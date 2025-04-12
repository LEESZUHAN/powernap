# [已棄用] 心率監測優化方案：日間與夜間睡眠檢測差異化

> **注意**：本文檔描述的日間午休與夜間睡眠差異化設計方案已不再採用。
> 當前版本 PowerNap 專注於白天短暫休息場景，不處理夜間睡眠數據。
> 本文檔保留作為將來可能開發全日版時的參考。

## 問題背景

當前PowerNap應用使用統一的心率閾值判斷用戶是否進入睡眠狀態。然而，根據生理學研究，日間午休的心率特徵與夜間睡眠存在明顯差異：

- 日間午休時，由於交感神經活性較高，心率通常比夜間睡眠高約10%
- 晝夜節律會影響基礎代謝率和心率
- 環境因素（光線、噪音）對日間休息的影響更大
- 午餐後消化活動可能使午休時期的心率維持在較高水平

當系統混合處理這兩種不同情境的數據時，會導致以下問題：

1. 如果主要學習自夜間睡眠的閾值（例如靜息心率的80%）應用在午休檢測上，可能過於寬鬆
2. 反之，如果閾值設置過高，又可能無法正確檢測夜間睡眠
3. 長期適應模型中混合兩種數據，閾值會持續波動，無法達到最佳精度

## 系統現狀分析

目前的`PersonalizedHRModelService`實現中，存在以下局限：

```swift
// 數據結構中沒有時段區分
struct SleepSession: Codable {
    let date: Date
    let heartRates: [Double]
    let restingHeartRate: Double
    // 缺乏時段標記
}

// 添加心率數據時沒有區分時段
func addSleepHeartRateData(heartRates: [Double], restingHeartRate: Double) {
    // 創建新的睡眠會話，無時段信息
    let newSession = SleepSession(
        date: Date(),
        heartRates: heartRates,
        restingHeartRate: restingHeartRate
    )
    
    sleepSessions.append(newSession)
}

// 更新模型時混合所有數據
private func updateModel() {
    // 計算平均比例
    let avgRatio = sleepToRestingRatios.reduce(0, +) / Double(sleepToRestingRatios.count)
    
    // 目標閾值（略高於實際比例）
    let targetThreshold = avgRatio + 0.02 // 無時段區分
}
```

## 技術改進方案

### 1. 數據結構優化

向`SleepSession`添加時段類型標記：

```swift
// 添加時段類型枚舉
enum SleepSessionType: String, Codable {
    case daytimeNap = "日間午休"
    case nightSleep = "夜間睡眠"
}

// 優化後的睡眠會話結構
struct SleepSession: Codable {
    /// 會話日期
    let date: Date
    /// 心率樣本
    let heartRates: [Double]
    /// 靜息心率值
    let restingHeartRate: Double
    /// 會話類型(新增)
    let sessionType: SleepSessionType 
    
    // 其他計算屬性保持不變...
}
```

### 2. 數據收集優化

在添加心率數據時根據時間自動分類：

```swift
// 優化後的數據添加方法
func addSleepHeartRateData(heartRates: [Double], restingHeartRate: Double) {
    guard !heartRates.isEmpty && restingHeartRate > 0 else { return }
    
    // 根據當前時間判斷會話類型
    let sessionType = determineSessionType(for: Date())
    
    // 創建新的睡眠會話
    let newSession = SleepSession(
        date: Date(),
        heartRates: heartRates,
        restingHeartRate: restingHeartRate,
        sessionType: sessionType
    )
    
    // 添加到會話列表
    sleepSessions.append(newSession)
    
    // 其餘保存數據和更新模型的邏輯不變...
}

// 新增：根據時間確定會話類型的方法
private func determineSessionType(for date: Date) -> SleepSessionType {
    let calendar = Calendar.current
    let hour = calendar.component(.hour, from: date)
    
    // 簡單劃分：6-21點為日間，其餘為夜間
    // 可根據實際需求調整時間範圍
    if hour >= 6 && hour < 21 {
        return .daytimeNap
    } else {
        return .nightSleep
    }
}
```

### 3. 模型處理優化

分別維護和計算日間午休和夜間睡眠的閾值：

