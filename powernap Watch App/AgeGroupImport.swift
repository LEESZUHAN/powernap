import Foundation

// 此文件用於確保所有服務檔案都能正確引用AgeGroup
// 在改用集中定義的AgeGroup之前，各服務檔案中使用了各自的AgeGroup定義
// 為了平滑過渡，我們保留這些定義，但在未來的版本中應該統一使用集中定義

// 提供向後兼容性
// 對於任何找不到AgeGroup定義的文件，可以導入此文件獲取類型定義
// 在Swift模塊系統完全修復之前，這是一個臨時解決方案

#if canImport(powernap_Watch_App)
// 如果在模塊內部，則直接使用AgeGroup
#else
// 如果不在模塊內部，則提供AgeGroup的定義
import Foundation

public enum AgeGroup: String, CaseIterable, Codable, Identifiable {
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
    
    // 用於列表識別的ID
    public var id: String { self.rawValue }
}
#endif 