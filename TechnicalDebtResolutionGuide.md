# PowerNap 技術債修正指導文件

## 1. 命名一致性問題
### 問題描述
專案中存在命名不一致的情況，主要是從HRV（心率變異性）到HR（心率）的轉換過程中，某些引用可能未更新。

### 修復方案
- 檢查所有引用 `HRVDisplayView` 的地方，確保它們已更新為 `HeartRateDisplayView`
- 檢查所有使用 `hrv` 作為變數或方法名稱的地方，確保它們已適當重命名為 `heartRate` 或 `hr`
- 檢查日誌中是否還有使用 `.hrv` 類型的地方，應相應更新

### 具體步驟
1. 使用全局搜索找出所有 `HRV` 或 `hrv` 的引用
2. 對每個引用進行評估，判斷是否需要更新
3. 執行重命名操作，確保引用和實際定義保持一致

## 2. 型別導入問題
### 問題描述
多個文件中出現「Cannot find type 'X' in scope」等錯誤，表明缺少必要的導入語句。

### 修復方案
在適當的文件中添加必要的 `import` 語句：
- `import Foundation`
- `import SwiftUI`
- `import Combine`
- `import HealthKit`
- `import CoreMotion` 等

### 具體步驟
1. 為 `SleepDetectionService.swift` 添加必要的導入：
   ```swift
   import Foundation
   import Combine
   import SwiftUI
   import HealthKit
   ```

2. 確保 `PowerNapViewModel.swift` 導入了所有依賴的服務類：
   ```swift
   import Foundation
   import Combine
   import SwiftUI
   import CoreMotion
   import HealthKit
   ```

3. 檢查其他所有出現型別錯誤的文件，添加相應的導入語句

## 3. AgeGroup 重複定義問題
### 問題描述
在 `UserSleepProfile.swift` 和 `HealthKitService.swift` 中都定義了 `AgeGroup` 枚舉，這將導致型別衝突。

### 修復方案
1. **方案A**：創建一個單獨的 `AgeGroup.swift` 文件，將 `AgeGroup` 定義放在那裡，然後在需要的地方導入。
2. **方案B**：保留 `HealthKitService.swift` 中的定義，修改 `UserSleepProfile.swift` 中的代碼以使用導入的 `AgeGroup`。

### 具體步驟（採用方案A）
1. 創建一個新的文件 `Models/AgeGroup.swift`：
   ```swift
   import Foundation
   
   public enum AgeGroup: String, CaseIterable, Identifiable, Codable {
       case teen = "10-17歲"
       case adult = "18-59歲"
       case senior = "60歲以上"
       
       public var id: String { self.rawValue }
       
       public var hrThresholdPercentage: Double {
           switch self {
           case .teen: return 0.875 // 87.5% (85-90%)
           case .adult: return 0.9  // 90%
           case .senior: return 0.935 // 93.5% (92-95%)
           }
       }
       
       public var sleepConfirmationTime: TimeInterval {
           switch self {
           case .teen: return 120  // 2分鐘
           case .adult: return 180 // 3分鐘
           case .senior: return 240 // 4分鐘
           }
       }
   }
   ```

2. 從 `HealthKitService.swift` 和 `UserSleepProfile.swift` 中移除 `AgeGroup` 的定義
3. 在這兩個文件中添加 `import` 語句以使用共享的 `AgeGroup` 定義

## 4. 日誌類型不匹配
### 問題描述
在 `SleepDetectionService` 中使用 `logManager.log(.sleep, ...)` 等方法時，可能出現日誌類型與 `LogManager` 中定義的 `LogCategory` 不匹配的情況。

### 修復方案
確保所有日誌調用使用的類型與 `LogManager.LogCategory` 中定義的枚舉值一致。

### 具體步驟
1. 檢查 `LogManager.swift` 中的 `LogCategory` 定義：
   ```swift
   enum LogCategory: String, CaseIterable {
       case hrv = "心率變異"
       case motion = "動作數據"
       case sleep = "睡眠狀態"
       case system = "系統"
       case error = "錯誤"
   }
   ```

2. 將所有日誌記錄調用更新為使用正確的類型：
   - 使用 `.sleep` 用於睡眠狀態相關日誌
   - 考慮將 `.hrv` 更新為 `.heartRate` 或類似的名稱，以保持一致性
   - 使用 `.motion` 用於動作數據相關日誌
   - 使用 `.system` 用於一般系統操作
   - 使用 `.error` 用於錯誤和異常情況

## 5. 心率相關術語混淆
### 問題描述
代碼中混用了 `HRV`（心率變異性）和 `HR`（心率）術語，可能導致概念混淆和潛在錯誤。

