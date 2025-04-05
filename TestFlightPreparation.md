# TestFlight 準備與部署指南

## 前期準備工作（開發者帳戶批准前）

### 1. 應用程式資料準備

- **基本資訊**
  - [x] 確定最終應用名稱：PowerNap
  - [x] 撰寫應用簡短描述（約 170 字元）：「PowerNap 專為 Apple Watch 設計，透過結合 HRV 與活動偵測，協助你在恰到好處的時間小睡並輕鬆醒來，讓日常生活更有活力。」
  - [x] 撰寫完整應用描述（已創建於 PowerNap_AppDescription.md）
  - [x] 準備 5-10 個關鍵字，用於 App Store 搜尋：PowerNap, Apple Watch, 小睡, HRV, 睡眠偵測, 倒數計時, 健康, 能量補充
  - [x] 確定應用分類（健康與健身）和次要分類（生活品味）

- **視覺資源**
  - [x] 設計並製作 App Icon 所有規格
    - [x] 1024x1024 App Store 圖示（無透明、無圓角）
  - [ ] 準備 App Store 預覽截圖
    - [x] Apple Watch 各尺寸截圖（最少 1 張，建議 3-5 張）
    - [ ] 可選：準備功能展示影片（30 秒內）
  - [ ] 設計宣傳用橫幅圖片（可選）

### 2. 技術準備

- **應用配置**
  - [x] 確保應用有唯一的 Bundle ID（格式：com.公司名.應用名）：com.michaellee.powernap
  - [x] 設定版本號和構建版本號系統：
     - 當前版本號：1.0（對外顯示的版本）
     - 當前構建號：1（內部追蹤用）
     - 更新策略：版本號採用語意化版本控制 (例如 1.0.0)，主要更新第一位，新功能更新第二位，錯誤修復更新第三位；構建號每次提交到 TestFlight 時遞增
  - [x] 配置所需權限描述：
     - NSHealthShareUsageDescription：存取健康數據分析HRV
     - NSHealthUpdateUsageDescription：儲存睡眠資訊到健康App
     - NSMotionUsageDescription：使用動作感測器偵測入睡
     - NSUserNotificationsUsageDescription：發送喚醒通知
     - 背景模式：audio, processing, mindfulness, workout-processing
  - [x] 配置必要的 App Groups：經評估目前不需要，應用功能不涉及跨組件數據共享
  - [x] 確保應用支援的 watchOS 最低版本設定：需要調整為 watchOS 10.0（目前設定為 11.2，建議修改為擴大支援範圍）

- **用戶隱私**
  - [x] 準備隱私政策網頁或文檔：
     - 已建立隱私政策文件 (PrivacyPolicy.md)，包含中英雙語版本
     - 內容符合 App Store 要求，包含數據收集範圍、使用目的、存儲方式及用戶權利
     - GitHub 儲存庫連結: https://github.com/LEESZUHAN/powernap/blob/main/PrivacyPolicy.md
     - 注意：提交 App Store 時需要提供一個公開的 URL，建議設置 GitHub Pages: https://leeszuhan.github.io/powernap/PrivacyPolicy.md
  - [x] 列出應用收集的用戶數據類型：
     - 健康數據：心率變異性 (HRV)
     - 運動數據：加速度計數據（用於偵測睡眠）
     - 睡眠分析數據：入睡時間、喚醒時間、睡眠時長
     - 應用使用數據：功能使用頻率、時間設定偏好等（用於改進應用）
  - [x] 確認數據使用符合 Apple 隱私政策要求：
     - 隱私政策明確聲明所有健康數據僅用於應用功能所需，不會分享給第三方
     - 僅收集核心功能必要的數據
     - 提供了用戶數據存取和刪除機制的說明

### 3. 測試計劃準備

- **測試文檔**
  - [ ] 撰寫測試目標與範圍說明
  - [ ] 列出待測試的核心功能清單
  - [ ] 設定測試優先級項目
  - [ ] 撰寫已知問題或限制說明

