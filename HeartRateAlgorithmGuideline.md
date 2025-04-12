# 心率演算法指導文件 
> **注意**: 本文件為 ProjectGuideline.md 的補充文件，專注於心率監測演算法的詳細實現。主要架構及功能設計請參考 ProjectGuideline.md。

## 以「即時 HR 低於個人 RHR 的 X%」作為入睡判定起始門檻

| 年齡組 | 判定標準 | 參考來源 |
|--------|----------|----------|
| 10–17 歲 | 低於 85–90%，且維持 ≥ 2 分鐘 | |
| 18–59 歲 | 低於 90%（多數人約下降 5–10%）且維持 ≥ 3 分鐘 | Burgess 1999 成人實驗夜間及午睡資料 |
| ≥ 60 歲 | 低於 92–95%，需延長觀察窗至 ≥ 4 分鐘（自主神經反應變鈍） | |

## 風險評估與處理

### 高訓練運動員的特殊情況
- **問題**：高訓練運動員 RHR 極低（40 bpm 以下）容易錯過入睡（假陰性）
- **解決方案**：以 ΔHR（下降 ≥ 5 bpm 且 < 個人 RHR）為輔助判準
- **實施方式**：App無法判斷使用者是否是運動員，先以40bpm為篩選標準

## 時間窗迴圈設定

每 15 秒評估一次；若條件連續成立 12 次（約3分鐘），標記入睡並開始倒數。

## 備用邏輯：取得「睡眠心率」的建議做法

### 1. 讀取睡眠時段
```swift
let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
// 執行 HKSampleQuery 或 HKAnchoredObjectQuery 取得使用者的睡眠段落
```

### 2. 篩選該時段內的心率樣本
```swift
let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)!
// 以 predicate 限制時間區間在睡眠段落，執行 HKSampleQuery 取得心率樣本
```

### 3. 計算統計指標
例如取平均、最低、最高或其他您需要的統計量，作為「睡眠心率」。

## 備註

- 所有閾值均可根據實際測試結果進行調整
- 考慮添加動作感測器數據作為輔助判斷依據
- 建議在開發階段記錄詳細日誌以助於演算法優化

## 個人化心率模型實施方案

### 模型概述

該模型旨在通過分析用戶的歷史睡眠心率數據，逐步優化睡眠檢測閾值，提高檢測準確率。

### 數據存儲結構

```swift
struct UserSleepProfile {
    // 使用者基本信息
    let userId: String
    let ageGroup: AgeGroup  // 枚舉：Teen, Adult, Senior
    
    // 心率閾值設定
    var hrThresholdPercentage: Double  // 例如 0.9 表示 RHR 的 90%
    var minDurationSeconds: Int        // 維持低心率需要的時間（秒）
    
    // 模型狀態追蹤
    var firstUseDate: Date?            // 首次使用日期
    var lastModelUpdateDate: Date?     // 最後一次模型更新日期
    var sleepSessionsCount: Int        // 記錄的睡眠次數
    
    // 統計數據
    var averageSleepHR: Double?        // 平均睡眠心率
    var minSleepHR: Double?            // 最低睡眠心率
    var sleepHRVariance: Double?       // 睡眠心率變異
    var truePositiveRate: Double?      // 準確檢測率（如果有反饋）
}
```

### 模型更新邏輯

```swift
func updateUserSleepModel(for userId: String) {
    // 1. 檢查是否需要更新
    guard let profile = getUserProfile(userId) else {
        // 新用戶，創建配置文件並使用預設值
        createNewUserProfile(userId)
        return
    }
    
    // 2. 確定是否需要更新
    let now = Date()
    let needsUpdate: Bool
    
    if profile.firstUseDate == nil {
        // 首次運行，記錄日期並使用預設值
        updateProfile(userId, firstUseDate: now)
        needsUpdate = false
    } else if daysBetween(profile.firstUseDate!, now) < 7 {
        // 使用未滿7天，繼續使用預設值
        needsUpdate = false
    } else if profile.lastModelUpdateDate == nil || 
              daysBetween(profile.lastModelUpdateDate!, now) >= 14 {
        // 首次更新或距離上次更新已超過14天
        needsUpdate = true
    } else {
        // 不需要更新
        needsUpdate = false
    }
    
    if needsUpdate {
        // 3. 收集過去兩週的睡眠數據
        let sleepData = collectSleepData(userId, startDate: profile.lastModelUpdateDate ?? profile.firstUseDate!, endDate: now)
        
        // 4. 分析數據並優化模型
        if let optimizedModel = analyzeAndOptimize(profile, newSleepData: sleepData) {
            // 5. 更新用戶模型
            updateUserModel(userId, newModel: optimizedModel)
            updateProfile(userId, lastModelUpdateDate: now)
        }
    }
}
```

