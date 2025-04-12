import SwiftUI

struct HeartRateDisplayView: View {
    var heartRate: Double?
    var restingHeartRate: Double?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("心率")
                .font(.caption)
                .foregroundColor(.gray)
            
            if let hr = heartRate {
                Text(String(format: "%.0f", hr))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(heartRateColor)
                
                if let rhr = restingHeartRate {
                    HStack(spacing: 2) {
                        Image(systemName: heartRate ?? 0 <= rhr ? "arrow.down" : "arrow.up")
                        Text("\(heartRateDifference)%")
                            .foregroundColor(heartRateColor)
                        Text("靜息心率")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .font(.caption)
                }
            } else {
                Text("--")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.gray)
                Text("尚未獲取")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.black.opacity(0.2))
        .cornerRadius(10)
    }
    
    // 計算與靜息心率的差異百分比
    private var heartRateDifference: String {
        guard let hr = heartRate, let rhr = restingHeartRate, rhr > 0 else {
            return "0"
        }
        
        let diff = ((hr - rhr) / rhr) * 100
        return String(format: "%.0f", abs(diff))
    }
    
    // 根據心率相對於靜息心率的情況決定顏色
    private var heartRateColor: Color {
        guard let hr = heartRate, let rhr = restingHeartRate else {
            return .gray
        }
        
        if hr <= rhr * 0.9 {
            return .green // 顯著低於靜息心率（可能在睡眠中）
        } else if hr >= rhr * 1.1 {
            return .orange // 顯著高於靜息心率（可能活躍或緊張）
        } else {
            return .blue // 接近靜息心率
        }
    }
} 