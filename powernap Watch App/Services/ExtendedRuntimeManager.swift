import Foundation
import SwiftUI
import WatchKit
import Combine

/// 擴展運行時會話管理器，處理背景執行相關操作
class ExtendedRuntimeManager: NSObject, ObservableObject {
    private var session: WKExtendedRuntimeSession?
    
    @Published var isSessionActive = false
    
    override init() {
        super.init()
    }
    
    /// 開始擴展運行時會話
    func startExtendedRuntimeSession() {
        // 如果已經有一個活動會話，先停止它
        if let existingSession = session, existingSession.state == .running {
            existingSession.invalidate()
        }
        
        // 創建並啟動新會話
        let newSession = WKExtendedRuntimeSession()
        newSession.delegate = self
        newSession.start()
        
        session = newSession
        print("已啟動擴展運行時會話")
    }
    
    /// 結束擴展運行時會話
    func stopExtendedRuntimeSession() {
        session?.invalidate()
        session = nil
        isSessionActive = false
        print("已停止擴展運行時會話")
    }
    
    /// 獲取當前會話狀態描述
    var sessionStateDescription: String {
        guard let session = session else {
            return "未啟動"
        }
        
        // 處理所有可能的會話狀態
        let state = session.state
        if state == .running {
            return "運行中"
        } else if state == .invalid {
            return "已失效"
        } else {
            // 處理未來可能添加的新狀態
            return "未知狀態: \(String(describing: state))"
        }
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate
extension ExtendedRuntimeManager: WKExtendedRuntimeSessionDelegate {
    /// 會話開始運行
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        DispatchQueue.main.async {
            self.isSessionActive = true
        }
        print("擴展運行時會話已開始")
    }
    
    /// 會話即將過期
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("警告：擴展運行時會話即將過期")
        
        // 重新啟動會話以延長運行時間
        DispatchQueue.main.async {
            self.startExtendedRuntimeSession()
        }
    }
    
    /// 會話已失效
    func extendedRuntimeSessionDidInvalidate(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        DispatchQueue.main.async {
            self.isSessionActive = false
        }
        print("擴展運行時會話已失效")
    }
    
    /// 會話因為特定原因無效化
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        DispatchQueue.main.async {
            self.isSessionActive = false
        }
        print("擴展運行時會話已無效化，原因: \(reason)")
        if let error = error {
            print("錯誤: \(error.localizedDescription)")
        }
    }
} 