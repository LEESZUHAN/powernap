import Foundation
import HealthKit
import SwiftUI

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

/// 專門處理用戶年齡組相關功能的服務
class AgeGroupService: ObservableObject {
    /// 用戶當前選擇的年齡組
    @Published var currentAgeGroup: AgeGroup {
        didSet {
            // 當年齡組變更時，儲存到UserDefaults
            saveAgeGroup()
        }
    }
    
    /// 健康商店實例，用於獲取出生日期
    private let healthStore = HKHealthStore()
    
    /// UserDefaults鍵值
    private let ageGroupKey = "userAgeGroup"
    
    /// 初始化，優先讀取已存儲的年齡組
    init() {
        // 嘗試從UserDefaults讀取之前儲存的年齡組
        if let savedData = UserDefaults.standard.data(forKey: ageGroupKey),
           let savedAgeGroup = try? JSONDecoder().decode(AgeGroup.self, from: savedData) {
            self.currentAgeGroup = savedAgeGroup
        } else {
            // 無存儲數據時使用預設值（成人）
            self.currentAgeGroup = .adult
        }
        
        // 啟動時嘗試從HealthKit讀取實際年齡
        Task {
            await detectAgeFromHealthKit()
        }
    }
    
    /// 保存當前年齡組到UserDefaults
    private func saveAgeGroup() {
        if let encodedData = try? JSONEncoder().encode(currentAgeGroup) {
            UserDefaults.standard.set(encodedData, forKey: ageGroupKey)
        }
    }
    
    /// 從HealthKit中獲取用戶實際年齡並設置對應年齡組
    @MainActor
    func detectAgeFromHealthKit() async {
        // 僅當HealthKit可用時嘗試獲取
        guard HKHealthStore.isHealthDataAvailable() else {
            return
        }
        
        // 定義需要讀取的數據類型（出生日期）
        let birthDateType = HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
        
        do {
            // 請求權限
            try await healthStore.requestAuthorization(toShare: [], read: [birthDateType])
            
            // 嘗試獲取出生日期
            if let birthDateComponents = try? healthStore.dateOfBirthComponents() {
                if let birthDate = birthDateComponents.date {
                    // 計算年齡
                    let age = calculateAge(from: birthDate)
                    
                    // 設置對應年齡組
                    let detectedAgeGroup = AgeGroup.from(age: age)
                    
                    // 如果與當前不同，更新年齡組
                    if detectedAgeGroup != currentAgeGroup {
                        currentAgeGroup = detectedAgeGroup
                        print("已從HealthKit更新用戶年齡組為: \(detectedAgeGroup.rawValue)")
                    }
                }
            }
        } catch {
            print("無法從HealthKit讀取出生日期: \(error.localizedDescription)")
        }
    }
    
    /// 計算從出生日期到現在的年齡
    private func calculateAge(from birthDate: Date) -> Int {
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: birthDate, to: Date())
        return ageComponents.year ?? 0
    }
    
    /// 手動設置年齡組
    func setAgeGroup(_ newAgeGroup: AgeGroup) {
        currentAgeGroup = newAgeGroup
    }
} 