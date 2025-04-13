import Foundation
import Combine
import SwiftUI
import CoreMotion
import HealthKit

/// 睡眠狀態
public enum SleepState: String {
    case awake = "清醒"
    case potentialSleep = "可能入睡"
    case asleep = "睡眠中"
    case disturbed = "睡眠受干擾"
}

/// 睡眠檢測服務，整合心率監測和動作監測
@MainActor
class SleepDetectionService: ObservableObject, @unchecked Sendable {
    // 依賴服務的引用
    private let healthKitService: HealthKitService
    private let motionService: MotionService
    
    // 觀察者集合
    private var cancellables = Set<AnyCancellable>()
    private var sleepDetectionTimer: Timer?
    
    // 睡眠檢測參數
    private let sleepConfirmationTime: TimeInterval = 180 // 需要連續滿足睡眠條件的時間（秒），默認3分鐘
    private let heartRateThreshold: Double = 0.9 // 心率閾值（靜息心率的90%）
    private let motionStillThresholdTime: TimeInterval = 120 // 需要保持靜止的時間（秒）
    
    // 潛在睡眠開始時間
    private var potentialSleepStartTime: Date?
    
    // 發布的變量
    @Published var currentSleepState: SleepState = .awake
    @Published var timeInCurrentState: TimeInterval = 0
    @Published var sleepDetected: Bool = false
    @Published var sleepStartTime: Date?
    @Published var lastStateChangeTime: Date = Date()
    @Published var isSleepConditionMet: Bool = false
    
    // 睡眠條件滿足的詳細情況
    @Published var isHeartRateConditionMet: Bool = false
    @Published var isMotionConditionMet: Bool = false
    
    // 心率和動作數據
    @Published var currentHeartRate: Double = 0
    @Published var restingHeartRate: Double = 0
    @Published var heartRateThresholdValue: Double = 0
    @Published var currentMotionLevel: Double = 0
    
    // 睡眠檢測狀態
    @Published var sleepStateDescription: String = "監測中"
    
    // 檢測設置
    private var ageGroup: AgeGroup = .adult  // 預設為成人組
    private var motionThreshold: Double = 0.3  // 動作閾值，超過此值視為有顯著動作
    
    // 睡眠干擾相關參數
    private var disturbanceStartTime: Date? = nil
    private let maxDisturbanceDuration: TimeInterval = 60 // 最大允許的干擾時間，超過視為醒來（默認60秒）
    @Published var disturbanceCount: Int = 0 // 睡眠過程中的干擾次數
    
    // 是否正在計時中（睡眠檢測已啟動且正在倒數）
    @Published var isCountdownActive: Bool = false
    
    // 個人化心率模型
    private let personalizedHRModel: PersonalizedHRModelService
    
    // 收集的心率數據
    private var collectedHeartRates: [Double] = []
    
    /// 初始化
    init(healthKitService: HealthKitService, motionService: MotionService) {
        self.healthKitService = healthKitService
        self.motionService = motionService
        self.personalizedHRModel = PersonalizedHRModelService(ageGroup: .adult) // 默認成人組
        
        // 訂閱心率和動作服務的變化
        setupSubscriptions()
    }
    
    /// 設置數據訂閱
    private func setupSubscriptions() {
        // 訂閱心率數據變化
        healthKitService.$latestHeartRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (value: Double) in
                self?.currentHeartRate = value
                self?.updateHeartRateCondition()
            }
            .store(in: &cancellables)
        
