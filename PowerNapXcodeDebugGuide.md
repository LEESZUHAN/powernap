# PowerNap 專案除錯歷史與開發指南

## 指南背景與目的

**重要提示：** 本指南記錄了專案在先前開發階段（特別是在嘗試統一 `AgeGroup` 類型定義和重構 `PowerNapViewModel` 時）所遇到的**一系列頑固的建置錯誤**，主要表現為 Xcode 無法正確解析類型和模組（"Cannot find type..."）。

儘管嘗試了包括深度清理和創建新 Target 在內的多種除錯手段，這些問題依然存在，強烈暗示原始 `.xcodeproj` 文件可能存在難以修復的設定損壞。

**因此，最終決定回退到一個之前的穩定版本作為新的開發起點。**

本文件的**主要目的**是：

1.  **記錄歷史問題：** 作為備忘錄，記錄過去遇到的陷阱。
2.  **總結經驗教訓：** 提煉出處理依賴管理、共享類型、Actor 模型和專案設定的最佳實踐。
3.  **指導未來開發：** 為後續（從穩定版本開始）添加新功能或進行重構時，提供參考，**避免重蹈覆轍**。
4.  **追蹤已知問題：** TODO 列表記錄了當前版本（回退後的版本）中已知需要處理的具體事項。

**請注意：** 文中描述的部分錯誤和解決方案是針對**過去那個有問題的專案狀態**，而不是直接描述回退後的當前程式碼庫。

---

## 開發流程建議 (混合策略)

為了在效率和穩定性之間取得平衡，建議採用以下開發流程：

1.  **關鍵性/結構性修改：**
    *   **範圍：** 添加新 Service、修改 ViewModel 核心邏輯、調整 Service 間交互、重新實現複雜功能等。
    *   **流程：** 在嘗試編譯**前**，建議利用 AI 輔助檢查程式碼是否符合本指南中的最佳實踐（如單一 `AgeGroup` 引用、正確的 ViewModel 初始化、依賴方向等）。

2.  **小型/獨立修改：**
    *   **範圍：** 修改 UI 佈局、在 Service 內部添加輔助方法、修改單文件內部邏輯等。
    *   **流程：** 可以**直接建置 (⌘+B)**，依賴 Xcode 捕捉明顯錯誤。

3.  **遇到任何建置錯誤時：**
    *   特別是與類型找不到、模組、依賴相關的錯誤，請將完整的錯誤日誌提供給 AI 進行分析。

4.  **持續參考本指南：** 在開發過程中，經常回顧本指南中的最佳實踐部分。

---

## 核心問題回顧

在開發過程中，我們遇到了幾個關鍵的建置與架構問題：

1.  **類型重複定義：** 主要體現在 `AgeGroup` 枚舉在多個服務文件中被重複定義，導致編譯器報 `Invalid redeclaration` 錯誤。
2.  **類型/模組解析錯誤：** 在統一類型定義和重構 ViewModel 後，出現了大量的 `Cannot find type 'XXXService' in scope` 錯誤。即使執行了深度清理和創建新 Target，此問題依然頑固存在，高度懷疑是 `.xcodeproj` 文件設定損壞或 Xcode 索引/建置系統的深層問題。
3.  **Swift Concurrency 初始化錯誤：** 在處理 ViewModel 的服務依賴初始化時，遇到了在非同步上下文調用 `@MainActor` 隔離的初始化方法的錯誤。
4.  **過時 API 使用：** 部分服務（如 `TestReportService`, `PermissionManager`）使用了在新版 watchOS SDK 中已更改或移除的 API。

本指南旨在提供解決這些問題的標準方法和未來開發的最佳實踐。

## 1. 統一共享類型定義 (以 AgeGroup 為例)

**目標：** 確保像 `AgeGroup` 這樣的共享數據類型在整個 App Target 中只有一份唯一定義。

**步驟：**

1.  **創建單一來源文件：**
    *   創建一個獨立的 Swift 文件（例如 `AgeGroup.swift`）。
    *   將共享類型（如 `enum AgeGroup`）完整定義在此文件中。
    *   **範例 (`AgeGroup.swift`)：**
        ```swift
        import Foundation

        // 確保訪問控制允許其他文件訪問 (internal 或 public)
        public enum AgeGroup: String, CaseIterable, Codable, Identifiable {
            case teen = "青少年 (10-17歲)"
            case adult = "成人 (18-59歲)"
            case senior = "銀髮族 (60歲以上)"
            
            public var id: String { self.rawValue }
            
            // 根據需要添加計算屬性或方法
            public var heartRateThresholdPercentage: Double { /* ... */ }
            public var minDurationForSleepDetection: TimeInterval { /* ... */ }
            public static func forAge(_ age: Int) -> AgeGroup { /* ... */ }
        }
        ```

