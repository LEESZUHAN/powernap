import Foundation
import Combine
import SwiftUI
import CoreMotion
import HealthKit

// 導入實際服務類和模型
// 注意：不需要特殊導入，因為同一目標下的文件直接可見

/// 電源休息視圖模型，處理應用程序的UI邏輯和業務邏輯
@MainActor
class PowerNapViewModel: ObservableObject {
    // 服務依賴
    private let healthKitService: HealthKitService
    private let motionService: MotionService
    private let notificationService = NotificationService()
    private lazy var sleepDetectionService: SleepDetectionService = SleepDetectionService(
        healthKitService: healthKitService,
        motionService: motionService
    )
    
    // 計時器
    private var napTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // 發布的基本屬性
    @Published var selectedDuration: Int = 20 // 默認20分鐘
    @Published var timeRemaining: Int = 20 * 60 // 秒
    @Published var progress: Double = 0.0
    @Published var isSessionActive: Bool = false
    @Published var isPaused: Bool = false
    @Published var isCompleted: Bool = false
    @Published var showSettings: Bool = false
    
    // 震動與聲音設置
    @Published var hapticStrength: Int = 1 // 0-輕微, 1-中等, 2-強烈
    @Published var soundEnabled: Bool = true
    
    // 睡眠監測相關屬性
    @Published var isSleepDetectionEnabled: Bool = true
    @Published var sleepDetected: Bool = false
    @Published var sleepStartTime: Date? = nil
    @Published var sleepState: SleepState = .awake
    @Published var monitoringStatus: String = "等待開始"
    @Published var hrvValue: Double = 0
    @Published var baselineHRV: Double = 0
    @Published var motionLevel: Double = 0
    @Published var isStill: Bool = false
    
    // 可用的持續時間選項
    let availableDurations = Array(1...30) // 1到30分鐘
    
    // MARK: - 初始化
    
    init(
        healthKitService: HealthKitService? = nil,
        motionService: MotionService = MotionService()
    ) {
        self.healthKitService = healthKitService ?? HealthKitService()
        self.motionService = motionService
        setupBindings()
        
        // 初始化通知服務
        notificationService.initialize()
        
        // 載入設置
        loadUserPreferences()
    }
    
    // 加載用戶偏好設置
    private func loadUserPreferences() {
        let defaults = UserDefaults.standard
        
        // 載入震動強度
        hapticStrength = defaults.integer(forKey: "hapticStrength")
        if defaults.object(forKey: "hapticStrength") == nil {
            hapticStrength = 1 // 默認中等強度
            defaults.set(1, forKey: "hapticStrength")
        }
        
        // 載入聲音設置
        soundEnabled = defaults.bool(forKey: "soundEnabled")
        if defaults.object(forKey: "soundEnabled") == nil {
            soundEnabled = true // 默認開啟聲音
            defaults.set(true, forKey: "soundEnabled")
        }
        
        // 載入選定持續時間
        selectedDuration = defaults.integer(forKey: "napDuration")
        if selectedDuration == 0 {
            selectedDuration = 5 // 默認5分鐘
            defaults.set(5, forKey: "napDuration")
        }
        
        // 更新倒計時
        timeRemaining = selectedDuration * 60
    }
    
    // 保存用戶偏好設置
    func saveUserPreferences() {
        let defaults = UserDefaults.standard
        defaults.set(hapticStrength, forKey: "hapticStrength")
        defaults.set(soundEnabled, forKey: "soundEnabled")
        defaults.set(selectedDuration, forKey: "napDuration")
    }
    
    // 設置綁定
    private func setupBindings() {
        // 訂閱睡眠檢測服務的變化
        sleepDetectionService.$sleepDetected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.sleepDetected = value
                if value && self?.sleepStartTime == nil {
                    self?.onSleepDetected()
                }
            }
            .store(in: &cancellables)
        
