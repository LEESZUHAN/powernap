import Foundation
import Combine
import SwiftUI

/// 睡眠狀態
public enum SleepState: String {
    case awake = "清醒"
    case potentialSleep = "潛在睡眠"
    case asleep = "睡眠中"
    case disturbed = "被干擾"
}

/// 睡眠檢測服務，整合 HRV 和動作監測，實現綜合睡眠判定
@MainActor
class SleepDetectionService: ObservableObject, @unchecked Sendable {
    // 依賴服務的引用，使用內建類型
    private let healthKitService: HealthKitService
    private let motionService: MotionService
    
    // 觀察者集合
    private var cancellables = Set<AnyCancellable>()
    private var sleepDetectionTimer: Timer?
    
    // 睡眠檢測參數
    private let sleepConfirmationTime: TimeInterval = 180 // 需要連續滿足睡眠條件的時間（秒）
    private let hrvThresholdMultiplier: Double = 1.15 // HRV 閾值倍數（基準線的1.15倍）
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
    @Published var isHrvConditionMet: Bool = false
    @Published var isMotionConditionMet: Bool = false
    
    // HRV 和動作數據
    @Published var currentHrv: Double = 0
    @Published var baselineHrv: Double = 0
    @Published var hrvThreshold: Double = 0
    @Published var currentMotionLevel: Double = 0
    
    /// 初始化
    init(healthKitService: HealthKitService, motionService: MotionService) {
        self.healthKitService = healthKitService
        self.motionService = motionService
        
        // 訂閱 HRV 和動作服務的變化
        setupSubscriptions()
    }
    
    /// 設置數據訂閱
    private func setupSubscriptions() {
        // 訂閱 HRV 數據變化
        healthKitService.$latestHRV
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (value: Double) in
                self?.currentHrv = value
                self?.updateHrvCondition()
            }
            .store(in: &cancellables)
        
        healthKitService.$baselineHRV
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (value: Double) in
                self?.baselineHrv = value
                self?.hrvThreshold = value * (self?.hrvThresholdMultiplier ?? 1.15)
                self?.updateHrvCondition()
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
        // 重置睡眠狀態
        resetSleepState()
        
        // 初始化 HealthKit
        let success = await healthKitService.initializeHRVMonitoring()
        if success {
            // 啟動 HRV 監測
            try await healthKitService.startHRVMonitoring()
        } else {
            throw NSError(domain: "SleepDetectionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "無法初始化 HealthKit 監測"])
        }
        
        // 開始動作監測
        motionService.startMonitoring()
        
        // 啟動睡眠狀態檢測計時器
        DispatchQueue.main.async {
            self.sleepDetectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.updateSleepState()
                }
            }
        }
    }
    
    /// 停止睡眠檢測
    func stopSleepDetection() async throws {
        // 停止 HRV 監測
        try await healthKitService.stopHRVMonitoring()
        
        // 停止動作監測
        motionService.stopMonitoring()
        
        // 停止計時器
        DispatchQueue.main.async {
            self.sleepDetectionTimer?.invalidate()
            self.sleepDetectionTimer = nil
        }
        
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
            self.isHrvConditionMet = false
            self.isMotionConditionMet = false
            self.potentialSleepStartTime = nil
        }
    }
    
    /// 更新 HRV 條件
    private func updateHrvCondition() {
        // 確保有基準值和當前值
        guard baselineHrv > 0, currentHrv > 0 else {
            DispatchQueue.main.async {
                self.isHrvConditionMet = false
            }
            return
        }
        
        // 判斷是否超過閾值
        let isMet = currentHrv >= (baselineHrv * hrvThresholdMultiplier)
        
        DispatchQueue.main.async {
            self.isHrvConditionMet = isMet
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
        let allConditionsMet = isHrvConditionMet && isMotionConditionMet
        
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
    
    /// 更新睡眠狀態
    private func updateSleepState() {
        // 更新當前狀態的持續時間
        timeInCurrentState = Date().timeIntervalSince(lastStateChangeTime)
        
        // 根據當前狀態和條件進行狀態轉換
        switch currentSleepState {
        case .awake:
            // 當所有條件滿足，轉入潛在睡眠狀態
            if isSleepConditionMet {
                transitionToState(.potentialSleep)
            }
            
        case .potentialSleep:
            // 如果不再滿足條件，回到清醒狀態
            if !isSleepConditionMet {
                transitionToState(.awake)
                return
            }
            
            // 檢查是否已達到確認睡眠所需的時間
            if let startTime = potentialSleepStartTime,
               Date().timeIntervalSince(startTime) >= sleepConfirmationTime {
                // 條件已持續足夠長時間，確認進入睡眠狀態
                transitionToState(.asleep)
                
                // 記錄睡眠開始時間
                DispatchQueue.main.async {
                    self.sleepStartTime = startTime
                    self.sleepDetected = true
                }
            }
            
        case .asleep:
            // 如果不再滿足條件，轉為被干擾狀態
            if !isSleepConditionMet {
                transitionToState(.disturbed)
            }
            
        case .disturbed:
            // 如果重新滿足條件，返回睡眠狀態
            if isSleepConditionMet {
                transitionToState(.asleep)
            }
            
            // 如果長時間不滿足條件，視為已醒來
            else if timeInCurrentState > 120 { // 2分鐘
                transitionToState(.awake)
                
                // 重置睡眠檢測
                DispatchQueue.main.async {
                    self.sleepDetected = false
                    self.sleepStartTime = nil
                }
            }
        }
    }
    
    /// 轉換睡眠狀態
    private func transitionToState(_ newState: SleepState) {
        if currentSleepState != newState {
            DispatchQueue.main.async {
                self.currentSleepState = newState
                self.lastStateChangeTime = Date()
                self.timeInCurrentState = 0
                
                print("睡眠狀態變更: \(self.currentSleepState.rawValue)")
            }
        }
    }
    
    /// 獲取可讀的睡眠狀態描述
    var sleepStateDescription: String {
        return currentSleepState.rawValue
    }
    
    /// 獲取當前 HRV 狀態的描述
    var hrvConditionDescription: String {
        guard baselineHrv > 0 else {
            return "等待基準 HRV 數據"
        }
        
        return isHrvConditionMet ? 
            "HRV 良好: \(String(format: "%.1f", currentHrv)) > \(String(format: "%.1f", hrvThreshold))" :
            "HRV 不足: \(String(format: "%.1f", currentHrv)) < \(String(format: "%.1f", hrvThreshold))"
    }
    
    /// 獲取當前動作狀態的描述
    var motionConditionDescription: String {
        return isMotionConditionMet ?
            "靜止中: \(Int(motionService.stillDuration))秒" :
            "有動作: \(String(format: "%.3f", currentMotionLevel))"
    }
} 