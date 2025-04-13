// AgeGroup.swift - 共享定義
import Foundation

/// 用戶年齡組定義
public enum AgeGroup: String, CaseIterable, Codable, Identifiable {
    /// 青少年組 (10-17歲)
    case teen = "青少年 (10-17歲)"
    
    /// 成人組 (18-59歲)
    case adult = "成人 (18-59歲)"
    
    /// 銀髮族 (60歲以上)
    case senior = "銀髮族 (60歲以上)"
    
    /// 用於列表識別的ID
    public var id: String { self.rawValue }
    
    /// 心率閾值百分比 - 低於靜息心率多少比例視為可能入睡
    /// 原名：hrThresholdPercentage
    public var heartRateThresholdPercentage: Double {
        switch self {
        case .teen:   return 0.875  // 87.5% (低於靜息心率的85-90%)
        case .adult:  return 0.9    // 90% (低於靜息心率的10%)
        case .senior: return 0.935  // 93.5% (低於靜息心率的6.5%)
        }
    }
    
    /// 持續時間要求 - 需要維持多少秒的低心率才判定為入睡
    /// 原名：minDurationSeconds
    public var minDurationForSleepDetection: TimeInterval {
        switch self {
        case .teen:   return 120  // 2分鐘
        case .adult:  return 180  // 3分鐘
        case .senior: return 240  // 4分鐘
        }
    }
    
    /// 根據實際年齡獲取對應年齡組
    /// 原名：from(age:)
    public static func forAge(_ age: Int) -> AgeGroup {
        switch age {
        case 0..<18:  return .teen
        case 18..<60: return .adult
        default:      return .senior
        }
    }
} 