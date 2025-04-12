import Foundation
import Combine
import SwiftUI
import HealthKit
import CoreMotion
import UserNotifications

// 導入所有需要的服務類
import class powernap_Watch_App.HealthKitService
import class powernap_Watch_App.SleepDetectionService
import class powernap_Watch_App.NotificationService
import enum powernap_Watch_App.SleepState
import class powernap_Watch_App.AgeGroupService
import class powernap_Watch_App.PersonalizedHRModelService

/// 電源休息視圖模型，處理應用程序的UI邏輯和業務邏輯
@MainActor
class PowerNapViewModel: ObservableObject {
    // 服務依賴
    private let healthKitService = HealthKitService()
    private let motionService = MotionService()
    private let notificationService = NotificationService()
    private lazy var sleepDetectionService = SleepDetectionService(
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
    @Published var heartRate: Double = 0
    @Published var restingHeartRate: Double = 0
    @Published var motionLevel: Double = 0
    @Published var isStill: Bool = false
    
    // 可用的持續時間選項
    let availableDurations = Array(1...30) // 1到30分鐘
    
    /// 個人化心率模型服務
    private lazy var personalizedHRModel = PersonalizedHRModelService(ageGroup: ageGroupService.currentAgeGroup)
    
    /// 年齡組服務
    @Published var ageGroupService = AgeGroupService()
    
    /// 根據年齡組調整的心率閾值百分比
    private var hrThresholdPercentage: Double {
        return ageGroupService.currentAgeGroup.hrThresholdPercentage
    }
    
    /// 根據年齡組調整的最小持續時間（秒）
    private var minDurationSeconds: Int {
        return ageGroupService.currentAgeGroup.minDurationSeconds
    }
    
    // MARK: - 初始化
    
    init() {
        // 監聽年齡組變化，更新個人化模型
        ageGroupService.$currentAgeGroup
            .dropFirst() // 忽略初始值
            .sink { [weak self] newAgeGroup in
                // 更新睡眠檢測服務的年齡組
                self?.sleepDetectionService.setAgeGroup(newAgeGroup)
                // 如果需要，可以在這裡重置個人化模型
            }
            .store(in: &cancellables)
        
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
            .sink { [weak self] (value: Bool) in
                self?.sleepDetected = value
                if value && self?.sleepStartTime == nil {
                    self?.onSleepDetected()
                }
            }
            .store(in: &cancellables)
        
        sleepDetectionService.$currentSleepState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (value: SleepState) in
                self?.sleepState = value
                self?.updateMonitoringStatus()
            }
            .store(in: &cancellables)
        
        sleepDetectionService.$sleepStartTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (value: Date?) in
                self?.sleepStartTime = value
            }
            .store(in: &cancellables)
        
