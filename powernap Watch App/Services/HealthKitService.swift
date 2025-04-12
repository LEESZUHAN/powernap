import Foundation
import HealthKit

/// HealthKit服務類，處理所有與健康數據相關的操作
@MainActor
class HealthKitService: ObservableObject, @unchecked Sendable {
    private let healthStore = HKHealthStore()
    private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let restingHeartRateType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
    
    /// 發布變量，用於更新UI
    @Published var isAuthorized = false
    @Published var latestHeartRate: Double = 0
    @Published var restingHeartRate: Double = 0
    
    /// 初始化，設置通知觀察者
    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBackgroundDelivery),
            name: NSNotification.Name(rawValue: "HKObserverQueryCompletionNotification"),
            object: nil
        )
    }
    
    /// 請求HealthKit權限
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit不可用")
            return false
        }
        
        let typesToRead: Set<HKObjectType> = [
            heartRateType,
            restingHeartRateType,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]
        
        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]
        
        do {
            try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)
            DispatchQueue.main.async {
                self.isAuthorized = true
            }
            return true
        } catch {
            print("獲取健康數據權限失敗: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 取得最新的靜息心率
    func fetchRestingHeartRate() async -> Double {
        let calendar = Calendar.current
        let now = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -7, to: now) else {
            return 0
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictEndDate)
        
        do {
            let results = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(
                    sampleType: restingHeartRateType,
                    predicate: predicate,
                    limit: 1,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
                ) { _, results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: results ?? [])
                    }
                }
                healthStore.execute(query)
            }
            
            if let sample = results.first as? HKQuantitySample {
                let value = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                DispatchQueue.main.async {
                    self.restingHeartRate = value
                }
                return value
            }
            return 0
        } catch {
            print("獲取靜息心率失敗: \(error.localizedDescription)")
            return 0
        }
    }
    
    /// 開始心率監測
    func startHeartRateMonitoring(callback: ((HeartRateReading) -> Void)? = nil) async throws {
        let query = HKObserverQuery(sampleType: heartRateType, predicate: nil) { [weak self] (query, completionHandler, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("心率觀察者查詢錯誤: \(error.localizedDescription)")
                completionHandler()
                return
            }
            
            // 當有新數據時，獲取最新的心率值
            Task { [weak self] in
                guard let self = self else { return }
                let heartRate = await self.fetchLatestHeartRate()
                if heartRate > 0, let callback = callback {
                    DispatchQueue.main.async {
                        callback(HeartRateReading(timestamp: Date(), value: heartRate))
                    }
                }
            }
            
            // 不要忘記調用完成處理程序
            completionHandler()
        }
        
        healthStore.execute(query)
        
        // 啟用背景更新
        try await healthStore.enableBackgroundDelivery(for: heartRateType, frequency: .immediate)
        print("心率背景更新已啟用")
    }
    
    /// 停止心率監測
    func stopHeartRateMonitoring() async throws {
        try await healthStore.disableBackgroundDelivery(for: heartRateType)
        print("心率背景更新已停用")
    }
    
    /// 取得最新的心率值
    @discardableResult
    func fetchLatestHeartRate() async -> Double {
        let calendar = Calendar.current
        let now = Date()
        guard let startDate = calendar.date(byAdding: .minute, value: -2, to: now) else {
            return 0
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictEndDate)
        
        do {
            let results = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(
                    sampleType: heartRateType,
                    predicate: predicate,
                    limit: 1,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
                ) { _, results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: results ?? [])
                    }
                }
                healthStore.execute(query)
            }
            
            if let sample = results.first as? HKQuantitySample {
                let value = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                DispatchQueue.main.async {
                    self.latestHeartRate = value
                }
                return value
            }
            return 0
        } catch {
            print("獲取最新心率失敗: \(error.localizedDescription)")
            return 0
        }
    }
    
    /// 判斷當前心率是否低於靜息心率的指定百分比閾值
    func isHeartRateBelowThreshold(currentHR: Double? = nil, threshold: Double = 0.9) -> Bool {
        let hrToCheck = currentHR ?? self.latestHeartRate
        let rhr = self.restingHeartRate
        
        // 如果沒有靜息心率或當前心率，返回false
        guard rhr > 0, hrToCheck > 0 else {
            return false
        }
        
        // 特殊情況處理：針對高訓練運動員（RHR 極低，40 bpm 以下）
        if rhr < 40 {
            // 使用心率下降 ≥ 5 bpm 作為輔助判準
            return hrToCheck <= (rhr - 5)
        }
        
        // 判斷是否低於閾值 (靜息心率 × 閾值百分比)
        return hrToCheck <= (rhr * threshold)
    }
    
    /// 處理背景交付通知
    @objc private func handleBackgroundDelivery() {
        Task { [weak self] in
            guard let self = self else { return }
            let _ = await self.fetchLatestHeartRate()
        }
    }
    
    /// 初始化心率監測系統
    func initializeHeartRateMonitoring() async -> Bool {
        // 請求授權
        let authorized = await requestAuthorization()
        if !authorized {
            return false
        }
        
        // 獲取靜息心率
        let rhr = await fetchRestingHeartRate()
        
        // 如果無法獲取靜息心率，設置默認值
        if rhr <= 0 {
            DispatchQueue.main.async {
                self.restingHeartRate = 65.0 // 設置為一個合理的默認值
            }
        }
        
        return true
    }
} 