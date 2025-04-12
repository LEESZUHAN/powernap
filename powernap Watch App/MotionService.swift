import Foundation
import Combine
import CoreMotion
import SwiftUI

/// 動作服務，監測用戶的動作狀態
class MotionService: ObservableObject {
    // 運動管理器
    private let motionManager = CMMotionManager()
    
    // 運動閾值與緩衝設置
    private let motionThreshold: Double = 0.1
    private let stillDurationThreshold: TimeInterval = 60 // 判定為靜止的時間（秒）
    
    // 發布屬性
    @Published var isStill: Bool = false
    @Published var currentMotionLevel: Double = 0.0
    @Published var stillDuration: TimeInterval = 0
    @Published var lastMotionTime: Date = Date()
    
    // 處理運動更新
    private let motionQueue = DispatchQueue(label: "com.michaellee.powernap.motion")
    private var motionUpdateTimer: Timer?
    
    // 當天活動相關
    @Published var peakActivityLevel: Double = 0.0
    @Published var hasDailyIntenseActivity: Bool = false
    
    private let intenseActivityThreshold: Double = 2.0 // 強烈活動的閾值
    private let activityResetTime: TimeInterval = 3600 * 4 // 活動重置時間（4小時）
    private var lastIntenseActivityTime: Date? = nil
    
    /// 初始化
    init() {
        // 確保設備支持動作檢測
        guard motionManager.isDeviceMotionAvailable else {
            print("設備不支持動作檢測")
            return
        }
        
        // 配置動作管理器
        motionManager.deviceMotionUpdateInterval = 0.5 // 每秒兩次
    }
    
    /// 開始動作監測
    func startMotionUpdates() {
        // 確保未在運行
        guard !motionManager.isDeviceMotionActive else { return }
        
        // 重置當天活動數據
        resetDailyActivity()
        
        // 開始動作更新
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] (motion, error) in
            guard let self = self, let motion = motion, error == nil else {
                print("動作更新錯誤: \(error?.localizedDescription ?? "未知錯誤")")
                return
            }
            
            self.processMotion(data: motion)
        }
        
        // 定期更新靜止持續時間
        DispatchQueue.main.async {
            self.motionUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.updateStillDuration()
            }
        }
    }
    
    /// 停止動作監測
    func stopMotionUpdates() {
        // 停止動作更新
        motionManager.stopDeviceMotionUpdates()
        
        // 停止計時器
        motionUpdateTimer?.invalidate()
        motionUpdateTimer = nil
        
        // 重置狀態
        DispatchQueue.main.async {
            self.isStill = false
            self.stillDuration = 0
        }
    }
    
    /// 判斷用戶是否已靜止指定時間
    func hasUserBeenStillFor(seconds: Int) -> Bool {
        return isStill && stillDuration >= Double(seconds)
    }
    
    /// 處理動作更新
    private func processMotion(data: CMDeviceMotion) {
        // 計算總體運動水平
        let userAcceleration = data.userAcceleration
        let rotationRate = data.rotationRate
        
        let accelerationMagnitude = sqrt(
            pow(userAcceleration.x, 2) +
            pow(userAcceleration.y, 2) +
            pow(userAcceleration.z, 2)
        )
        
        let rotationMagnitude = sqrt(
            pow(rotationRate.x, 2) +
            pow(rotationRate.y, 2) +
            pow(rotationRate.z, 2)
        )
        
        // 綜合運動水平
        let combinedMotionLevel = accelerationMagnitude + rotationMagnitude * 0.5
        
        // 判斷是否靜止
        let isCurrentlyStill = combinedMotionLevel < motionThreshold
        
        // 更新動作狀態
        DispatchQueue.main.async {
            self.currentMotionLevel = combinedMotionLevel
            
            if !isCurrentlyStill {
                self.lastMotionTime = Date()
                self.isStill = false
                self.stillDuration = 0
            } else if !self.isStill {
                // 剛開始靜止
                let timeSinceLastMotion = Date().timeIntervalSince(self.lastMotionTime)
                if timeSinceLastMotion >= self.stillDurationThreshold {
                    self.isStill = true
                }
            }
            
            // 檢查和更新當天的峰值活動水平
            if combinedMotionLevel > self.peakActivityLevel {
                self.peakActivityLevel = combinedMotionLevel
            }
            
            // 檢查是否為強烈活動
            if combinedMotionLevel > self.intenseActivityThreshold {
                self.lastIntenseActivityTime = Date()
                self.hasDailyIntenseActivity = true
            } else if let lastIntense = self.lastIntenseActivityTime {
                // 如果已超過重置時間，重置活動標誌
                if Date().timeIntervalSince(lastIntense) > self.activityResetTime {
                    self.hasDailyIntenseActivity = false
                }
            }
        }
    }
    
    /// 更新靜止持續時間
    private func updateStillDuration() {
        if isStill {
            DispatchQueue.main.async {
                self.stillDuration += 1.0
            }
        }
    }
    
    /// 重置當天活動數據
    private func resetDailyActivity() {
        peakActivityLevel = 0.0
        hasDailyIntenseActivity = false
        lastIntenseActivityTime = nil
    }
} 