2.  **確保 Target Membership：**
    *   在 Xcode 中選中此文件 (`AgeGroup.swift`)。
    *   打開 File Inspector (⌘+⌥+1)。
    *   在 "Target Membership" 部分，**確保只勾選了你的主 App Target**（例如 `PowerNap Watch App V2`）。

3.  **移除舊定義：**
    *   仔細檢查所有其他 `.swift` 文件（特別是 Service 文件）。
    *   **刪除**任何舊的、重複的 `AgeGroup`（或其他同名衝突類型，如 `AgeGroupType`, `PersonalizedHRAgeGroup` 等）的 `enum`, `struct`, 或 `class` 定義。
    *   **刪除**所有相關的 `typealias AgeGroup = ...` 語句。

4.  **直接引用：**
    *   在需要使用 `AgeGroup` 的地方（例如 ViewModel 或 Service），直接使用類型名稱 `AgeGroup` 即可。
    *   **通常不需要**在文件頂部添加 `import ModuleName.AgeGroup`，因為它們在同一個 Target/Module 中。

## 2. 服務依賴管理與 ViewModel 初始化

**目標：** 清晰、安全地在 ViewModel 中管理和初始化其依賴的 Service。

**最佳實踐：**

1.  **屬性宣告：** 在 ViewModel 中，使用實際的 Service 類型來宣告屬性。
    ```swift
    @MainActor // ViewModel 通常在主線程操作 UI
    class PowerNapViewModel: ObservableObject {
        private let healthKitService: HealthKitService
        private let motionService: MotionService
        // ... 其他服務
    ```

2.  **依賴注入 (Initialization):**
    *   **推薦方式：** 在 ViewModel 的 `init` 方法**內部**創建服務實例。
    *   **處理 Actor 隔離：** 如果 ViewModel 或 Service 被標記為 Actor（如 `@MainActor`），直接在 `init` 內部創建實例是安全的，因為 `init` 會在同一個 Actor 上下文中執行。
    *   **避免參數預設值：** **不要**在 `init` 的參數列表中為 Actor 隔離的服務提供預設值（如 `init(healthKitService: HealthKitService = HealthKitService())`），這會導致非同步上下文調用錯誤。
    *   **範例 (`PowerNapViewModel.swift`)：**
        ```swift
        init() {
            // 在 init 內部創建服務實例
            self.healthKitService = HealthKitService()
            self.motionService = MotionService()
            self.notificationService = NotificationService()
            self.ageGroupService = AgeGroupService()
            // ... 其他服務

            // 需要其他服務實例來初始化的服務
            self.personalizedHRModel = PersonalizedHRModelService(ageGroup: ageGroupService.currentAgeGroup)
            self.sleepDetectionService = SleepDetectionService(
                healthKitService: self.healthKitService,
                motionService: self.motionService,
                personalizedHRModel: self.personalizedHRModel
            )
            
            // ... 執行其他初始化，如 loadUserPreferences(), setupBindings()
            loadUserPreferences()
            setupBindings()
        }
        ```

3.  **綁定 (Bindings):** 使用 Combine 的 `assign(to:)` 或 `sink` 來訂閱 Service 發布的更新。
    ```swift
    private func setupBindings() {
        healthKitService.$latestHeartRate
            .receive(on: DispatchQueue.main) // 確保在主線程更新
            .assign(to: &$heartRate) // 直接賦值給 @Published 屬性
        
        sleepDetectionService.$currentSleepState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.currentSleepState = state
                self?.handleSleepStateChange(state) // 觸發額外邏輯
            }
            .store(in: &cancellables)
    }
    ```

## 3. 處理頑固的建置錯誤 (歷史經驗)

當遇到即使清理後仍然存在的類型找不到問題時，按以下順序嘗試：