- **測試指南**
  - [ ] 製作測試者操作手冊
  - [ ] 撰寫功能使用說明
  - [ ] 設計反饋問卷或反饋重點

- **測試場景**
  - [ ] 設計特定測試場景（如：不同時間的短暫小睡）
  - [ ] 準備比較基準（如何判斷功能效果）

### 4. 測試者管理

- **內部測試群組**
  - [ ] 整理內部團隊成員名單和電子郵件
  - [ ] 確認內部測試者都有有效的 Apple ID
  - [ ] 準備內部測試者分工和責任

- **外部測試群組**
  - [ ] 整理外部測試者名單和電子郵件（最多 10,000 人）
  - [ ] 將測試者分組（基於設備類型、測試目的等）
  - [ ] 準備測試邀請訊息範本

## TestFlight 部署步驟（需開發者帳戶）

### 1. App Store Connect 設定

- [ ] 登入 [App Store Connect](https://appstoreconnect.apple.com)
- [ ] 建立新應用（「我的應用程式」→「+」→「新應用程式」）
- [ ] 填寫應用基本資訊
  - 平台：watchOS
  - 名稱、語言、Bundle ID
  - SKU：內部追蹤代碼
  - 用戶存取權：完整或有限

### 2. 應用版本資訊設定

- [ ] 上傳準備好的 App Icon 和截圖
- [ ] 填寫促銷文字和關鍵字
- [ ] 提供隱私政策 URL
- [ ] 設定應用價格與可用地區
- [ ] 填寫版本發布資訊

### 3. TestFlight 配置

- [ ] 切換到「TestFlight」標籤
- [ ] 設定測試資訊
  - 測試版說明
  - 反饋聯絡資訊
  - 測試版的新功能描述
- [ ] 建立內部測試群組
- [ ] 建立外部測試群組（可按功能、地區等分類）

### 4. 上傳構建版本

- [ ] 在 Xcode 中建立發布構建版本
  - 選擇「Any watchOS Device」或特定設備
  - 選擇「Product」→「Archive」
- [ ] 使用 Xcode 上傳構建版本
  - 在 Organizer 中選擇構建版本
  - 點擊「Distribute App」→「TestFlight & App Store」
  - 按照提示完成上傳流程
- [ ] 等待構建版本處理完成（通常需要 30 分鐘左右）

### 5. 測試版部署

- [ ] 內部測試（無需審核）
  - 分配構建版本到內部測試群組
  - 邀請內部測試者
  - 收集內部反饋和修復問題
- [ ] 外部測試（需要審核）
  - 提交 Beta App 審核
  - 審核通過後向外部測試者發送邀請
  - 管理測試者反饋

### 6. 測試與迭代

- [ ] 監控測試者參與情況
- [ ] 收集並分析測試者反饋
- [ ] 修復發現的問題
- [ ] 上傳新的構建版本
- [ ] 通知測試者新版本可用

### 7. 測試完成後的步驟

- [ ] 分析最終測試報告
- [ ] 決定是否準備好上架 App Store
- [ ] 準備正式發布版本
- [ ] 更新 App Store 資訊（如有必要）
- [ ] 提交應用進行 App Store 審核

## 實用資源

- [Apple TestFlight 官方文檔](https://developer.apple.com/testflight/)
- [App Store 審核指南](https://developer.apple.com/app-store/review/guidelines/)
- [watchOS 人機介面指南](https://developer.apple.com/design/human-interface-guidelines/watchos)
- [App Store 產品頁面最佳做法](https://developer.apple.com/app-store/product-page/)

## 注意事項

- 內部測試限制：100 名測試者
- 外部測試限制：10,000 名測試者
- 測試版期限：從上傳日期起 90 天
- Beta App 審核通常需要 1-2 天
- 測試者需要安裝 TestFlight 應用才能參與測試 