### 修復方案
統一使用一致的術語，明確區分心率（HR）和心率變異性（HRV）的概念和用法。

### 具體步驟
1. 檢查所有使用 `HRV` 的地方，判斷它們實際上指的是心率還是心率變異性
2. 重命名方法、變數和屬性以明確它們的用途：
   - `getHRVDescription()` → `getHeartRateDescription()`
   - `hrvValue` → `heartRateValue` 或 `currentHeartRate`
   - `baselineHRV` → `restingHeartRate` 
3. 更新相關的UI文本和注釋，確保用戶界面的一致性

## 6. 編譯效能問題
### 問題描述
`PersonalizedModelTestView` 等一些複雜視圖可能導致"The compiler is unable to type-check this expression in reasonable time"錯誤。

### 修復方案
將復雜視圖拆分為更小的子視圖組件，減少編譯器負擔。

### 具體步驟
1. 拆分 `PersonalizedModelTestView` 為更小的子視圖：
   ```swift
   // 心率數據卡片視圖
   struct HeartRateCardView: View {
       @EnvironmentObject var viewModel: PowerNapViewModel
       
       var body: some View {
           // 心率數據卡片內容
       }
   }
   
   // 個人化模型卡片視圖
   struct PersonalizedModelCardView: View {
       @EnvironmentObject var viewModel: PowerNapViewModel
       @Binding var showingSettingsSheet: Bool
       
       var body: some View {
           // 個人化模型卡片內容
       }
   }
   
   // 睡眠檢測卡片視圖
   struct SleepDetectionCardView: View {
       @EnvironmentObject var viewModel: PowerNapViewModel
       
       var body: some View {
           // 睡眠檢測卡片內容
       }
   }
   
   // 主視圖
   struct PersonalizedModelTestView: View {
       @EnvironmentObject var viewModel: PowerNapViewModel
       @State private var showingSettingsSheet = false
       
       var body: some View {
           ScrollView {
               VStack(spacing: 20) {
                   HeartRateCardView()
                   PersonalizedModelCardView(showingSettingsSheet: $showingSettingsSheet)
                   SleepDetectionCardView()
               }
               .padding()
           }
           .navigationTitle("模型測試")
           .sheet(isPresented: $showingSettingsSheet) {
               AgeGroupSettingsView(viewModel: viewModel)
           }
       }
   }
   ```

2. 同樣方式檢查並拆分其他複雜視圖

## 7. 異步處理問題
### 問題描述
可能存在異步方法調用不正確，或Task的使用不恰當的情況。

### 修復方案
確保所有異步方法和任務正確使用async/await模式。

### 具體步驟
1. 檢查所有包含await的方法調用，確保它們在async函數或Task中執行
2. 確保異步方法的返回值正確處理，特別是可能為nil的情況
3. 檢查Task的使用是否正確，包括生命週期管理和錯誤處理
4. 特別關注跨服務的異步調用，確保數據流正確且沒有競態條件

## 8. 內存管理與循環引用
### 問題描述
可能存在內存泄漏，特別是在服務和視圖模型之間的關係中。

### 修復方案
確保正確使用弱引用(`weak self`)避免循環引用，特別是在閉包和發布-訂閱關係中。

### 具體步驟
1. 檢查所有使用閉包的地方，特別是`.sink`方法內部，確保使用`[weak self]`
2. 檢查所有異步任務中對self的引用，避免長期任務導致的內存泄漏
3. 確保`cancellables`集合正確管理，包括添加和清除操作
4. 檢查服務之間的相互引用，避免形成循環依賴

## 9. 狀態管理與數據流
### 問題描述
視圖模型和服務間的狀態同步可能不完整，導致UI狀態與實際數據不一致。

### 修復方案
確保數據流向清晰，狀態更新完整且及時。

### 具體步驟
1. 檢查所有@Published屬性，確保它們在適當的時候得到更新
2. 檢查UI狀態是否正確反映服務層的實際狀態
3. 確保狀態轉換邏輯完整，不會出現「卡在中間狀態」的情況
4. 檢查用戶操作（如按鈕點擊）是否正確觸發狀態更新

## 總結
透過系統性地解決這些技術債，我們可以提高代碼質量，減少潛在錯誤，並為未來的功能擴展打下堅實基礎。每個問題的修復應該單獨進行，並在修復後進行測試，以確保不會引入新的問題。 

## 修復進度追踪

### 2024-07-15 更新
已完成的任務：

