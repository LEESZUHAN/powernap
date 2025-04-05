import Foundation
import CoreMotion

/// 動作監測服務，用於偵測使用者的靜止狀態
class MotionService: ObservableObject {
    private let motionManager = CMMotionManager()
    private var motionQueue = OperationQueue()
    private var updateTimer: Timer?
    private var motionLevels: [MotionDataPoint] = []
    
    // 觀察時間窗口尺寸
    private let windowSize = 300 // 5分鐘的數據點（假設每秒一個數據點）
    
    // 短時間窗口，用於即時檢測突然移動
    private let shortWindowSize = 20 // 20秒窗口
    
    /// 動作級別閾值 - 低於此值視為靜止
    @Published var motionThreshold: Double = 0.02
    
    /// 當前動作級別
    @Published var currentMotionLevel: Double = 0
    
    /// 是否處於靜止狀態
    @Published var isStill: Bool = false
    
    /// 靜止開始時間
    @Published var stillStartTime: Date? = nil
    
    /// 靜止持續時間（秒）
    @Published var stillDuration: TimeInterval = 0
    
    /// 是否自動調整閾值
    @Published var autoAdjustThreshold: Bool = true
    
    // 用於儲存動作數據點的結構
    private struct MotionDataPoint {
        let timestamp: Date
        let accelMagnitude: Double
        let gyroMagnitude: Double? // 可選，取決於是否使用陀螺儀
    }
    
    init() {
        motionQueue.maxConcurrentOperationCount = 1
        motionQueue.qualityOfService = .userInitiated
    }
    
    /// 開始監測動作狀態
    func startMonitoring() {
        guard motionManager.isAccelerometerAvailable else {
            print("加速度計不可用")
            return
        }
        
        // 重置狀態
        resetMotionData()
        
        // 設置加速度計
        motionManager.accelerometerUpdateInterval = 1.0
        motionManager.startAccelerometerUpdates(to: motionQueue) { [weak self] (data, error) in
            guard let self = self, let data = data else {
                if let error = error {
                    print("加速度計監測出錯: \(error.localizedDescription)")
                }
                return
            }
            
            // 處理加速度數據
            self.processAccelerometerData(data)
        }
        
        // 如果陀螺儀可用，也一併監測
        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = 1.0
            motionManager.startGyroUpdates(to: motionQueue) { [weak self] (data, error) in
                guard let _ = self, let _ = data else {
                    if let error = error {
                        print("陀螺儀監測出錯: \(error.localizedDescription)")
                    }
                    return
                }
                
                // 處理陀螺儀數據（暫不使用，保留API）
                // self.processGyroData(data)
            }
        }
        
        // 設定定期更新計時器
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // 每2秒更新一次靜止狀態判斷
            self.updateStillStatus()
            
            // 每2秒更新一次靜止持續時間
            if self.isStill, let startTime = self.stillStartTime {
                self.stillDuration = Date().timeIntervalSince(startTime)
            }
            
            // 每分鐘清理一次過多數據點，確保不會無限增長
            if self.motionLevels.count > self.windowSize {
                self.motionLevels.removeFirst(self.motionLevels.count - self.windowSize)
            }
            