        sleepDetectionService.$currentSleepState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.sleepState = value
                self?.updateMonitoringStatus()
            }
            .store(in: &cancellables)
        
        sleepDetectionService.$sleepStartTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.sleepStartTime = value
            }
            .store(in: &cancellables)
        
        // 訂閱 HRV 和動作數據
        healthKitService.$latestHRV
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.hrvValue = value
            }
            .store(in: &cancellables)
        
        healthKitService.$baselineHRV
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.baselineHRV = value
            }
            .store(in: &cancellables)
        
        motionService.$currentMotionLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.motionLevel = value
            }
            .store(in: &cancellables)
        
        motionService.$isStill
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.isStill = value
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 公共方法
    
    /// 開始休息會話
    func startNap() {
        guard !isSessionActive else { return }
        
        // 更新狀態
        isSessionActive = true
        isPaused = false
        isCompleted = false
        progress = 0.0
        monitoringStatus = "監測中"
        
        // 如果啟用了睡眠檢測，開始監測
        if isSleepDetectionEnabled {
            Task {
                do {
                    try await sleepDetectionService.startSleepDetection()
                } catch {
                    print("啟動睡眠檢測失敗: \(error)")
                }
            }
        }
        
        // 開始計時
        startNapTimer()
    }
    
    /// 暫停休息會話
    func pauseNap() {
        guard isSessionActive && !isPaused else { return }
        
        // 暫停計時器
        napTimer?.invalidate()
        napTimer = nil
        
        // 更新狀態
        isPaused = true
        monitoringStatus = "已暫停"
    }
    
    /// 繼續休息會話
    func resumeNap() {
        guard isSessionActive && isPaused else { return }
        
        // 重新開始計時
        startNapTimer()
        
        // 更新狀態
        isPaused = false
        monitoringStatus = "監測中"
    }
    
    /// 停止休息會話
    func stopNap() {
        // 停止計時器
        napTimer?.invalidate()
        napTimer = nil
        
        // 如果啟用了睡眠檢測，停止監測
        if isSleepDetectionEnabled {
            Task {
                do {
                    try await sleepDetectionService.stopSleepDetection()
                } catch {
                    print("停止睡眠檢測失敗: \(error)")
                }
            }
        }
        
        // 重置狀態
        isSessionActive = false
        isPaused = false
        isCompleted = false
        progress = 0.0
        timeRemaining = selectedDuration * 60
        sleepDetected = false
        sleepStartTime = nil
        monitoringStatus = "等待開始"
    }
    
    /// 設置選定的持續時間
    func setDuration(_ minutes: Int) {
        guard !isSessionActive else { return }
        
        selectedDuration = minutes
        timeRemaining = minutes * 60
    }
    
    /// 切換睡眠檢測功能
    func toggleSleepDetection(_ enabled: Bool) {
        isSleepDetectionEnabled = enabled
    }
    
    // MARK: - 私有方法
    
    /// 處理檢測到睡眠的情況
    private func onSleepDetected() {
        print("檢測到睡眠，開始計時")
        
        // 開始計時，從檢測到睡眠的時間開始
        startNapTimer()
        
        // 更新狀態
        monitoringStatus = "睡眠中"
    }
    
    /// 啟動休息計時器
    private func startNapTimer() {
        napTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                if self.timeRemaining > 0 {
                    self.timeRemaining -= 1
                    self.updateProgress()
                } else {
                    self.completeNap()
                }
            }
        }
    }
    
    /// 完成休息會話
    private func completeNap() {
        // 停止計時器
        napTimer?.invalidate()
        
        // 發送喚醒通知
        sendWakeupNotification()
        
        // 停止睡眠檢測
        if isSleepDetectionEnabled {
            Task {
                do {
                    try await sleepDetectionService.stopSleepDetection()
                } catch {
                    print("停止睡眠檢測失敗: \(error)")
                }
            }
        }
        
        // 更新狀態
        isCompleted = true
        isSessionActive = false
        isPaused = false
        progress = 1.0
        monitoringStatus = "已完成"
    }
    
    /// 發送喚醒通知
    private func sendWakeupNotification() {
        // 使用增強版的通知服務喚醒用戶
        notificationService.wakeupUser(
            vibrationStrength: hapticStrength,
            withSound: soundEnabled
        )
    }
    
    /// 更新進度
    private func updateProgress() {
        let totalSeconds = selectedDuration * 60
        progress = Double(totalSeconds - timeRemaining) / Double(totalSeconds)
    }
    
    /// 更新監測狀態
    private func updateMonitoringStatus() {
        if !isSessionActive {
            monitoringStatus = "等待開始"
            return
        }
        
        if sleepDetected {
            monitoringStatus = "睡眠中"
        } else {
            switch sleepState {
            case .awake:
                monitoringStatus = "監測中"
            case .potentialSleep:
                monitoringStatus = "可能入睡"
            case .asleep:
                monitoringStatus = "睡眠中"
            case .disturbed:
                monitoringStatus = "睡眠受干擾"
            }
        }
    }
    
    /// 格式化剩餘時間
    func formattedTimeRemaining() -> String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // MARK: - 公共輔助方法
    
    /// 獲取HRV狀態描述
    func getHRVDescription() -> String {
        if baselineHRV <= 0 {
            return "等待HRV數據"
        }
        
        if hrvValue <= 0 {
            return "監測中..."
        }
        
        let threshold = baselineHRV * 1.15
        if hrvValue >= threshold {
            return "HRV增加: \(Int(hrvValue)) ms"
        } else {
            return "HRV正常: \(Int(hrvValue)) ms"
        }
    }
    
    /// 獲取動作狀態描述
    func getMotionDescription() -> String {
        return isStill ? "靜止中" : "有動作: \(String(format: "%.3f", motionLevel))"
    }
    
    /// 獲取睡眠檢測狀態描述
    func getSleepDetectionStatus() -> String {
        if !isSleepDetectionEnabled {
            return "睡眠檢測已禁用"
        }
        
        return sleepDetectionService.sleepStateDescription
    }
} 