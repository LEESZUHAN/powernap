import Foundation
import HealthKit
import SwiftUI
import ObjectiveC

/// 負責應用程序的權限管理
@MainActor
class PermissionManager: ObservableObject {
    /// 健康權限的當前狀態
    @Published var healthPermissionStatus: PermissionStatus = .unknown
    
    /// 上次提醒用戶授予權限的日期
    @AppStorage("lastPermissionReminderDate") private var lastPermissionReminderDate: Double = 0
    
    /// 用戶是否已完成引導流程
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    
    /// 用戶是否已授予健康權限（用戶報告的狀態，可能與實際狀態不符）
    @AppStorage("hasGrantedHealthPermissions") private var hasGrantedHealthPermissions: Bool = false
    
    /// 健康商店實例
    private let healthStore = HKHealthStore()
    
    /// 需要讀取的健康數據類型
    private let typesToRead: Set<HKObjectType> = [
        HKQuantityType.quantityType(forIdentifier: .heartRate)!,
        HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
    ]
    
    /// 需要寫入的健康數據類型（目前為空）
    private let typesToWrite: Set<HKSampleType> = []
    
    /// 權限狀態枚舉
    enum PermissionStatus: String {
        case unknown = "未知"
        case granted = "已授權"
        case denied = "已拒絕"
        case restricted = "受限制"
        case notDetermined = "未決定"
    }
    
    /// 初始化
    init() {
        Task {
            await checkHealthPermissions()
        }
    }
    
    /// 檢查健康權限
    func checkHealthPermissions() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthPermissionStatus = .restricted
            return
        }
        
        // 檢查心率訪問權限（作為主要指標）
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let status = healthStore.authorizationStatus(for: heartRateType)
        
        switch status {
        case .sharingAuthorized:
            healthPermissionStatus = .granted
            hasGrantedHealthPermissions = true
        case .sharingDenied:
            healthPermissionStatus = .denied
            hasGrantedHealthPermissions = false
        case .notDetermined:
            healthPermissionStatus = .notDetermined
            hasGrantedHealthPermissions = false
        @unknown default:
            healthPermissionStatus = .unknown
            hasGrantedHealthPermissions = false
        }
    }
    
    /// 請求健康權限
    func requestHealthPermissions() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthPermissionStatus = .restricted
            return false
        }
        
        do {
            // 請求授權返回Void，不是Bool，所以我們需要自己判斷結果
            try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)
            
            // 請求後檢查狀態
            await checkHealthPermissions()
            
            // 根據檢查結果判斷是否成功
            let isGranted = healthPermissionStatus == .granted
            hasGrantedHealthPermissions = isGranted
            
            // 更新提醒日期
            lastPermissionReminderDate = Date().timeIntervalSince1970
            
            return isGranted
        } catch {
            print("健康授權請求錯誤: \(error.localizedDescription)")
            healthPermissionStatus = .denied
            hasGrantedHealthPermissions = false
            return false
        }
    }
    
    /// 完成引導流程
    func completeOnboarding() {
        hasCompletedOnboarding = true
    }
    
    /// 打開健康設置
    func openHealthSettings() {
        guard let settingsURL = URL(string: "x-apple-health://") else { return }
        
        #if os(watchOS)
        // 使用反射間接調用WKExtension，避免直接導入WatchKit
        if let extensionClass = NSClassFromString("WKExtension"),
           let openURLMethod = class_getInstanceMethod(extensionClass, #selector(WKExtension.openSystemURL(_:))) { // 獲取實例方法

            let sharedSelector = #selector(WKExtension.shared) // 獲取類方法的 Selector
            // 調用輔助方法，傳遞 Selector
            if let objcSharedExtension = method_invoke_ret(extensionClass, sharedSelector)?.takeUnretainedValue() as? NSObject {
                
                typealias OpenURLImp = @convention(c) (AnyObject, Selector, URL) -> Void
                let openURLSel = #selector(WKExtension.openSystemURL(_:))
                
                // 獲取 openSystemURL 的實現
                if let openURLImpPointer = class_getMethodImplementation(extensionClass, openURLSel) { // 修正：應該從實例獲取IMP，但反射較複雜，先嘗試直接從類獲取
                    let openURLFunction = unsafeBitCast(openURLImpPointer, to: OpenURLImp.self)
                    // 在獲取的共享實例上調用方法
                    openURLFunction(objcSharedExtension, openURLSel, settingsURL)
                } else {
                     // 嘗試從實例獲取方法實現（更標準的方式）
                    if let instanceMethodImp = class_getMethodImplementation(type(of: objcSharedExtension), openURLSel) {
                        let openURLFunction = unsafeBitCast(instanceMethodImp, to: OpenURLImp.self)
                        openURLFunction(objcSharedExtension, openURLSel, settingsURL)
                    } else {
                        print("無法獲取 openSystemURL 方法的實現")
                    }
                }
            } else {
                print("無法獲取 WKExtension 的共享實例")
            }
        } else {
            print("無法獲取 WKExtension 類或 openSystemURL 方法")
        }
        #else
        // 非WatchOS環境下的處理
        print("嘗試打開健康設置URL: \(settingsURL)")
        #endif
    }
    
    /// 檢查是否應該顯示權限提醒（避免過於頻繁打擾用戶）
    func shouldShowPermissionReminder() -> Bool {
        // 如果已授權或未完成引導，不顯示提醒
        if healthPermissionStatus == .granted || !hasCompletedOnboarding {
            return false
        }
        
        // 如果從未提醒過或上次提醒已超過24小時
        let lastReminderDate = Date(timeIntervalSince1970: lastPermissionReminderDate)
        let daysSinceLastReminder = Calendar.current.dateComponents([.day], from: lastReminderDate, to: Date()).day ?? 0
        
        return daysSinceLastReminder >= 1
    }
    
    /// 標記用戶已經被提醒
    func markUserReminded() {
        lastPermissionReminderDate = Date().timeIntervalSince1970
    }

    // 輔助方法，用於安全調用類方法並獲取返回值
    private func method_invoke_ret(_ target: AnyClass, _ selector: Selector) -> Unmanaged<AnyObject>? {
        guard let method = class_getClassMethod(target, selector) else {
            print("無法獲取類方法: \(selector)")
            return nil
        }
        let implementation = method_getImplementation(method)
        typealias Function = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>?
        let function = unsafeBitCast(implementation, to: Function.self)
        return function(target, selector)
    }
} 