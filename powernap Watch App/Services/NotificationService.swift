import Foundation
import UserNotifications
import WatchKit

/// 通知服務類，負責管理應用程序的本地通知
class NotificationService: ObservableObject {
    /// 初始化並請求通知權限
    func initialize() {
        requestAuthorization()
    }
    
    /// 請求通知權限
    private func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("通知權限獲取成功")
            } else if let error = error {
                print("通知權限請求錯誤: \(error.localizedDescription)")
            } else {
                print("通知權限被拒絕")
            }
        }
    }
    
    /// 直接喚醒用戶 - 立即發送強化通知和震動
    /// - Parameters:
    ///   - vibrationStrength: 震動強度 (0-輕微, 1-中等, 2-強烈)
    ///   - withSound: 是否播放聲音
    func wakeupUser(vibrationStrength: Int = 1, withSound: Bool = true) {
        // 發送高優先級通知
        let content = UNMutableNotificationContent()
        content.title = "小睡完成"
        content.body = "是時候醒來了！您的小睡時間已結束。"
        
        // 設置為時間敏感通知，確保即使在專注模式下也能提醒
        content.interruptionLevel = .timeSensitive
        
        // 添加聲音
        if withSound {
            content.sound = UNNotificationSound.default
        }
        
        // 立即發送通知
        let request = UNNotificationRequest(identifier: "wakeup-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("發送喚醒通知失敗: \(error.localizedDescription)")
            }
        }
        
        // 播放多次震動
        DispatchQueue.global(qos: .userInteractive).async {
            // 根據強度選擇震動模式
            let hapticType: WKHapticType
            switch vibrationStrength {
            case 0:
                hapticType = .notification
            case 2:
                hapticType = .success
            default:
                hapticType = .notification
            }
            
            // 多次播放震動，確保用戶被喚醒
            for _ in 0..<(vibrationStrength + 2) {
                WKInterfaceDevice.current().play(hapticType)
                Thread.sleep(forTimeInterval: 0.3)
            }
            
            // 對於最強震動，添加額外的震動模式
            if vibrationStrength == 2 {
                // 短暫延遲後再次震動
                Thread.sleep(forTimeInterval: 0.5)
                
                for _ in 0..<3 {
                    WKInterfaceDevice.current().play(.retry)
                    Thread.sleep(forTimeInterval: 0.2)
                }
            }
        }
    }
    
    /// 安排即將結束的通知
    /// - Parameter timeInterval: 多少秒後顯示通知
    func scheduleEndingSoonNotification(timeInterval: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "休息即將結束"
        content.body = "您的休息時間將在1分鐘內結束。"
        content.sound = UNNotificationSound.default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(identifier: "endingSoon", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("安排通知時出錯: \(error.localizedDescription)")
            }
        }
    }
    
    /// 安排休息完成通知
    /// - Parameter timeInterval: 多少秒後顯示通知
    func scheduleCompletionNotification(timeInterval: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "休息結束"
        content.body = "您的休息時間已完成，感覺如何？"
        content.sound = UNNotificationSound.default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(identifier: "completed", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("安排通知時出錯: \(error.localizedDescription)")
            }
        }
    }
    
    /// 安排休息中斷通知
    func scheduleInterruptionNotification() {
        let content = UNMutableNotificationContent()
        content.title = "動作檢測"
        content.body = "檢測到動作，您的休息可能受到影響。"
        content.sound = UNNotificationSound.default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "interrupted", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("安排通知時出錯: \(error.localizedDescription)")
            }
        }
    }
    
    /// 取消所有待處理的通知
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    /// 取消特定類型的通知
    /// - Parameter identifier: 通知標識符
    func cancelNotification(withIdentifier identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
} 