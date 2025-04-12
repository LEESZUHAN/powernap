import Foundation
import SwiftUI
import WatchKit
import os

/// 測試報告生成和共享服務
class TestReportService: ObservableObject {
    /// 報告生成狀態
    @Published var isGeneratingReport = false
    @Published var lastReportStatus: ReportStatus = .none
    
    /// 報告狀態枚舉
    enum ReportStatus {
        case none
        case generating
        case ready
        case failed(String)
    }
    
    /// 初始化
    init() {
        // 設定記錄器
        print("測試報告服務初始化")
    }
    
    /// 生成並共享測試報告
    func generateAndShareReport() {
        isGeneratingReport = true
        lastReportStatus = .generating
        
        // 生成報告
        let report = generateTestReport()
        
        // 儲存報告到臨時文件
        let fileName = "PowerNapReport-\(Date().timeIntervalSince1970).txt"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try report.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // 生成成功
            lastReportStatus = .ready
            
            // 使用系統共享表單共享文件
            presentActivityController(with: fileURL)
            
        } catch {
            print("報告生成錯誤: \(error.localizedDescription)")
            lastReportStatus = .failed("文件創建失敗: \(error.localizedDescription)")
            isGeneratingReport = false
        }
    }
    
    /// 顯示系統共享表單
    private func presentActivityController(with fileURL: URL) {
        DispatchQueue.main.async {
            // 獲取當前控制器
            guard let rootController = WKExtension.shared().rootInterfaceController else {
                self.lastReportStatus = .failed("無法獲取界面控制器")
                self.isGeneratingReport = false
                return
            }
            
            // 創建活動項目
            let items: [Any] = [fileURL]
            
            // 顯示系統共享表單
            rootController.presentActivityController(
                with: items,
                completionHandler: { activityType, completed, items, error in
                    
                    DispatchQueue.main.async {
                        self.isGeneratingReport = false
                        
                        if let error = error {
                            self.lastReportStatus = .failed("共享錯誤: \(error.localizedDescription)")
                            return
                        }
                        
                        if completed {
                            if let activityType = activityType {
                                print("報告已共享到: \(activityType)")
                            }
                            self.lastReportStatus = .ready
                        } else {
                            print("用戶取消了共享")
                            // 保持為ready狀態因為報告已生成
                        }
                    }
                }
            )
        }
    }
    
    /// 生成測試報告內容
    private func generateTestReport() -> String {
        // 創建報告標題
        var report = "PowerNap測試報告\n"
        report += "生成時間: \(formatDate(Date()))\n"
        report += "-------------\n\n"
        
        // 設備信息
        report += "設備信息:\n"
        report += "WatchOS版本: \(deviceOSVersion())\n"
        report += "設備型號: \(deviceModel())\n"
        report += "-------------\n\n"
        
        // 應用狀態
        report += "應用狀態:\n"
        report += generateAppStateReport()
        report += "-------------\n\n"
        
        // 系統日誌（如果可用）
        report += "系統日誌:\n"
        report += getSystemLogs()
        report += "-------------\n\n"
        
        return report
    }
    
    /// 獲取系統日誌
    private func getSystemLogs() -> String {
        // 由於獲取系統完整日誌較複雜，這裡提供一個簡化版本
        return "系統日誌獲取功能僅在開發版本可用。\n詳細日誌請參考Xcode控制台輸出。"
    }
    
    /// 生成應用狀態報告
    private func generateAppStateReport() -> String {
        var state = ""
        
        // 應用版本信息
        state += "應用版本: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知")\n"
        state += "構建號: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知")\n"
        state += "Bundle ID: \(Bundle.main.bundleIdentifier ?? "未知")\n\n"
        
        // 記憶體信息
        let memoryInfo = reportMemoryInfo()
        state += "記憶體使用: \(memoryInfo)\n"
        
        // 設備狀態
        state += "電池電量: \(getBatteryLevel())%\n"
        state += "設備方向: \(getDeviceOrientation())\n"
        
        return state
    }
    
    /// 獲取記憶體信息
    private func reportMemoryInfo() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMB = Float(info.resident_size) / 1048576.0
            return String(format: "%.2f MB", usedMB)
        }
        return "無法獲取"
    }
    
    /// 獲取設備電池電量
    private func getBatteryLevel() -> Int {
        return WKInterfaceDevice.current().batteryLevel * 100
    }
    
    /// 獲取設備方向
    private func getDeviceOrientation() -> String {
        switch WKInterfaceDevice.current().orientation {
        case .left:
            return "左"
        case .right:
            return "右"
        case .down:
            return "下"
        case .up:
            return "上"
        default:
            return "未知"
        }
    }
    
    /// 獲取設備OS版本
    private func deviceOSVersion() -> String {
        return ProcessInfo.processInfo.operatingSystemVersionString
    }
    
    /// 獲取設備型號
    private func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                ptr in String(validatingUTF8: ptr)
            }
        }
        return modelCode ?? "未知"
    }
    
    /// 格式化日期
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
} 