### 數據分析與閾值優化

```swift
func analyzeAndOptimize(_ profile: UserSleepProfile, newSleepData: [SleepSession]) -> OptimizedThresholds? {
    // 確保有足夠數據進行分析
    guard !newSleepData.isEmpty else { return nil }
    
    // 1. 計算睡眠心率統計數據
    let allHeartRates = newSleepData.flatMap { $0.heartRates }
    let avgHR = average(allHeartRates)
    let minHR = minimum(allHeartRates)
    let hrVariance = calculateVariance(allHeartRates)
    
    // 2. 計算與靜息心率的比例
    let restingHR = getLatestRestingHeartRate(profile.userId)
    let sleepToRestingRatio = avgHR / restingHR
    
    // 3. 根據實際數據優化閾值
    // 這裡的邏輯可以根據您的需求進一步複雜化
    var optimizedThresholds = OptimizedThresholds()
    
    // 心率閾值：根據年齡組和實際數據調整
    let baseThreshold: Double
    switch profile.ageGroup {
        case .Teen: baseThreshold = 0.875  // 87.5% (85-90%)
        case .Adult: baseThreshold = 0.9   // 90%
        case .Senior: baseThreshold = 0.935 // 93.5% (92-95%)
    }
    
    // 根據實際睡眠心率數據調整閾值
    // 如果實際比例低於基礎閾值，適當降低閾值
    if sleepToRestingRatio < baseThreshold {
        optimizedThresholds.hrThresholdPercentage = max(sleepToRestingRatio + 0.02, baseThreshold - 0.05)
    } else {
        // 否則使用略低於基礎閾值的值
        optimizedThresholds.hrThresholdPercentage = baseThreshold - 0.01
    }
    
    // 根據年齡組設定持續時間
    switch profile.ageGroup {
        case .Teen: optimizedThresholds.minDurationSeconds = 120  // 2分鐘
        case .Adult: optimizedThresholds.minDurationSeconds = 180 // 3分鐘
        case .Senior: optimizedThresholds.minDurationSeconds = 240 // 4分鐘
    }
    
    // 如果有反饋數據，可以根據準確率進一步調整
    if let accuracyRate = profile.truePositiveRate, accuracyRate < 0.8 {
        // 如果準確率低於80%，微調閾值
        optimizedThresholds.hrThresholdPercentage += 0.02
    }
    
    return optimizedThresholds
}
```

### 實際使用模型進行睡眠檢測

```swift
func detectSleep(currentHR: Double, userId: String) -> Bool {
    // 1. 獲取用戶模型
    guard let profile = getUserProfile(userId) else {
        // 沒有模型，使用預設值
        return useFallbackSleepDetection(currentHR)
    }
    
    // 2. 獲取當前靜息心率
    let restingHR = getLatestRestingHeartRate(userId)
    
    // 3. 計算閾值
    let hrThreshold = restingHR * profile.hrThresholdPercentage
    
    // 4. 檢查當前心率是否低於閾值
    if currentHR < hrThreshold {
        // 記錄此次低於閾值的時間點
        recordLowHRTimestamp()
        
        // 檢查是否已經維持足夠時間
        if getLowHRDuration() >= profile.minDurationSeconds {
            // 判定為睡眠狀態
            return true
        }
    } else {
        // 清除低心率計時
        resetLowHRTimestamps()
    }
    
    return false
}
```

### 實施建議

1. **數據存儲**：
   - 使用 UserDefaults 存儲簡單的用戶配置
   - 對於詳細的睡眠數據，考慮使用 CoreData 或 SQLite

2. **定期更新**：
   - 在應用啟動時檢查是否需要更新模型
   - 在每次睡眠會話結束後收集數據

3. **漸進式調整**：
   - 每次更新時只小幅調整閾值（例如 ±1-2%）
   - 保留歷史閾值，以便在效果不佳時可以回退

4. **反饋機制**：
   - 提供讓用戶確認睡眠檢測是否準確的方式
   - 利用這些反饋進一步優化模型

## 關鍵指標詳解與應用策略

在個人化心率模型中，我們利用三個核心指標來優化睡眠檢測閾值：平均睡眠心率、最低心率和心率變異性。以下詳細說明這些指標的概念及其應用方法。

### 平均睡眠心率

**概念**：
- 睡眠期間所有心率樣本的平均值
- 通常比靜息心率低10-20%
- 因人而異，受年齡、體能狀況和睡眠階段影響

**應用策略**：
- 根據用戶的實際平均睡眠心率/靜息心率比例調整閾值
- 如果用戶的平均睡眠心率為靜息心率的80%，可從預設值（如87.5%）逐步調整至接近80%
- 採用漸進式調整，避免因單次數據波動導致過度調整