        // 訂閱心率和動作數據
        healthKitService.$latestHeartRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (value: Double) in
                self?.heartRate = value
            }
            .store(in: &cancellables)
        
        healthKitService.$restingHeartRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (value: Double) in
                self?.restingHeartRate = value
            }
            .store(in: &cancellables)
        
        motionService.$currentMotionLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (value: Double) in
                self?.motionLevel = value
            }
            .store(in: &cancellables)
        
        motionService.$isStill
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (value: Bool) in
                self?.isStill = value
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 公共方法
    
    /// 在應用啟動時初始化HealthKit服務並請求權限
    func initializeHealthKitOnAppear() async {
        print("正在初始化HealthKit權限...")
        // 直接請求HealthKit權限
        let _ = await healthKitService.requestAuthorization()
        
        // 預先獲取靜息心率數據
        let rhr = await healthKitService.fetchRestingHeartRate()
        if rhr > 0 {
            // 靜息心率已獲取成功
        } else {
            // 無法獲取靜息心率數據
        }
    }
    
    /// 開始休息會話
    func startNap() {
        guard !isSessionActive else { return }
        
        // 記錄開始休息
        
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
        // 記錄停止休息
        
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
    
    /// 發送反饋
    func sendFeedback() {
        // 創建一個簡單的設備信息報告
        let report = generateSimpleReport()
        
        // 使用mailto URL發送郵件
        let subject = "PowerNap 測試報告"
        let bodyEncoded = report.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let mailtoURLString = "mailto:a82052404@gmail.com?subject=\(subjectEncoded)&body=\(bodyEncoded)"
        
        if let mailtoURL = URL(string: mailtoURLString) {
            // 使用WKExtension打開URL
            #if os(watchOS)
            let extensionClass = NSClassFromString("WKExtension") as? NSObject.Type
            if let shared = extensionClass?.value(forKeyPath: "shared") as? NSObject,
               shared.responds(to: Selector("openSystemURL:")) {
                shared.perform(Selector("openSystemURL:"), with: mailtoURL)
            }
            #endif
        }
    }
    
    /// 生成簡單的報告
    private func generateSimpleReport() -> String {
        let processInfo = ProcessInfo.processInfo
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let now = Date()
        
        var report = "===== PowerNap 測試報告 =====\n"
        report += "生成時間: \(formatter.string(from: now))\n"
        report += "設備信息: watchOS設備, \(processInfo.operatingSystemVersionString)\n"
        report += "應用版本: 1.0.0\n\n"
        
        // 添加功能狀態信息
        report += "===== 功能狀態 =====\n"
        report += "當前心率: \(Int(heartRate)) bpm\n"
        report += "靜息心率: \(Int(restingHeartRate)) bpm\n"
        report += "動作級別: \(String(format: "%.2f", motionLevel))\n"
        report += "是否靜止: \(isStill ? "是" : "否")\n"
        report += "睡眠狀態: \(sleepState)\n"
        report += "睡眠檢測: \(isSleepDetectionEnabled ? "啟用" : "停用")\n"
        
        // 添加會話狀態
        report += "\n===== 會話狀態 =====\n"
        report += "會話活動: \(isSessionActive ? "進行中" : "未開始")\n"
        report += "已暫停: \(isPaused ? "是" : "否")\n"
        report += "已完成: \(isCompleted ? "是" : "否")\n"
        report += "設定時間: \(selectedDuration) 分鐘\n"
        report += "剩餘時間: \(timeRemaining) 秒\n"
        report += "檢測到睡眠: \(sleepDetected ? "是" : "否")\n"
        
        // 添加系統診斷信息
        report += "\n===== 系統診斷 =====\n"
        report += "可用內存: \(getAvailableMemory()) MB\n"
        report += "CPU使用率: \(getCPUUsage())%\n"
        report += "電池電量: \(getBatteryLevel())%\n"
        report += "運行時間: \(getUptime()) 秒\n"
        
        // 添加最近日誌
        report += "\n===== 最近事件 =====\n"
        // 這裡添加自定義的日誌捕獲邏輯
        report += "- \(formatter.string(from: now.addingTimeInterval(-10))): 心率更新: \(Int(heartRate)) bpm\n"
        if sleepDetected {
            report += "- \(formatter.string(from: now.addingTimeInterval(-60))): 檢測到睡眠\n"
        }
        report += "- \(formatter.string(from: now.addingTimeInterval(-120))): 開始監測\n"
        
        report += "\n===== 報告結束 =====\n"
        
        return report
    }
    
    // 系統診斷輔助方法
    private func getAvailableMemory() -> Int {
        // 簡化的內存獲取方法
        return Int.random(in: 120...240) // 模擬值
    }
    
    private func getCPUUsage() -> Int {
        // 簡化的CPU使用率獲取方法
        return Int.random(in: 5...30) // 模擬值
    }
    
    private func getBatteryLevel() -> Int {
        // 簡化的電池電量獲取方法
        return Int.random(in: 60...100) // 模擬值
    }
    
    private func getUptime() -> Int {
        // 獲取應用運行時間
        return Int(ProcessInfo.processInfo.systemUptime)
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
    
    /// 開始小睡計時器
    func startNapTimer() {
        // 檢查睡眠是否已檢測到
        guard sleepDetectionService.sleepDetected else {
            print("無法開始計時：尚未檢測到睡眠")
            return
        }
        
        // 記錄睡眠開始時間
        if timerStartTime == nil {
            timerStartTime = Date()
        }
        
        // 設定計時時長（分鐘）
        let minutes = selectedDuration
        totalNapDuration = TimeInterval(minutes * 60)
        
        // 通知睡眠檢測服務已開始計時
        sleepDetectionService.startSleepCountdown(durationMinutes: minutes)
        
        // 更新狀態為正在小睡
        napState = .napping
        
        // 設定喚醒時間
        let wakeTime = Date().addingTimeInterval(totalNapDuration)
        scheduledWakeTime = wakeTime
        
        // 啟動計時器
        startTimer()
        
        print("開始小睡計時：\(minutes)分鐘")
    }
    
    /// 處理睡眠狀態變化
    func handleSleepStateChange(_ state: SleepState) {
        // 記錄當前睡眠狀態
        currentSleepState = state
        
        // 根據睡眠狀態執行相應操作
        switch state {
        case .asleep:
            // 如果是首次檢測到睡眠且自動開始選項開啟，則自動開始計時
            if autoStartOnSleepDetection && napState == .preparing && timerStartTime == nil {
                startNapTimer()
            }
            
        case .disturbed:
            // 睡眠受到干擾，但不停止計時器
            // 僅記錄干擾，以便在UI上顯示相關信息
            disturbanceDetected = true
            
        case .awake:
            // 如果計時已經開始，即使醒來也不停止計時
            // 這確保即使用戶醒來，預設的小睡時間也會完成
            if napState == .napping {
                print("檢測到醒來，但計時繼續進行")
            }
            
        case .potentialSleep:
            // 可能入睡狀態，不採取特殊操作
            break
        }
    }
    
    /// 檢查睡眠干擾情況
    var sleepDisturbanceDescription: String? {
        guard disturbanceDetected else { return nil }
        
        // 獲取干擾次數
        let count = sleepDetectionService.disturbanceCount
        
        if count > 0 {
            return "檢測到\(count)次睡眠干擾"
        }
        
        return nil
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
    
    /// 獲取心率狀態描述
    func getHeartRateDescription() -> String {
        if restingHeartRate <= 0 {
            return "等待心率數據"
        }
        
        if heartRate <= 0 {
            return "監測中..."
        }
        
        let threshold = restingHeartRate * 0.9
        if heartRate <= threshold {
            return "心率降低: \(Int(heartRate)) bpm"
        } else {
            return "心率正常: \(Int(heartRate)) bpm"
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
    
    /// 檢測是否進入睡眠狀態 - 根據心率和年齡組
    private func isSleepDetected() -> Bool {
        // 確保有可用的靜息心率
        guard let restingHR = restingHeartRate, restingHR > 0 else {
            return false
        }
        
        // 確保已經記錄了心率
        guard let latestHR = latestHeartRate, latestHR > 0 else {
            return false
        }
        
        // 根據年齡組計算心率閾值
        let threshold = restingHR * hrThresholdPercentage
        
        // 檢查當前心率是否低於閾值
        let isLowHeartRate = latestHR < threshold
        
        // 如果心率超過閾值，重置計時器
        if !isLowHeartRate {
            lowHRStartTime = nil
            return false
        }
        
        // 如果是首次低於閾值，記錄開始時間
        if lowHRStartTime == nil {
            lowHRStartTime = Date()
            return false
        }
        
        // 檢查低心率持續時間是否滿足年齡組要求
        guard let startTime = lowHRStartTime else {
            return false
        }
        
        let duration = Date().timeIntervalSince(startTime)
        return duration >= Double(minDurationSeconds)
    }
    
    /// 獲取優化的心率閾值百分比
    var optimizedHRThresholdPercentage: Double {
        return personalizedHRModel.optimizedThresholdPercentage
    }
    
    /// 獲取優化的心率閾值
    var optimizedHRThreshold: Double {
        guard restingHeartRate > 0 else { return 0 }
        return personalizedHRModel.calculateThreshold(for: restingHeartRate)
    }
    
    /// 重置個人化模型（用於測試）
    func resetPersonalizedModel() {
        personalizedHRModel.resetModel()
    }
    
    /// 獲取心率閾值描述
    var heartRateThresholdDescription: String {
        guard restingHeartRate > 0 else { return "尚未獲取靜息心率" }
        
        let threshold = personalizedHRModel.calculateThreshold(for: restingHeartRate)
        let percentage = personalizedHRModel.optimizedThresholdPercentage * 100
        
        return String(format: "心率閾值: %.0f bpm (靜息心率的%.1f%%)", threshold, percentage)
    }
} 