1.  **確認 Target Membership：** 再次仔細檢查**所有**相關文件（ViewModel, Services, Models, Views, 共享類型文件）是否都已正確添加到**當前**的 App Target。這是最基本但也容易出錯的地方。
2.  **檢查訪問控制 (Access Control)：** 確保所有需要被其他文件引用的 `class`, `struct`, `enum` 都具有正確的訪問級別（至少是 `internal` - 默認，或根據需要設為 `public`）。確認沒有意外標記為 `private` 或 `fileprivate`。
3.  **檢查循環依賴：** 思考是否存在 A 依賴 B，而 B 又直接或間接依賴 A 的情況。嘗試通過協議或調整依賴關係來打破循環。
4.  **標準清理：**
    *   Xcode 菜單 -> Product -> Clean Build Folder (Shift+Command+K)。
    *   關閉 Xcode。
    *   **刪除 Derived Data：** 在終端執行 `rm -rf ~/Library/Developer/Xcode/DerivedData/YOUR_PROJECT_NAME*` (將 `YOUR_PROJECT_NAME` 替換為你的專案名)。
    *   重新開啟 Xcode 並建置。
5.  **深度清理（如標準清理無效）：**
    *   完全退出 Xcode。
    *   打開 Finder，導航到專案目錄。
    *   **顯示隱藏檔案** (Command + Shift + .)。
    *   **刪除** `.swiftpm` 資料夾 (如果存在)。
    *   **刪除** `.xcworkspace` 文件 (如果存在)。
    *   在 `.xcodeproj` 文件上右鍵 -> "顯示套件內容"，**刪除**內部的 `xcuserdata` 資料夾。
    *   重新打開 `.xcodeproj` 文件（如果沒有 `.xcworkspace`）。
    *   等待 Xcode 完成索引後再建置。
6.  **創建新 Target（如深度清理無效）：**
    *   在現有專案中創建一個全新的 App Target。
    *   **手動**將所有必要的 `.swift` 文件和資源文件（特別是 `Assets.xcassets`）添加到新 Target 的 "Build Phases" 中。
    *   配置新 Target 的 Bundle ID、簽名等。
    *   選擇新 Target 的 Scheme 並建置。
7.  **創建新專案（最終手段）：**
    *   創建一個全新的 Xcode 專案。
    *   將舊專案的程式碼和資源複製並添加到新專案中。

## 4. 開發最佳實踐總結

*   **單一職責原則：** 讓每個 Service 專注於特定領域（健康、運動、通知等）。
*   **清晰的依賴關係：** ViewModel 持有並管理 Service，避免 Service 反向依賴 ViewModel。如果 Service 間需要通信，考慮使用 Combine Publisher/Subscriber 或協議/委託。
*   **統一數據模型：** 對於跨多個服務使用的數據結構（如 `AgeGroup`），定義在一個共享文件中，並確保所有地方都引用這個唯一定義。
*   **Actor 模型：** 善用 Swift Concurrency 和 `@MainActor` 來確保線程安全，特別是在更新 UI 或處理來自不同線程的回調時。注意 Actor 隔離規則對初始化的影響。
*   **依賴注入：** 在初始化時明確傳入依賴項（如 Service 實例），有利於測試和維護。
*   **定期清理：** 在進行較大重構或遇到奇怪的建置問題時，執行標準或深度清理。
*   **版本控制：** 在進行重大修改前，務必提交當前穩定版本到 Git。

## 5. 當前 TODO 列表 (基於回退後的版本)

- [ ] 檢查 `powernap Watch App/Services/HealthStatsSettingsView.swift` 的用途和位置，考慮將其移動到 `Views` 或更合適的目錄下。
- [ ] 修復 `TestReportService.swift` 中的 WatchKit API 錯誤 (`presentActivityController`, `orientation` 等)。考慮使用 SwiftUI 的 `ShareLink` 替代舊的共享方式。
- [ ] 實現 `PersonalizedHRModelService` 中的 `updateAgeGroup(_:)` 方法的實際邏輯。
- [ ] 處理 `PermissionManager.swift` 中打開 URL 的反射代碼警告（如果可能，尋找不依賴 WatchKit 的替代方案，或接受警告）。
- [ ] 檢查並修復 `PowerNapView.swift` 中因移除 `isSessionActive` 而導致的 UI 邏輯錯誤，改用 `napState` 判斷。

---

**備註：** Xcode 的建置系統有時確實會表現得很奇怪。遇到無法解釋的問題時，按照清理層級逐步嘗試，並仔細檢查 Target Membership 和訪問控制通常是解決問題的關鍵。如果所有方法都失敗，創建新 Target 或新專案雖然費時，但往往能根除問題。 