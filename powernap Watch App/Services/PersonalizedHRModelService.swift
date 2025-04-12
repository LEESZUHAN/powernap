import Foundation
import HealthKit
import SwiftUI
import Combine

/// 年齡組枚舉，用於根據年齡調整睡眠檢測參數
enum AgeGroup: String, CaseIterable, Codable, Identifiable {
    /// 青少年組 (10-17歲)
    case teen = "青少年 (10-17歲)"
    
    /// 成人組 (18-59歲)
    case adult = "成人 (18-59歲)"
    
    /// 銀髮族 (60歲以上)
    case senior = "銀髮族 (60歲以上)"
    
    /// 用於列表識別的ID
    var id: String { self.rawValue }
    
    /// 心率閾值百分比 - 低於靜息心率多少比例視為可能入睡
    var hrThresholdPercentage: Double {
        switch self {
        case .teen:   return 0.875  // 87.5% (低於靜息心率的85-90%)
        case .adult:  return 0.9    // 90% (低於靜息心率的10%)
        case .senior: return 0.935  // 93.5% (低於靜息心率的6.5%)
        }
    }
    
    /// 持續時間要求 - 需要維持多少秒的低心率才判定為入睡
    var minDurationSeconds: Int {
        switch self {
        case .teen:   return 120  // 2分鐘
        case .adult:  return 180  // 3分鐘
        case .senior: return 240  // 4分鐘
        }
    }
    
    /// 根據實際年齡獲取對應年齡組
    static func from(age: Int) -> AgeGroup {
        switch age {
        case 0..<18:  return .teen
        case 18..<60: return .adult
        default:      return .senior
        }
    }
}

/// 睡眠數據收集會話
struct SleepSession: Codable {
    /// 會話日期
    let date: Date
    /// 心率樣本
    let heartRates: [Double]
    /// 靜息心率值
    let restingHeartRate: Double
    /// 是否為夜間睡眠
    let isNightSleep: Bool
    /// 睡眠心率平均值
    var averageHeartRate: Double {
        heartRates.isEmpty ? 0 : heartRates.reduce(0, +) / Double(heartRates.count)
    }
    /// 睡眠心率最低值
    var minimumHeartRate: Double {
        heartRates.isEmpty ? 0 : heartRates.min() ?? 0
    }
    /// 心率變異性（標準差）
    var heartRateVariance: Double {
        guard heartRates.count > 1 else { return 0 }
        let mean = averageHeartRate
        let sumOfSquaredDifferences = heartRates.reduce(0) { $0 + pow($1 - mean, 2) }
        return sqrt(sumOfSquaredDifferences / Double(heartRates.count))
    }
}

/// 個人化心率模型服務 - 根據用戶的睡眠數據自動優化心率閾值
class PersonalizedHRModelService: ObservableObject {
    /// 當前心率閾值百分比（預設值由年齡組決定）
    @Published var optimizedThresholdPercentage: Double
    
    /// 用戶年齡組
    private let ageGroup: AgeGroup
    
    /// 最近收集的睡眠會話
    private var sleepSessions: [SleepSession] = []
    
    /// 用於儲存閾值和會話的鍵值
    private let thresholdKey = "optimizedHRThreshold"
    private let sessionsKey = "sleepSessions"
    private let lastUpdateKey = "lastModelUpdateDate"
    
    /// 白天與夜間睡眠的不同閾值
    private let daytimeThresholdKey = "daytimeHRThreshold"
    private let nighttimeThresholdKey = "nighttimeHRThreshold"
    
    /// 版本控制 - 用於數據遷移
    private let dataVersionKey = "hrModelDataVersion"
    private let currentDataVersion = 2 // 當前數據版本，如有重大更改則遞增
    
