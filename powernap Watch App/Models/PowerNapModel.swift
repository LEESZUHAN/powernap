import Foundation

/// PowerNap數據模型，定義應用的主要數據結構
struct PowerNapSession: Identifiable, Codable {
    var id = UUID()
    var startTime: Date
    var sleepDetectedTime: Date?
    var endTime: Date?
    var duration: Int  // 選擇的分鐘數
    var actualDuration: TimeInterval? {
        if let endTime = endTime, let sleepDetectedTime = sleepDetectedTime {
            return endTime.timeIntervalSince(sleepDetectedTime)
        }
        return nil
    }
    var status: NapStatus
    var hrvBaseline: Double? // 用戶的HRV基準值
    var hrvDuringNap: [HRVReading]? // 小睡期間的HRV讀數
    
    init(duration: Int) {
        self.startTime = Date()
        self.duration = duration
        self.status = .monitoring
        self.hrvDuringNap = []
    }
}

/// HRV讀數模型
struct HRVReading: Codable {
    var timestamp: Date
    var value: Double  // SDNN值，單位毫秒
}

/// 小睡的狀態枚舉
enum NapStatus: String, Codable {
    case monitoring = "監測中"   // 等待入睡
    case sleeping = "睡眠中"     // 已偵測到睡眠
    case completed = "已完成"    // 小睡已完成
    case canceled = "已取消"     // 使用者取消
}

/// 小睡倒數時間選項
enum NapDuration: Int, CaseIterable, Identifiable {
    case fiveMin = 5
    case tenMin = 10
    case fifteenMin = 15
    case twentyMin = 20
    case twentyFiveMin = 25
    case thirtyMin = 30
    
    var id: Int { self.rawValue }
    
    var description: String {
        return "\(self.rawValue) 分鐘"
    }
} 