```swift
// 增加類屬性存儲不同時段的閾值
@Published var napThresholdPercentage: Double = 0.0
@Published var nightThresholdPercentage: Double = 0.0

// 優化後的模型更新方法
private func updateModel() {
    print("開始更新個人化心率模型...")
    
    // 區分不同類型的睡眠會話
    let napSessions = sleepSessions.filter { $0.sessionType == .daytimeNap }
    let nightSessions = sleepSessions.filter { $0.sessionType == .nightSleep }
    
    // 分別更新不同類型的閾值
    updateThresholdFor(sessions: napSessions, thresholdKey: "napHRThreshold", isNapMode: true)
    updateThresholdFor(sessions: nightSessions, thresholdKey: "nightHRThreshold", isNapMode: false)
    
    // 根據當前時間決定使用哪個閾值作為當前活躍閾值
    let currentIsNapTime = determineSessionType(for: Date()) == .daytimeNap
    optimizedThresholdPercentage = currentIsNapTime ? napThresholdPercentage : nightThresholdPercentage
}

// 新增：更新指定類型會話的閾值
private func updateThresholdFor(sessions: [SleepSession], thresholdKey: String, isNapMode: Bool) {
    // 確保有足夠數據
    guard sessions.count >= 2 else {
        print("\(isNapMode ? "午休" : "夜間")數據不足，保持默認設置")
        return
    }
    
    // 計算該類型的心率比例
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
    guard !sleepToRestingRatios.isEmpty else { return }
    
    // 計算平均比例
    let avgRatio = sleepToRestingRatios.reduce(0, +) / Double(sleepToRestingRatios.count)
    print("\(isNapMode ? "午休" : "夜間")平均心率/靜息心率比例: \(String(format: "%.3f", avgRatio))")
    
    // 目標閾值（略高於實際比例）
    // 午休時增加更多的安全邊際
    let safetyMargin = isNapMode ? 0.03 : 0.02
    let targetThreshold = avgRatio + safetyMargin
    
    // 獲取當前閾值
    let currentThreshold = isNapMode ? napThresholdPercentage : nightThresholdPercentage
    let initialThreshold = isNapMode ? 
                          ageGroup.hrThresholdPercentage + 0.05 : // 午休模式初始值稍高
                          ageGroup.hrThresholdPercentage
    
    // 如果是首次設置，使用初始值
    let actualCurrentThreshold = (currentThreshold <= 0.01) ? initialThreshold : currentThreshold
    
    // 漸進式調整（每次最多調整maxAdjustment）
    var newThreshold: Double
    
    if targetThreshold < actualCurrentThreshold {
        // 目標比當前低，逐步降低
        newThreshold = max(targetThreshold, actualCurrentThreshold - maxAdjustment)
    } else {
        // 目標比當前高，逐步提高
        newThreshold = min(targetThreshold, actualCurrentThreshold + maxAdjustment)
    }
    
    // 應用其他安全限制（最低/最高心率等）...
    // 保持與原算法相同的安全檢查邏輯
    
    // 保存到模型及UserDefaults
    if isNapMode {
        napThresholdPercentage = newThreshold
    } else {
        nightThresholdPercentage = newThreshold
    }
    
    UserDefaults.standard.set(newThreshold, forKey: thresholdKey)
    
    print("\(isNapMode ? "午休" : "夜間")模型更新：\(String(format: "%.3f", actualCurrentThreshold)) -> \(String(format: "%.3f", newThreshold))")
}
```

### 4. 閾值應用優化

根據當前時間自動選擇適當的閾值：

```swift
// 優化閾值計算方法
func calculateThreshold(for restingHeartRate: Double) -> Double {
    // 根據當前時間確定使用哪個閾值
    let sessionType = determineSessionType(for: Date())
    let thresholdToUse = (sessionType == .daytimeNap) ? napThresholdPercentage : nightThresholdPercentage
    
    // 如果該模式的閾值尚未初始化，則使用預設值
    let threshold = (thresholdToUse > 0.01) ? thresholdToUse : 
                   (sessionType == .daytimeNap ? ageGroup.hrThresholdPercentage + 0.05 : ageGroup.hrThresholdPercentage)
    
    return restingHeartRate * threshold
}
```

### 5. 用戶界面優化

添加設置項，允許用戶查看和微調不同時段的閾值：

```swift
// 在HealthStatsSettingsView中新增顯示
Section(header: Text("時段優化設置")) {
    VStack(alignment: .leading) {
        Text("日間午休閾值：\(String(format: "%.1f", viewModel.napThresholdPercentage * 100))%")
        Text("夜間睡眠閾值：\(String(format: "%.1f", viewModel.nightThresholdPercentage * 100))%")
    }
    .font(.footnote)
    
    Toggle("啟用時段智能優化", isOn: $viewModel.enableTimeBasedOptimization)
        .onChange(of: viewModel.enableTimeBasedOptimization) { newValue in
            UserDefaults.standard.set(newValue, forKey: "enableTimeBasedOptimization")
        }
}
```

## 實施計劃

### 第一階段：數據結構更新
1. 更新`SleepSession`結構，添加時段類型字段
2. 修改數據保存和加載方法，確保向後兼容
3. 在`addSleepHeartRateData`中實現時段自動分類

### 第二階段：模型優化
1. 添加針對不同時段的閾值存儲和計算
2. 實現分類處理不同時段數據的邏輯
3. 優化閾值計算方法，根據時間自動選擇

### 第三階段：界面和控制
1. 在設置界面添加時段優化開關和信息顯示
2. 添加測試和診斷功能，驗證兩種模式的閾值差異
3. 記錄午休和夜間模式的檢測準確率，用於後續優化

## 預期效果

1. **提高檢測準確性**：針對不同時間段的睡眠生理特徵進行優化，減少誤判率
2. **個性化體驗**：系統將學習用戶的個人日間和夜間睡眠模式
3. **技術深度**：展示產品對睡眠科學的深入理解，提升專業形象
4. **用戶信心**：用戶將感受到應用對其實際使用場景（白天小睡vs夜間睡眠）的理解

## 注意事項

- 實施過程中需保持兼容性，確保用戶數據平滑過渡
- 應收集足夠的數據驗證兩種模式下的閾值差異
- 考慮添加用戶校準機制，允許用戶對特定情境提供反饋
- 監測邊界情況，如黃昏或清晨時段的自動分類準確性 