```swift
// 漸進式調整閾值示例
let actualRatio = avgSleepHR / restingHR // 例如 80%
let targetThreshold = actualRatio + 0.02 // 添加2%安全邊際 = 82%
let currentThreshold = profile.hrThresholdPercentage // 當前閾值，例如 87.5%
let maxAdjustment = 0.025 // 每次最多調整2.5個百分點
let newThreshold = max(targetThreshold, currentThreshold - maxAdjustment)
```

### 最低心率

**概念**：
- 睡眠過程中觀察到的最低心率值
- 通常出現在深度睡眠階段
- 比平均睡眠心率低5-15%

**應用策略**：
- 作為閾值調整的下限保護，防止閾值設定過低
- 確保閾值始終高於最低心率比例加上安全邊際
- 特別適用於心率下降明顯的健康用戶

```swift
// 使用最低心率作為下限保護
let lowestRatio = minSleepHR / restingHR // 例如 75%
let minimumThreshold = lowestRatio + 0.05 // 設定安全邊際 = 80%
let safeThreshold = max(newThreshold, minimumThreshold)
```

### 心率變異性

**概念**：
- 心率在睡眠中的波動程度
- 高變異性表示心率波動大，可能處於淺睡或REM睡眠
- 低變異性通常表示穩定的深度睡眠

**應用策略**：
- 高變異性用戶需要較寬鬆的閾值：
  - 高變異性（>10 bpm）：增加閾值安全邊際
  - 低變異性（<5 bpm）：可使用更精確的閾值
- 也可用於評估睡眠質量和改進檢測算法

```swift
// 根據心率變異性微調閾值
let varianceAdjustment: Double
if hrVariance > 10 {
    varianceAdjustment = 0.03 // 高變異性，增加3%
} else if hrVariance < 5 {
    varianceAdjustment = -0.01 // 低變異性，可減少1%
} else {
    varianceAdjustment = 0.01 // 中等變異性，增加1%
}
let finalThreshold = safeThreshold + varianceAdjustment
```

### 綜合應用模型

最佳實踐是將三個指標綜合應用，形成完整的個人化調整流程：

1. **初始閾值**：基於年齡組設定基礎閾值
2. **主要調整**：根據平均睡眠心率逐步調整閾值（漸進式）
3. **安全限制**：使用最低心率設定閾值下限
4. **精細調整**：根據心率變異性微調最終閾值

綜合演算法流程：

```swift
func calculateOptimizedThreshold(profile: UserSleepProfile, sleepData: [SleepSession]) -> Double {
    // 1. 獲取基於年齡的基礎閾值
    let baseThreshold = getBaseThresholdForAgeGroup(profile.ageGroup)
    
    // 2. 計算平均睡眠心率與靜息心率的比例
    let avgSleepHR = calculateAverageSleepHR(sleepData)
    let restingHR = getLatestRestingHeartRate(profile.userId)
    let avgRatio = avgSleepHR / restingHR
    
    // 3. 設定目標閾值（略高於實際比例）
    let targetThreshold = avgRatio + 0.02
    
    // 4. 漸進式調整（每次最多調整2.5%）
    let currentThreshold = profile.hrThresholdPercentage
    let maxAdjustment = 0.025
    let adjustedThreshold = max(targetThreshold, currentThreshold - maxAdjustment)
    
    // 5. 使用最低心率作為安全限制
    let minSleepHR = calculateMinimumSleepHR(sleepData)
    let minRatio = minSleepHR / restingHR
    let safeThreshold = max(adjustedThreshold, minRatio + 0.05)
    
    // 6. 根據心率變異性進行精細調整
    let hrVariance = calculateHRVariance(sleepData)
    let finalThreshold = adjustBasedOnVariance(safeThreshold, variance: hrVariance)
    
    // 7. 確保閾值不超出合理範圍
    return clamp(finalThreshold, min: 0.75, max: 0.95)
}
```

### 實施注意事項

1. **數據收集期**：
   - 建議收集至少3-5次睡眠數據後再首次調整閾值
   - 每次調整前確保有足夠的新數據（至少2-3次睡眠記錄）

2. **異常處理**：
   - 識別並排除異常心率數據（例如運動後或壓力下的記錄）
   - 考慮添加置信度評分，低置信度的調整幅度更小

3. **用戶反饋整合**：
   - 如果提供用戶反饋機制，可根據用戶確認的睡眠檢測準確性進一步調整模型
   - 對於反饋「誤檢測」的情況，適當提高閾值
   - 對於反饋「未檢測到」的情況，適當降低閾值