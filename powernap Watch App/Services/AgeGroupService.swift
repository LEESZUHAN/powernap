import Foundation
import HealthKit
import SwiftUI

// 確保AgeGroup在範圍內
// 此處導入主模塊中定義的AgeGroup
// 如果在同一模塊中，此導入可能是多餘的，但為了安全起見仍然添加

/// 專門處理用戶年齡組相關功能的服務
class AgeGroupService: ObservableObject {
    /// 用戶當前選擇的年齡組
    @Published var currentAgeGroup: AgeGroup = .adult {
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
                    let detectedAgeGroup = AgeGroup.forAge(age)
                    
                    // 如果與當前不同，更新年齡組
                    if detectedAgeGroup != currentAgeGroup {
                        currentAgeGroup = detectedAgeGroup
                        print("已從HealthKit更新用戶年齡組為: \(detectedAgeGroup)")
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