        healthKitService.$restingHeartRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (value: Double) in
                self?.restingHeartRate = value
                self?.heartRateThresholdValue = value * (self?.heartRateThreshold ?? 0.9)
                self?.updateHeartRateCondition()
            }
            .store(in: &cancellables)
        
        // 訂閱動作數據變化
        motionService.$isStill
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (isStill: Bool) in
                self?.updateMotionCondition()
            }
            .store(in: &cancellables)
        
        motionService.$currentMotionLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (level: Double) in
                self?.currentMotionLevel = level
            }
            .store(in: &cancellables)
        
        motionService.$stillDuration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (duration: TimeInterval) in
                self?.updateMotionCondition()
            }
            .store(in: &cancellables)
    }
    
    /// 開始睡眠檢測
    func startSleepDetection() async throws {
        print("開始睡眠檢測服務")
        
        // 重置睡眠狀態
        resetSleepState()
        
        // 獲取靜息心率
        if restingHeartRate <= 0 {
            let rhr = await healthKitService.fetchRestingHeartRate()
            if rhr > 0 {
                restingHeartRate = rhr
            }
        }
        
        // 開始心率監測
        try await healthKitService.startHeartRateMonitoring()
        
        // 開始動作監測
        motionService.startMotionUpdates()
        
        // 啟動定時評估
        startEvaluationTimer()
    }
    
    /// 停止睡眠檢測
    func stopSleepDetection() async throws {
        print("停止睡眠檢測服務")
        
        // 停止心率監測
        try await healthKitService.stopHeartRateMonitoring()
        
        // 停止動作監測
        motionService.stopMotionUpdates()
        
        // 如果已經檢測到睡眠，並且收集了足夠的心率數據，更新個人化模型
        if sleepDetected && !collectedHeartRates.isEmpty {
            personalizedHRModel.addSleepHeartRateData(
                heartRates: collectedHeartRates, 
                restingHeartRate: restingHeartRate
            )
            
            // 清空收集的數據
            collectedHeartRates = []
        }
        
        // 停止定時評估
        stopEvaluationTimer()
        
        // 重置睡眠狀態
        resetSleepState()
    }
    
    /// 重置睡眠狀態
    private func resetSleepState() {
        DispatchQueue.main.async {
            self.currentSleepState = .awake
            self.timeInCurrentState = 0
            self.sleepDetected = false
            self.sleepStartTime = nil
            self.lastStateChangeTime = Date()
            self.isSleepConditionMet = false
            self.isHeartRateConditionMet = false
            self.isMotionConditionMet = false
            self.potentialSleepStartTime = nil
        }
    }
    
    /// 更新心率條件
    private func updateHeartRateCondition() {
        // 確保有靜息心率和當前心率
        guard restingHeartRate > 0, currentHeartRate > 0 else {
            DispatchQueue.main.async {
                self.isHeartRateConditionMet = false
            }
            return
        }
        
        // 收集心率數據用於後續模型更新
        if sleepDetected {
            collectedHeartRates.append(currentHeartRate)
        }
        
        // 獲取優化的閾值百分比
        let optimizedThreshold = personalizedHRModel.optimizedThresholdPercentage
        
        // 檢查是否有當日激烈活動，需要調整閾值
        if motionService.hasDailyIntenseActivity {
            personalizedHRModel.adjustForDailyActivity(
                activityLevel: motionService.peakActivityLevel,
                restingHeartRate: restingHeartRate
            )
        }
        
        // 計算心率閾值
        let threshold = restingHeartRate * optimizedThreshold
        
        // 檢查當前心率是否低於閾值
        let isLowHeartRate = currentHeartRate < threshold
        
        DispatchQueue.main.async {
            self.isHeartRateConditionMet = isLowHeartRate
            self.checkAllSleepConditions()
        }
    }
    
    /// 更新動作條件
    private func updateMotionCondition() {
        // 檢查是否已經靜止足夠時間
        let isStillEnough = motionService.hasUserBeenStillFor(seconds: Int(motionStillThresholdTime))
        
        DispatchQueue.main.async {
            self.isMotionConditionMet = isStillEnough
            self.checkAllSleepConditions()
        }
    }
    
    /// 檢查所有睡眠條件
    private func checkAllSleepConditions() {
        let allConditionsMet = isHeartRateConditionMet && isMotionConditionMet
        
        if isSleepConditionMet != allConditionsMet {
            isSleepConditionMet = allConditionsMet
            
            // 條件轉變時記錄時間
            if allConditionsMet {
                potentialSleepStartTime = Date()
            } else {
                potentialSleepStartTime = nil
            }
        }
    }
    
    /// 啟動評估計時器
    private func startEvaluationTimer() {
        // 每15秒評估一次睡眠狀態
        sleepDetectionTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.evaluateSleepState()
        }
    }
    
    /// 停止評估計時器
    private func stopEvaluationTimer() {
        sleepDetectionTimer?.invalidate()
        sleepDetectionTimer = nil
    }
    
    /// 評估睡眠狀態 - 整合心率和動作數據
    private func evaluateSleepState() {
        // 確保有靜息心率數據
        guard restingHeartRate > 0 else {
            updateSleepState(.awake, description: "等待心率數據")
            return
        }
        
        // 檢查心率條件
        let isHeartRateLow = checkHeartRateCondition()
        
        // 檢查動作條件
        let isMotionStill = checkMotionCondition()
        
        // 根據兩個條件綜合判斷
        if isHeartRateLow && isMotionStill {
            // 兩個條件都滿足，標記為睡眠
            if !sleepDetected {
                sleepDetected = true
                sleepStartTime = Date()
            } else if currentSleepState == .disturbed {
                // 從干擾恢復到睡眠
                disturbanceStartTime = nil
                print("從干擾中恢復到睡眠狀態")
            }
            updateSleepState(.asleep, description: "已檢測到睡眠")
        } else if isHeartRateLow {
            // 僅心率條件滿足
            handlePartialSleepCondition(.potentialSleep, description: "心率降低，可能入睡")
        } else if isMotionStill {
            // 僅動作條件滿足
            handlePartialSleepCondition(.potentialSleep, description: "靜止中，可能入睡")
        } else {
            // 兩個條件都不滿足
            if !sleepDetected {
                // 若尚未入睡，直接更新為清醒
                updateSleepState(.awake, description: "清醒")
            } else {
                // 已經入睡，現在遇到干擾
                handleSleepDisturbance()
            }
        }
    }
    
    /// 處理部分滿足睡眠條件的情況（心率或動作單獨滿足）
    private func handlePartialSleepCondition(_ state: SleepState, description: String) {
        if !sleepDetected {
            // 尚未入睡，更新為可能入睡
            updateSleepState(state, description: description)
        } else if currentSleepState == .disturbed {
            // 已經入睡但目前受干擾，保持干擾狀態不變
            // 但不重置干擾時間，因為仍未恢復完全睡眠條件
        } else {
            // 已經入睡，但條件變弱，視為輕微干擾但不改變狀態
            // 這裡可以記錄一些統計信息，但不改變主要狀態
        }
    }
    
    /// 處理睡眠過程中的干擾
    private func handleSleepDisturbance() {
        // 如果是首次檢測到干擾，記錄開始時間
        if disturbanceStartTime == nil {
            disturbanceStartTime = Date()
            disturbanceCount += 1
            print("檢測到睡眠干擾 #\(disturbanceCount)")
        }
        
        // 檢查干擾持續時間
        guard let startTime = disturbanceStartTime else { return }
        
        let disturbanceDuration = Date().timeIntervalSince(startTime)
        
        if disturbanceDuration > maxDisturbanceDuration {
            // 干擾持續時間過長，判定為真正醒來
            if isCountdownActive {
                // 如果正在計時，不要停止計時
                // 但記錄用戶醒來的狀態以供顯示
                print("長時間干擾，但保持計時繼續")
                updateSleepState(.awake, description: "已醒來，但計時繼續")
            } else {
                // 如果只是在睡眠檢測階段，重置睡眠狀態
                print("長時間干擾，判定為完全醒來")
                sleepDetected = false
                sleepStartTime = nil
                disturbanceStartTime = nil
                updateSleepState(.awake, description: "已完全醒來")
            }
        } else {
            // 干擾時間未超過閾值，視為短暫干擾
            updateSleepState(.disturbed, description: "睡眠受干擾(\(Int(disturbanceDuration))秒)")
        }
    }
    
    /// 檢查心率條件 - 使用個人化模型
    private func checkHeartRateCondition() -> Bool {
        // 確保有心率數據
        guard currentHeartRate > 0 else { return false }
        
        // 收集心率數據用於後續模型更新
        if sleepDetected {
            collectedHeartRates.append(currentHeartRate)
        }
        
        // 獲取優化的閾值百分比
        let optimizedThreshold = personalizedHRModel.optimizedThresholdPercentage
        
        // 檢查是否有當日激烈活動，需要調整閾值
        if motionService.hasDailyIntenseActivity {
            personalizedHRModel.adjustForDailyActivity(
                activityLevel: motionService.peakActivityLevel,
                restingHeartRate: restingHeartRate
            )
        }
        
        // 計算心率閾值
        let threshold = restingHeartRate * optimizedThreshold
        
        // 檢查當前心率是否低於閾值
        let isLowHeartRate = currentHeartRate < threshold
        
        return isLowHeartRate
    }
    
    /// 檢查動作條件
    private func checkMotionCondition() -> Bool {
        // 檢查是否靜止
        let isUserStill = motionService.isStill && currentMotionLevel < motionThreshold
        
        // 如果有顯著動作，重置計時器
        if !isUserStill {
            return false
        }
        
        return true
    }
    
    /// 更新睡眠狀態並發佈描述
    private func updateSleepState(_ state: SleepState, description: String) {
        if currentSleepState != state {
            currentSleepState = state
            lastStateChangeTime = Date()
            timeInCurrentState = 0
        } else {
            timeInCurrentState = Date().timeIntervalSince(lastStateChangeTime)
        }
        
        DispatchQueue.main.async {
            self.sleepStateDescription = description
        }
    }
    
    /// 獲取當前心率狀態的描述 - 使用優化閾值
    var heartRateConditionDescription: String {
        guard restingHeartRate > 0 else {
            return "等待靜息心率數據"
        }
        
        let threshold = restingHeartRate * personalizedHRModel.optimizedThresholdPercentage
        
        return isHeartRateConditionMet ? 
            "心率良好: \(String(format: "%.0f", currentHeartRate)) < \(String(format: "%.0f", threshold))" :
            "心率過高: \(String(format: "%.0f", currentHeartRate)) > \(String(format: "%.0f", threshold))"
    }
    
    /// 獲取當前動作狀態的描述
    var motionConditionDescription: String {
        return isMotionConditionMet ?
            "靜止中: \(Int(motionService.stillDuration))秒" :
            "有動作: \(String(format: "%.3f", currentMotionLevel))"
    }
    
    /// 設置年齡組
    func setAgeGroup(_ newAgeGroup: AgeGroup) {
        ageGroup = newAgeGroup
        // 如果需要，這裡也可以重新初始化個人化心率模型
    }
    
    /// 啟動睡眠倒計時（在檢測到睡眠後開始計時）
    func startSleepCountdown(durationMinutes: Int) {
        guard sleepDetected, let sleepStart = sleepStartTime else {
            print("無法啟動計時：尚未檢測到睡眠")
            return
        }
        
        isCountdownActive = true
        print("開始睡眠倒計時：\(durationMinutes)分鐘")
        
        // 通知倒計時開始的邏輯可以在這裡添加
    }
    
    /// 停止睡眠倒計時
    func stopSleepCountdown() {
        isCountdownActive = false
        print("停止睡眠倒計時")
        
        // 通知倒計時結束的邏輯可以在這裡添加
    }
} 