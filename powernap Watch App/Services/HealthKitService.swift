import Foundation
import HealthKit

/// HealthKit服務類，處理所有與健康數據相關的操作
@MainActor
class HealthKitService: ObservableObject, @unchecked Sendable {
    private let healthStore = HKHealthStore()
    private let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
    
    /// 發布變量，用於更新UI
    @Published var isAuthorized = false
    @Published var latestHRV: Double = 0
    @Published var baselineHRV: Double = 0
    @Published var daytimeBaselineHRV: Double = 0
    
    // 睡眠檢測的 HRV 閾值倍數
    private let hrvThresholdMultiplier: Double = 1.15
    
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
            hrvType,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!
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
    
    /// 取得過去7天的HRV平均值作為基準
    func fetchBaselineHRV() async -> Double {
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -7, to: endDate) else {
            return 0
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        do {
            let results = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: results ?? [])
                    }
                }
                healthStore.execute(query)
            }
            
            // 計算SDNN平均值
            var totalHRV = 0.0
            var count = 0
            
            for result in results {
                if let sample = result as? HKQuantitySample {
                    let value = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                    totalHRV += value
                    count += 1
                }
            }
            
            if count > 0 {
                let average = totalHRV / Double(count)
                DispatchQueue.main.async {
                    self.baselineHRV = average
                }
                return average
            }
            
            return 0
        } catch {
            print("獲取基準HRV失敗: \(error.localizedDescription)")
            return 0
        }
    }
    
    /// 取得過去7天內白天時段(6:00-22:00)的HRV平均值作為白天基準
    func fetchDaytimeBaselineHRV() async -> Double {
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -7, to: endDate) else {
            return 0
        }
        
        // 創建時間範圍查詢條件
        let dayTimePredicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        do {
            let results = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(sampleType: hrvType, predicate: dayTimePredicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: results ?? [])
                    }
                }
                healthStore.execute(query)
            }
            
            // 計算白天SDNN平均值 (只計算6:00-22:00之間的樣本)
            var totalHRV = 0.0
            var count = 0
            
            for result in results {
                if let sample = result as? HKQuantitySample {
                    // 檢查樣本時間是否在白天時段
                    let hour = calendar.component(.hour, from: sample.startDate)
                    if hour >= 6 && hour < 22 {
                        let value = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                        totalHRV += value
                        count += 1
                    }
                }
            }
            
            if count > 0 {
                let average = totalHRV / Double(count)
                DispatchQueue.main.async {
                    self.daytimeBaselineHRV = average
                }
                return average
            }
            
            return 0
        } catch {
            print("獲取白天基準HRV失敗: \(error.localizedDescription)")
            return 0
        }
    }
    
    /// 開始HRV監測
    func startHRVMonitoring(callback: ((HRVReading) -> Void)? = nil) async throws {
        let query = HKObserverQuery(sampleType: hrvType, predicate: nil) { [weak self] (query, completionHandler, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("HRV觀察者查詢錯誤: \(error.localizedDescription)")
                completionHandler()
                return
            }
            
            // 當有新數據時，獲取最新的HRV值
            Task { [weak self] in
                guard let self = self else { return }
                let hrv = await self.fetchLatestHRV()
                if hrv > 0, let callback = callback {
                    DispatchQueue.main.async {
                        callback(HRVReading(timestamp: Date(), value: hrv))
                    }
                }
            }
            
            // 不要忘記調用完成處理程序
            completionHandler()
        }
        
        healthStore.execute(query)
        
        // 啟用背景更新
        try await healthStore.enableBackgroundDelivery(for: hrvType, frequency: .immediate)
        print("HRV背景更新已啟用")
    }
    
    /// 停止HRV監測
    func stopHRVMonitoring() async throws {
        try await healthStore.disableBackgroundDelivery(for: hrvType)
        print("HRV背景更新已停用")
    }
    
    /// 取得最新的HRV值
    @discardableResult
    func fetchLatestHRV() async -> Double {
        let calendar = Calendar.current
        let now = Date()
        guard let startDate = calendar.date(byAdding: .minute, value: -10, to: now) else {
            return 0
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictEndDate)
        
        do {
            let results = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: results ?? [])
                    }
                }
                healthStore.execute(query)
            }
            
            if let sample = results.first as? HKQuantitySample {
                let value = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                DispatchQueue.main.async {
                    self.latestHRV = value
                }
                return value
            }
            return 0
        } catch {
            print("獲取最新HRV失敗: \(error.localizedDescription)")
            return 0
        }
    }
    
    /// 判斷當前HRV是否超過基準閾值 (基準值 × 1.15)
    func isHRVExceedingThreshold(currentHRV: Double? = nil, useBaselineHRV: Double? = nil) -> Bool {
        let hrvToCheck = currentHRV ?? self.latestHRV
        let baseline = useBaselineHRV ?? self.daytimeBaselineHRV
        
        // 如果沒有基準值或當前值，返回false
        guard baseline > 0, hrvToCheck > 0 else {
            return false
        }
        
        // 判斷是否超過閾值 (基準值 × 1.15)
        return hrvToCheck >= (baseline * hrvThresholdMultiplier)
    }
    
    /// 處理背景交付通知
    @objc private func handleBackgroundDelivery() {
        Task { [weak self] in
            guard let self = self else { return }
            let _ = await self.fetchLatestHRV()
        }
    }
    
    /// 初始化HRV監測系統
    func initializeHRVMonitoring() async -> Bool {
        // 請求授權
        let authorized = await requestAuthorization()
        if !authorized {
            return false
        }
        
        // 獲取基準數據
        let baselineHRV = await fetchBaselineHRV()
        let daytimeHRV = await fetchDaytimeBaselineHRV()
        
        // 如果無法獲取基準數據，設置默認值
        if baselineHRV <= 0 {
            DispatchQueue.main.async {
                self.baselineHRV = 50.0 // 設置為一個合理的默認值
            }
        }
        
        if daytimeHRV <= 0 {
            DispatchQueue.main.async {
                self.daytimeBaselineHRV = baselineHRV > 0 ? baselineHRV : 50.0
            }
        }
        
        return true
    }
} 