    /// 最後一次模型更新日期
    private var lastUpdateDate: Date? {
        get {
            UserDefaults.standard.object(forKey: lastUpdateKey) as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: lastUpdateKey)
        }
    }
    
    /// 首次使用日期
    private var firstUseDate: Date? {
        get {
            UserDefaults.standard.object(forKey: "firstUseDate") as? Date
        }
        set {
            if firstUseDate == nil {
                UserDefaults.standard.set(newValue, forKey: "firstUseDate")
            }
        }
    }
    
    /// 模型更新間隔（天）
    private let updateInterval: Int = 7 // 默認7天
    
    /// 安全邊際設定
    private let minThreshold: Double = 0.75 // 最低允許閾值（靜息心率的75%）
    private let maxThreshold: Double = 0.95 // 最高允許閾值（靜息心率的95%）
    private let maxAdjustment: Double = 0.025 // 每次最大調整幅度（2.5%）
    
    /// 每日校準參數
    private let dailyCalibrationEnabled = true // 是否啟用每日校準
    private let activeLevelAdjustment: Double = 0.02 // 激烈活動後的閾值調整（+2%）
    
    /// 大幅波動偵測閾值
    private let suddenChangeThreshold: Double = 0.15 // 心率突然變化超過15%視為異常
    
    /// 學習率相關參數
    private let defaultLearningRate: Double = 0.3 // 默認學習率
    
    /// 心率閾值相關屬性
    private var heartRateThreshold: Int = 0
    private var baselineHeartRate: Double = 0
    private var minimumHeartRate: Double = 0
    
    /// 初始化
    init(ageGroup: AgeGroup) {
        self.ageGroup = ageGroup
        
        // 檢查數據版本，執行必要的遷移
        checkAndMigrateDataIfNeeded()
        
        // 嘗試從存儲中加載優化閾值
        if let savedThreshold = UserDefaults.standard.object(forKey: thresholdKey) as? Double {
            self.optimizedThresholdPercentage = savedThreshold
        } else {
            // 首次使用，使用年齡組預設值
            self.optimizedThresholdPercentage = ageGroup.hrThresholdPercentage
        }
        
        // 記錄首次使用日期
        if firstUseDate == nil {
            firstUseDate = Date()
        }
        
        // 載入已保存的睡眠會話
        loadSleepSessions()
    }
    
    /// 檢查並遷移數據
    private func checkAndMigrateDataIfNeeded() {
        let defaults = UserDefaults.standard
        let savedVersion = defaults.integer(forKey: dataVersionKey)
        
        if savedVersion < currentDataVersion {
            print("檢測到心率模型數據需要遷移：版本 \(savedVersion) -> \(currentDataVersion)")
            
            // 從版本1遷移到版本2
            if savedVersion < 2 {
                migrateDataToVersion2()
            }
            
            // 更新數據版本
            defaults.set(currentDataVersion, forKey: dataVersionKey)
            print("心率模型數據遷移完成，當前版本：\(currentDataVersion)")
        }
    }
    
    /// 將數據遷移到版本2
    private func migrateDataToVersion2() {
        // 這是一個數據結構變更時的遷移範例
        let defaults = UserDefaults.standard
        
        // 例如：遷移舊格式的睡眠會話數據
        if let oldData = defaults.data(forKey: sessionsKey) {
            do {
                // 嘗試將舊格式數據轉換為新格式
                // 注意：實際遷移代碼將取決於具體的數據結構變化
                print("遷移睡眠會話數據到新格式...")
                
                // 在此示例中，我們假設數據格式沒有變更，但在實際場景中需要適當轉換
                // 例如：可能需要添加新字段或改變數據格式
                
                // 將更新後的數據保存回去
                defaults.set(oldData, forKey: sessionsKey)
                print("睡眠會話數據遷移完成")
            } catch {
                print("睡眠會話數據遷移失敗：\(error.localizedDescription)")
            }
        }
        
        // 其他版本2特定的遷移操作...
    }
    
    /// 改進的異常值過濾，結合IQR方法、突變檢測和時間窗口分析
    private func filterOutliers(from heartRates: [Double]) -> [Double] {
        guard heartRates.count > 4 else { return heartRates }
        
        // 第一步：使用四分位距法（IQR）過濾極端值
        let sortedRates = heartRates.sorted()
        let count = sortedRates.count
        
        // 計算第一和第三四分位數
        let q1Index = count / 4
        let q3Index = (count * 3) / 4
        
        let q1 = sortedRates[q1Index]
        let q3 = sortedRates[q3Index]
        
        // 計算四分位距
        let iqr = q3 - q1
        
        // 設定上下限閾值（使用1.8倍IQR以優化對睡眠心率的保留）
        let lowerBound = q1 - (1.8 * iqr)
        let upperBound = q3 + (1.8 * iqr)
        
        // 初步過濾極端值
        var filteredRates = heartRates.filter { $0 >= lowerBound && $0 <= upperBound }
        
        // 若過濾後數據過少，使用較寬鬆的標準重新過濾
        if filteredRates.count < heartRates.count * 0.7 {
            let relaxedLowerBound = q1 - (2.5 * iqr)
            let relaxedUpperBound = q3 + (2.5 * iqr)
            filteredRates = heartRates.filter { $0 >= relaxedLowerBound && $0 <= relaxedUpperBound }
            
            // 如果仍然過濾太多，使用原始數據
            if filteredRates.count < heartRates.count * 0.5 {
                print("使用原始心率數據 - 過濾太嚴格")
                filteredRates = heartRates
            }
        }
        
        // 第二步：檢測突變（短時間內大幅波動）
        if filteredRates.count > 10 {
            var stableRates: [Double] = []
            var previousRate: Double? = nil
            var outlierCount = 0
            
            for rate in filteredRates {
                if let prev = previousRate {
                    // 計算變化百分比
                    let changePercent = abs(rate - prev) / prev
                    
                    // 如果變化不超過設定的突變閾值，則保留
                    if changePercent <= suddenChangeThreshold {
                        stableRates.append(rate)
                    } else {
                        outlierCount += 1
                        print("檢測到心率突變: \(Int(prev)) -> \(Int(rate)), 變化: \(Int(changePercent * 100))%")
                    }
                } else {
                    // 第一個值總是保留
                    stableRates.append(rate)
                }
                
                previousRate = rate
            }
            
            // 輸出過濾統計
            if outlierCount > 0 {
                print("心率過濾統計: 過濾前 \(Int(filteredRates.count)) 個樣本, 過濾後 \(Int(stableRates.count)) 個樣本, 移除 \(outlierCount) 個異常值")
            }
            
            // 確保過濾後還有足夠數據
            if stableRates.count >= filteredRates.count * 0.8 {
                return stableRates
            }
        }
        
        // 第三步：時間窗口分析（假設心率數據包含時間戳）
        // 注意：此功能需要心率數據同時包含時間戳才能實現
        // 此版本暫未實現此功能
        
        return filteredRates
    }
    
    /// 檢測是否為夜間睡眠
    private func isNightSleep() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        // 通常晚上10點到早上6點視為夜間
        return hour >= 22 || hour < 6
    }
    
    /// 添加新的睡眠心率數據
    func addSleepHeartRateData(heartRates: [Double], restingHeartRate: Double) {
        guard !heartRates.isEmpty && restingHeartRate > 0 else { return }
        
        // 過濾異常值
        let filteredHeartRates = filterOutliers(from: heartRates)
        
        // 檢測是否為夜間睡眠
        let nightSleep = isNightSleep()
        
        // 創建新的睡眠會話
        let newSession = SleepSession(
            date: Date(),
            heartRates: filteredHeartRates,
            restingHeartRate: restingHeartRate,
            isNightSleep: nightSleep
        )
        
        // 添加到會話列表
        sleepSessions.append(newSession)
        
        // 保存會話數據
        saveSleepSessions()
        
        // 檢查是否需要更新模型
        checkAndUpdateModel()
    }
    
    /// 檢查當天活動水平並調整閾值（用於處理運動後的情況）
    func adjustForDailyActivity(activityLevel: Double, restingHeartRate: Double) {
        guard dailyCalibrationEnabled else { return }
        
        // 如果活動水平高於閾值，暫時提高心率閾值
        if activityLevel > 2.0 { // 假設2.0是激烈活動的閾值
            // 臨時提高閾值，但不永久保存
            let tempAdjustedThreshold = min(optimizedThresholdPercentage + activeLevelAdjustment, maxThreshold)
            
            print("檢測到高強度活動，臨時調整閾值：\(optimizedThresholdPercentage) -> \(tempAdjustedThreshold)")
            
            // 這裡只是臨時調整，不保存到UserDefaults
            // 這確保只有當天的檢測受影響，而不會影響長期模型
            optimizedThresholdPercentage = tempAdjustedThreshold
        }
    }
    
    /// 根據當前心率和靜息心率計算實際閾值
    func calculateThreshold(for restingHeartRate: Double) -> Double {
        // 檢查是白天還是夜間，使用相應的閾值
        let thresholdPercentage: Double
        
        if isNightSleep() {
            // 夜間使用較低閾值
            if let nightThreshold = UserDefaults.standard.object(forKey: nighttimeThresholdKey) as? Double {
                thresholdPercentage = nightThreshold
            } else {
                // 夜間默認閾值略低於白天
                thresholdPercentage = optimizedThresholdPercentage - 0.02
            }
        } else {
            // 白天使用正常閾值
            if let dayThreshold = UserDefaults.standard.object(forKey: daytimeThresholdKey) as? Double {
                thresholdPercentage = dayThreshold
            } else {
                thresholdPercentage = optimizedThresholdPercentage
            }
        }
        
        return restingHeartRate * thresholdPercentage
    }
    
    /// 檢查並更新心率模型
    private func checkAndUpdateModel() {
        let now = Date()
        
        // 確定是否需要更新
        let needsUpdate: Bool
        
        if lastUpdateDate == nil {
            // 如果首次運行不到7天，不更新
            guard let firstUse = firstUseDate,
                  daysBetween(firstUse, now) >= updateInterval else {
                print("模型使用未滿\(updateInterval)天，繼續使用初始值")
                return
            }
            needsUpdate = true
        } else if let lastUpdate = lastUpdateDate,
                  daysBetween(lastUpdate, now) >= updateInterval {
            // 上次更新已超過間隔天數
            needsUpdate = true
        } else {
            // 不需要更新
            needsUpdate = false
        }
        
        if needsUpdate {
            // 確保有足夠的數據進行分析（至少3次睡眠記錄）
            guard sleepSessions.count >= 3 else {
                print("睡眠記錄不足，無法更新模型（當前：\(sleepSessions.count)次）")
                return
            }
            
            // 執行模型更新
            updateModel()
            
            // 更新最後更新日期
            lastUpdateDate = now
        }
    }
    
    /// 更新心率模型
    private func updateModel() {
        print("開始更新個人化心率模型...")
        
        // 將會話分為白天和夜間
        let daytimeSessions = sleepSessions.filter { !$0.isNightSleep }
        let nighttimeSessions = sleepSessions.filter { $0.isNightSleep }
        
        // 更新白天模型
        updateSpecificModel(
            for: daytimeSessions,
            threshold: &optimizedThresholdPercentage,
            thresholdKey: daytimeThresholdKey,
            label: "白天"
        )
        
        // 如果有夜間數據，更新夜間模型
        if !nighttimeSessions.isEmpty {
            var nighttimeThreshold: Double
            
            if let saved = UserDefaults.standard.object(forKey: nighttimeThresholdKey) as? Double {
                nighttimeThreshold = saved
            } else {
                nighttimeThreshold = optimizedThresholdPercentage - 0.02
            }
            
            updateSpecificModel(
                for: nighttimeSessions,
                threshold: &nighttimeThreshold,
                thresholdKey: nighttimeThresholdKey,
                label: "夜間"
            )
        }
        
        // 清理舊數據（保留最近20條記錄）
        if sleepSessions.count > 20 {
            sleepSessions = Array(sleepSessions.sorted(by: { $0.date > $1.date }).prefix(20))
            saveSleepSessions()
        }
    }
    
    /// 更新特定時段的模型（白天或夜間）
    private func updateSpecificModel(for sessions: [SleepSession], threshold: inout Double, thresholdKey: String, label: String) {
        guard !sessions.isEmpty else {
            print("沒有\(label)睡眠數據，跳過更新")
            return
        }
        
        print("開始更新\(label)心率模型...")
        
        // 計算平均睡眠心率與靜息心率比例
        var sleepToRestingRatios: [Double] = []
        
        for session in sessions {
            let avgHR = session.averageHeartRate
            let rhr = session.restingHeartRate
            
            if avgHR > 0 && rhr > 0 {
                let ratio = avgHR / rhr
                sleepToRestingRatios.append(ratio)
            }
        }
        
        // 確保有足夠比例數據
        guard !sleepToRestingRatios.isEmpty else {
            print("無有效心率比例數據，無法更新\(label)模型")
            return
        }
        
        // 計算平均比例
        let avgRatio = sleepToRestingRatios.reduce(0, +) / Double(sleepToRestingRatios.count)
        print("\(label)平均睡眠心率/靜息心率比例: \(String(format: "%.3f", avgRatio))")
        
        // 目標閾值（略高於實際比例）
        let targetThreshold = avgRatio + 0.02 // 添加2%安全邊際
        
        // 獲取當前閾值
        let currentThreshold = threshold
        
        // 漸進式調整（每次最多調整maxAdjustment）
        var newThreshold: Double
        
        if targetThreshold < currentThreshold {
            // 目標比當前低，逐步降低
            newThreshold = max(targetThreshold, currentThreshold - maxAdjustment)
        } else {
            // 目標比當前高，逐步提高
            newThreshold = min(targetThreshold, currentThreshold + maxAdjustment)
        }
        
        // 計算最低睡眠心率安全限制
        let minHeartRates = sessions.map { $0.minimumHeartRate }
        let minHRToRestingRatios = zip(minHeartRates, sessions.map { $0.restingHeartRate }).compactMap { minHR, rhr -> Double? in
            guard minHR > 0 && rhr > 0 else { return nil }
            return minHR / rhr
        }
        
        if let lowestRatio = minHRToRestingRatios.min() {
            // 設定安全下限（最低心率比例 + 5%）
            let safeMinThreshold = lowestRatio + 0.05
            
            // 確保新閾值不低於安全下限
            newThreshold = max(newThreshold, safeMinThreshold)
            print("\(label)安全下限閾值: \(String(format: "%.3f", safeMinThreshold))")
        }
        
        // 根據心率變異性微調閾值
        let allVariances = sessions.map { $0.heartRateVariance }
        if let avgVariance = allVariances.isEmpty ? nil : allVariances.reduce(0, +) / Double(allVariances.count) {
            let varianceAdjustment: Double
            
            if avgVariance > 10 {
                varianceAdjustment = 0.03 // 高變異性，增加3%
                print("檢測到\(label)高心率變異性 (\(String(format: "%.1f", avgVariance))), 增加3%安全邊際")
            } else if avgVariance < 5 {
                varianceAdjustment = -0.01 // 低變異性，可減少1%
                print("檢測到\(label)低心率變異性 (\(String(format: "%.1f", avgVariance))), 減少1%安全邊際")
            } else {
                varianceAdjustment = 0.01 // 中等變異性，增加1%
                print("檢測到\(label)中等心率變異性 (\(String(format: "%.1f", avgVariance))), 增加1%安全邊際")
            }
            
            newThreshold += varianceAdjustment
        }
        
        // 確保閾值在合理範圍內
        newThreshold = min(max(newThreshold, minThreshold), maxThreshold)
        
        // 更新閾值
        threshold = newThreshold
        
        // 保存到UserDefaults
        UserDefaults.standard.set(newThreshold, forKey: thresholdKey)
        
        print("\(label)模型更新完成! 舊閾值: \(String(format: "%.3f", currentThreshold)) -> 新閾值: \(String(format: "%.3f", newThreshold))")
        
        // 針對白天閾值，同時更新主閾值
        if thresholdKey == daytimeThresholdKey {
            optimizedThresholdPercentage = newThreshold
            UserDefaults.standard.set(newThreshold, forKey: self.thresholdKey)
        }
    }
    
    /// 加載已保存的睡眠會話
    private func loadSleepSessions() {
        if let data = UserDefaults.standard.data(forKey: sessionsKey) {
            do {
                // 嘗試解碼新格式（包含isNightSleep字段）
                let decoded = try JSONDecoder().decode([SleepSession].self, from: data)
                sleepSessions = decoded
                print("成功加載\(sleepSessions.count)條睡眠記錄")
            } catch {
                print("無法載入睡眠會話數據: \(error.localizedDescription)")
                
                // 嘗試數據修復和遷移
                attemptDataRecovery()
            }
        }
    }
    
    /// 嘗試修復損壞的數據
    private func attemptDataRecovery() {
        print("正在嘗試修復損壞的數據...")
        
        // 嘗試從備份恢復，如果有備份機制的話
        let backupKey = "\(sessionsKey)_backup"
        if let backupData = UserDefaults.standard.data(forKey: backupKey) {
            do {
                let decoded = try JSONDecoder().decode([SleepSession].self, from: backupData)
                sleepSessions = decoded
                print("已從備份恢復\(sleepSessions.count)條睡眠記錄")
                
                // 恢復成功後保存
                saveSleepSessions()
                return
            } catch {
                print("備份數據也已損壞，無法恢復")
            }
        }
        
        // 如果無法從備份恢復，則重置數據
        sleepSessions = []
        print("無法修復數據，已重置睡眠記錄")
    }
    
    /// 保存睡眠會話
    private func saveSleepSessions() {
        if let encoded = try? JSONEncoder().encode(sleepSessions) {
            UserDefaults.standard.set(encoded, forKey: sessionsKey)
            
            // 同時保存一份備份
            UserDefaults.standard.set(encoded, forKey: "\(sessionsKey)_backup")
            
            // 保存學習狀態
            let learningRateInt = Int(round(defaultLearningRate * 100))
            UserDefaults.standard.set(learningRateInt, forKey: "learningRatePercentage")
        }
    }
    
    /// 計算兩個日期之間的天數
    private func daysBetween(_ date1: Date, _ date2: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: date1, to: date2)
        return abs(components.day ?? 0)
    }
    
    /// 重置模型（用於測試）
    func resetModel() {
        sleepSessions = []
        optimizedThresholdPercentage = ageGroup.hrThresholdPercentage
        lastUpdateDate = nil
        firstUseDate = nil
        
        UserDefaults.standard.removeObject(forKey: thresholdKey)
        UserDefaults.standard.removeObject(forKey: daytimeThresholdKey)
        UserDefaults.standard.removeObject(forKey: nighttimeThresholdKey)
        UserDefaults.standard.removeObject(forKey: sessionsKey)
        UserDefaults.standard.removeObject(forKey: lastUpdateKey)
        UserDefaults.standard.removeObject(forKey: "firstUseDate")
        
        print("個人化心率模型已重置")
    }
    
    /// 根據用戶數據優化心率閾值
    private func optimizeHeartRateThreshold() {
        guard !sleepSessions.isEmpty else { return }
        
        // 使用預設學習率
        let learningRate = defaultLearningRate
        
        // 當前閾值和理想閾值（這些應該在實際方法中計算得出）
        let currentThreshold = Double(heartRateThreshold)
        let idealThreshold = optimizedThresholdPercentage * baselineHeartRate
        
        // 計算加權閾值（將當前閾值與理想閾值進行加權平均）
        let weightedThreshold = (currentThreshold * (1.0 - learningRate)) + (idealThreshold * learningRate)
        
        // 更新心率閾值，確保轉換為整數
        heartRateThreshold = Int(round(weightedThreshold))
        print("優化後的心率閾值: \(heartRateThreshold)")
    }
    
    /// 更新基線心率數據
    func updateBaselineHeartRate(ageGroup: AgeGroup, restingHeartRate: Double) {
        // 更新基線心率
        baselineHeartRate = restingHeartRate
        
        // 更新最小心率（假設為基線心率的某個百分比）
        minimumHeartRate = restingHeartRate * ageGroup.hrThresholdPercentage
        
        // 保存到 UserDefaults
        UserDefaults.standard.set(baselineHeartRate, forKey: "baselineHeartRate")
        UserDefaults.standard.set(minimumHeartRate, forKey: "minimumHeartRate")
    }
} 