            // 如果開啟自動調整閾值功能，每分鐘調整一次
            if self.autoAdjustThreshold && self.updateTimer?.timeInterval.truncatingRemainder(dividingBy: 60) == 0 {
                self.adjustMotionThreshold()
            }
        }
    }
    
    /// 處理加速度計數據
    private func processAccelerometerData(_ data: CMAccelerometerData) {
        let x = data.acceleration.x
        let y = data.acceleration.y
        let z = data.acceleration.z
        
        // 計算總加速度向量大小（扣除重力約1g）
        let totalAccel = sqrt(x*x + y*y + z*z) - 1.0
        let absAccel = abs(totalAccel)
        
        // 創建數據點並保存
        let dataPoint = MotionDataPoint(timestamp: Date(), accelMagnitude: absAccel, gyroMagnitude: nil)
        motionLevels.append(dataPoint)
        
        // 保持窗口大小
        if motionLevels.count > windowSize {
            motionLevels.removeFirst()
        }
        
        // 計算並更新當前動作級別（使用最近的短窗口數據）
        updateCurrentMotionLevel()
    }
    
    /// 更新當前動作級別
    private func updateCurrentMotionLevel() {
        // 使用短窗口來計算當前動作級別，更敏感地反映突然動作
        let recentPoints = Array(motionLevels.suffix(min(shortWindowSize, motionLevels.count)))
        let averageMotion = recentPoints.reduce(0.0) { $0 + $1.accelMagnitude } / Double(recentPoints.count)
        
        DispatchQueue.main.async {
            self.currentMotionLevel = averageMotion
        }
    }
    
    /// 更新靜止狀態判斷
    private func updateStillStatus() {
        // 使用整個窗口來判斷是否靜止，更穩定地反映整體趨勢
        let averageMotion = calculateMovingAverage()
        let newIsStill = averageMotion < motionThreshold
        
        DispatchQueue.main.async {
            // 只有當狀態發生變化時才更新時間戳
            if self.isStill != newIsStill {
                if newIsStill {
                    // 從活動到靜止：記錄開始時間
                    self.stillStartTime = Date()
                    self.stillDuration = 0
                } else {
                    // 從靜止到活動：重置時間
                    self.stillStartTime = nil
                    self.stillDuration = 0
                }
            }
            
            self.isStill = newIsStill
        }
    }
    
    /// 停止監測動作狀態
    func stopMonitoring() {
        motionManager.stopAccelerometerUpdates()
        if motionManager.isGyroActive {
            motionManager.stopGyroUpdates()
        }
        
        updateTimer?.invalidate()
        updateTimer = nil
        resetMotionData()
    }
    
    /// 計算移動平均
    private func calculateMovingAverage() -> Double {
        guard !motionLevels.isEmpty else { return 0.0 }
        
        // 計算加速度平均值
        return motionLevels.reduce(0.0) { $0 + $1.accelMagnitude } / Double(motionLevels.count)
    }
    
    /// 是否已經連續靜止指定時間段（秒）
    func hasUserBeenStillFor(seconds: Int) -> Bool {
        guard let stillStart = stillStartTime else { return false }
        let stillTime = Date().timeIntervalSince(stillStart)
        return isStill && stillTime >= Double(seconds)
    }
    
    /// 自動調整動作閾值
    private func adjustMotionThreshold() {
        guard motionLevels.count >= 60 else { return } // 至少需要1分鐘的數據
        
        // 計算過去數據的標準差
        let mean = calculateMovingAverage()
        let variance = motionLevels.reduce(0.0) { $0 + pow($1.accelMagnitude - mean, 2) } / Double(motionLevels.count)
        let stdDev = sqrt(variance)
        
        // 設置閾值為平均值加上1個標準差，但有上下限
        let newThreshold = min(max(mean + stdDev, 0.015), 0.05)
        
        DispatchQueue.main.async {
            self.motionThreshold = newThreshold
        }
    }
    
    /// 手動設置動作閾值
    func setCustomThreshold(_ threshold: Double) {
        // 確保閾值在合理範圍內
        let safeThreshold = min(max(threshold, 0.005), 0.1)
        
        DispatchQueue.main.async {
            self.motionThreshold = safeThreshold
            self.autoAdjustThreshold = false
        }
    }
    
    /// 重置動作監測數據
    func resetMotionData() {
        motionLevels.removeAll()
        
        DispatchQueue.main.async {
            self.currentMotionLevel = 0
            self.isStill = false
            self.stillStartTime = nil
            self.stillDuration = 0
        }
    }
    
    /// 獲取最近時間段內的動作數據
    func getMotionDataForLastMinutes(_ minutes: Int) -> [Double] {
        // 計算需要的數據點數量
        let pointsNeeded = min(minutes * 60, motionLevels.count)
        
        // 獲取最近的數據點
        let recentPoints = Array(motionLevels.suffix(pointsNeeded))
        
        // 返回加速度值數組
        return recentPoints.map { $0.accelMagnitude }
    }
} 