#### 1. 命名一致性問題
- ✅ 已更新 `LogManager.swift` 中的日誌類別從 `.hrv` 改為 `.heartRate`
- ✅ 已更新 `SleepDetectionService.swift` 中使用 `.hrv` 的日誌調用為 `.heartRate`
- ✅ 已更新 `LogsView.swift` 中的 `categoryColor` 方法，針對新的類別名稱進行調整
- ✅ 已更新 `PowerNapModel.swift` 中的命名，將 `hrvBaseline` 改為 `heartRateBaseline`，`HRVReading` 改為 `HeartRateReading`
- ✅ 已更新 `UserSleepProfile.swift` 中的 `sleepHRVariance` 改為 `heartRateVariance` 
- ✅ 已更新 `SleepProfileService.swift` 中相關引用以匹配重命名的變數

#### 2. 型別導入問題
- ✅ 初步為 `SleepDetectionService.swift` 添加必要的導入，包括 `CoreMotion`
- ✅ 創建了 `Models/Shared/AgeGroup.swift` 解決重複定義問題
- ✅ 創建了 `ServiceProtocols.swift` 定義了各服務接口：
  - `HealthServiceProtocol`
  - `MotionServiceProtocol`
  - `SleepProfileServiceProtocol`
  - `LoggingProtocol`

### 2024-07-16 更新
新完成的任務：

#### 1. 命名一致性問題
- ✅ 已更新 `SleepProfileService.swift` 中的 `hrVariance` 為 `heartRateVariance`
- ✅ 已確認代碼庫中大部分 HRV 相關命名已更新為 HR 或 heartRate

#### 2. 型別導入問題
- ⚠️ 發現由於模組結構問題，無法直接使用共享的 `AgeGroup.swift`
- ✅ 已在 `HealthKitService.swift` 添加技術債標記，表明需要後續修改

#### 3. AgeGroup 重複定義問題
- ⚠️ 暫時保留各自定義，但添加了明確的技術債標記
- ✅ 後續需要進行項目結構調整，實現真正的共享模型

### 2024-07-17 更新
新完成的任務：

#### 1. AgeGroup 重複定義問題
- ✅ 已將 `HealthKitService.swift` 中的 AgeGroup 定義添加 public 修飾符
- ✅ 已在 `UserSleepProfile.swift` 中重新添加 AgeGroup 定義並標記為技術債
- ✅ 已在 `Models/Shared/AgeGroup.swift` 中添加技術債標記，說明文件暫時未使用
- ✅ 所有 AgeGroup 定義保持完全一致，確保不會出現不同步問題

#### 2. 長期技術債解決方案
為徹底解決 AgeGroup 重複定義問題，建議未來進行以下重構：

1. **創建共享模型模組**：
   - 將 `AgeGroup` 和其他共享模型移至單獨的模組
   - 確保該模組被所有需要使用這些模型的其他模組正確引用

2. **調整項目結構**：
   - 重組項目文件結構，將共享模型和協議放在合適的位置
   - 更新 Xcode 項目設置，確保模組依賴關係正確

3. **移除重複定義**：
   - 當共享模型模組可用後，刪除 `HealthKitService.swift` 和 `UserSleepProfile.swift` 中的重複定義
   - 更新所有相關引用

### 2024-07-18 更新 - 重建計劃

經過嘗試修復AgeGroup重複定義和其他技術債問題，已決定採取更徹底的方法：從git恢復最後穩定版本並重建HR功能。

#### 重建計劃概述

1. **從git恢復最後穩定版本**
   - 保留當前的技術債文檔和開發指南
   - 暫存未提交的更改，以便後續參考

2. **刪除所有HRV相關代碼**
   - 移除 `HealthKitService.swift` 中所有與HRV相關的函數和變量
   - 刪除 `PowerNapModel.swift` 中的HRV相關邏輯
   - 更新 `SleepDetectionService.swift` 中的檢測邏輯，改為使用HR
   - 移除UI中所有HRV相關顯示和引用

3. **依照HR邏輯重建代碼**
   - 使用心率（HR）替代心率變異性（HRV）進行睡眠檢測
   - 實現基於當前心率與靜息心率比例的檢測邏輯
   - 根據年齡組調整心率閾值判定（如18-59歲：低於RHR的90%）
   - 維持現有的活動監測邏輯與整合

4. **優化項目結構**
   - 建立更清晰的共享模型結構
   - 避免重複定義和類型衝突
   - 改進命名一致性，確保使用統一的術語

**預期優勢**:
- 代碼更簡潔、更一致
- 避免概念混淆（HRV vs HR）
- 結構更合理，減少技術債累積
- 提高代碼可維護性

**重建時間估計**:
- 基礎功能: 1-2天
- 完整功能: 3-4天
- 測試和優化: 1-2天

### 待完成任務
- 處理異步處理問題
- 檢查內存管理與循環引用
- 優化狀態管理與數據流 