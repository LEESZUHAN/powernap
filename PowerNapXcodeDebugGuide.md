# PowerNap專案除錯指南：解決AgeGroup類型定義衝突

## 問題背景

在Xcode專案中出現了同一類型（特別是`AgeGroup`枚舉）在多個檔案中重複定義的問題，導致編譯錯誤。

## 1. 確認並移除重複定義

### 步驟1.1：搜尋所有`AgeGroup`定義
```bash
cd /Users/michaellee/Documents/PowerNap
grep -r "enum AgeGroup" --include="*.swift" .
```

### 步驟1.2：檢查專案中的編譯源檔案
- 打開Xcode
- 選擇PowerNap Watch App目標
- 前往Build Phases > Compile Sources
- 確認沒有重複的檔案或已刪除的檔案仍在列表中

## 2. 集中定義一個共享的AgeGroup

### 步驟2.1：創建一個共享的AgeGroup.swift檔案
```swift
// AgeGroup.swift
import Foundation

public enum AgeGroup {
    case teen     // 10-17歲
    case adult    // 18-59歲
    case senior   // 60歲以上
    
    // 心率閾值百分比
    var heartRateThresholdPercentage: Double {
        switch self {
        case .teen: return 0.7
        case .adult: return 0.65
        case .senior: return 0.6
        }
    }
    
    // 睡眠檢測的最小持續時間（秒）
    var minDurationForSleepDetection: TimeInterval {
        switch self {
        case .teen: return 180
        case .adult: return 240
        case .senior: return 300
        }
    }
    
    // 根據實際年齡確定年齡組
    static func forAge(_ age: Int) -> AgeGroup {
        if age >= 60 {
            return .senior
        } else if age >= 18 {
            return .adult
        } else {
            return .teen
        }
    }
}
```

### 步驟2.2：確保此檔案被添加到正確的目標（Target）中
- 將AgeGroup.swift添加到Watch App目標中
- 確保Access Control設為`public`讓所有檔案都能訪問

## 3. 修改引用AgeGroup的服務檔案

### 步驟3.1：從服務檔案中移除AgeGroup定義
檢查並修改以下檔案，移除各自的AgeGroup定義：
- SleepDetectionService.swift
- PersonalizedHRModelService.swift
- AgeGroupService.swift

### 步驟3.2：更新各服務中的引用
確保各服務檔案直接使用共享的AgeGroup定義：

```swift
// 示例：AgeGroupService.swift
import Foundation

class AgeGroupService: ObservableObject {
    @Published var currentAgeGroup: AgeGroup = .adult
    
    func updateAgeGroup(age: Int) {
        currentAgeGroup = AgeGroup.forAge(age)
    }
}
```

## 4. 徹底清理專案

### 步驟4.1：清理Xcode的構建文件夾
- Xcode選單 > Product > Clean Build Folder
- 或使用快捷鍵：Shift + Command + K

### 步驟4.2：關閉Xcode並清理Derived Data
```bash
cd /Users/michaellee/Documents/PowerNap
rm -rf ~/Library/Developer/Xcode/DerivedData/powernap*
```

### 步驟4.3：重新開啟Xcode並構建專案

## 5. 處理引用問題

如果出現類似「Cannot find type 'HealthKitService' in scope」的錯誤：

### 步驟5.1：確認服務檔案在同一模組中
- 檢查所有服務檔案是否都添加到同一目標（Watch App）

### 步驟5.2：添加必要的import語句
如果檔案分屬不同模組，在需要的檔案頂部添加適當的import語句：
```swift
import powernap_Watch_App  // 使用你實際的模組名稱
```

## 6. 處理特殊情況：多Target環境

如果在多個Target（如iOS和watchOS）中需要共享AgeGroup：

### 步驟6.1：創建共享Framework或Swift Package
- 創建一個包含共享類型的新Framework或Swift Package
- 將AgeGroup定義移動到此Framework中

### 步驟6.2：在各個目標中引用此Framework
```swift
import SharedPowerNapTypes  // 共享Framework的名稱
```

## 7. 調試常見錯誤

### 錯誤1：「Invalid redeclaration of 'AgeGroup'」
- **原因**: 多處定義了同名類型
- **解決**: 確保整個專案中只有一個AgeGroup定義

### 錯誤2：「Cannot find type 'AgeGroup' in scope」
- **原因**: 定義的AgeGroup不在當前作用域
- **解決**: 添加正確的import語句或確保檔案在同一模組

### 錯誤3：「Cannot find 'XXXService' in scope」
- **原因**: 服務類不在當前作用域
- **解決**: 添加適當的import語句或檢查服務類的可見性修飾符

## 8. 驗證解決方案

### 步驟8.1：構建專案
- 確認沒有編譯錯誤

### 步驟8.2：運行專案
- 確認功能正常
- 驗證AgeGroup的所有使用都正確生效

### 步驟8.3：檢查引用一致性
- 確認所有檔案都以相同方式引用AgeGroup

---

## 備註

調試過程可能需要多次嘗試不同的方法。每次重大變更後，建議執行完整的清理步驟（步驟4）以確保不受快取干擾。

如果問題依然存在，請考慮創建一個簡化版的測試專案，以證明共享類型定義的方法是否可行。 