import Foundation
import SwiftUI

/// 應用版本管理服務 - 處理版本更新和數據遷移
class AppVersionService: ObservableObject {
    /// 當前應用版本
    @Published private(set) var currentVersion: String
    
    /// 當前應用構建號
    @Published private(set) var currentBuild: String
    
    /// 是否為新安裝或更新後首次啟動
    @Published private(set) var isFirstLaunchAfterUpdate: Bool = false
    
    /// 版本相關的UserDefaults鍵
    private let lastVersionKey = "lastAppVersion"
    private let lastBuildKey = "lastAppBuild"
    
    /// 初始化
    init() {
        // 獲取當前版本和構建號
        let infoDictionary = Bundle.main.infoDictionary
        currentVersion = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        currentBuild = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        
        // 檢查版本變更
        checkVersionChange()
    }
    
    /// 檢查應用版本是否有變更，若有則執行數據遷移
    private func checkVersionChange() {
        let defaults = UserDefaults.standard
        
        // 獲取上一次啟動的版本
        let lastVersion = defaults.string(forKey: lastVersionKey) ?? ""
        let lastBuild = defaults.string(forKey: lastBuildKey) ?? ""
        
        // 檢查版本變更
        if lastVersion.isEmpty {
            // 首次安裝應用
            print("檢測到首次安裝應用，版本：\(currentVersion) (構建號：\(currentBuild))")
            isFirstLaunchAfterUpdate = true
        } else if lastVersion != currentVersion || lastBuild != currentBuild {
            // 版本已更新
            print("檢測到應用更新：\(lastVersion) -> \(currentVersion) (構建號：\(lastBuild) -> \(currentBuild))")
            isFirstLaunchAfterUpdate = true
            
            // 執行數據遷移
            migrateDataFromVersion(lastVersion, toBuild: lastBuild)
        } else {
            print("應用版本未變更：\(currentVersion) (構建號：\(currentBuild))")
        }
        
        // 更新儲存的版本號
        defaults.set(currentVersion, forKey: lastVersionKey)
        defaults.set(currentBuild, forKey: lastBuildKey)
    }
    
    /// 遷移數據 - 基於版本號執行特定的遷移操作
    private func migrateDataFromVersion(_ oldVersion: String, toBuild oldBuild: String) {
        // 根據版本執行特定遷移任務
        let versionParts = oldVersion.split(separator: ".")
        let major = Int(versionParts.count > 0 ? versionParts[0] : "0") ?? 0
        let minor = Int(versionParts.count > 1 ? versionParts[1] : "0") ?? 0
        
        // 從1.0版本遷移到更高版本
        if major == 1 && minor == 0 {
            migrateFromVersion1_0()
        }
        
        // 從1.1版本遷移到更高版本
        if major == 1 && minor == 1 {
            migrateFromVersion1_1()
        }
        
        // 從2.0之前遷移到2.0或更高版本
        if major < 2 {
            migrateToVersion2_0()
        }
        
        // 清理舊版本不再使用的數據
        cleanupDeprecatedData()
    }
    
    /// 從1.0版本遷移數據
    private func migrateFromVersion1_0() {
        print("執行從1.0版本的數據遷移...")
        
        // 遷移UserDefaults鍵（如果舊版使用了不同的鍵名）
        migrateUserDefaultsKey(from: "oldHeartRateThreshold", to: "optimizedHRThreshold")
        migrateUserDefaultsKey(from: "oldSleepSessions", to: "sleepSessions")
        
        print("完成從1.0版本的數據遷移")
    }
    
    /// 從1.1版本遷移數據
    private func migrateFromVersion1_1() {
        print("執行從1.1版本的數據遷移...")
        
        // 此處添加從1.1版本遷移的特定操作
        
        print("完成從1.1版本的數據遷移")
    }
    
    /// 遷移到2.0版本
    private func migrateToVersion2_0() {
        print("執行到2.0版本的數據遷移...")
        
        // 此處添加遷移到2.0版本的特定操作
        
        print("完成到2.0版本的數據遷移")
    }
    
    /// 遷移UserDefaults鍵值
    private func migrateUserDefaultsKey(from oldKey: String, to newKey: String) {
        let defaults = UserDefaults.standard
        
        // 檢查舊鍵是否存在
        if defaults.object(forKey: oldKey) != nil {
            // 獲取舊數據
            let oldData = defaults.object(forKey: oldKey)
            
            // 保存到新鍵
            defaults.set(oldData, forKey: newKey)
            
            // 移除舊鍵（可選）
            defaults.removeObject(forKey: oldKey)
            
            print("已遷移UserDefaults鍵: \(oldKey) -> \(newKey)")
        }
    }
    
    /// 清理不再使用的數據
    private func cleanupDeprecatedData() {
        print("清理過時數據...")
        
        // 需要清理的過時鍵列表
        let deprecatedKeys = [
            "deprecatedKey1",
            "deprecatedKey2",
            "oldSetting",
            "unusedFeatureFlag"
        ]
        
        // 移除這些鍵
        let defaults = UserDefaults.standard
        for key in deprecatedKeys {
            if defaults.object(forKey: key) != nil {
                defaults.removeObject(forKey: key)
                print("已移除過時的UserDefaults鍵: \(key)")
            }
        }
    }
    
    /// 檢查是否需要顯示版本更新通知
    func shouldShowUpdateNotice() -> Bool {
        return isFirstLaunchAfterUpdate
    }
    
    /// 獲取可顯示的版本字符串
    func getDisplayVersion() -> String {
        return "\(currentVersion) (\(currentBuild))"
    }
} 