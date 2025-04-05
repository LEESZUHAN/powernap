import SwiftUI

struct HRVDisplayView: View {
    var hrvValue: Double?
    var baselineHRV: Double?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("心率變異性")
                .font(.caption)
                .foregroundColor(.gray)
            
            if let hrv = hrvValue {
                Text(String(format: "%.1f", hrv))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(hrvColor)
                
                if let baseline = baselineHRV {
                    HStack(spacing: 2) {
                        Image(systemName: hrvValue ?? 0 >= baseline ? "arrow.up" : "arrow.down")
                        Text("\(hrvDifference)%")
                            .foregroundColor(hrvColor)
                        Text("基準線")
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
    
    // 計算與基準線的差異百分比
    private var hrvDifference: String {
        guard let hrv = hrvValue, let baseline = baselineHRV, baseline > 0 else {
            return "0"
        }
        
        let diff = ((hrv - baseline) / baseline) * 100
        return String(format: "%.0f", abs(diff))
    }
    
    // 根據 HRV 相對於基準線的情況決定顏色
    private var hrvColor: Color {
        guard let hrv = hrvValue, let baseline = baselineHRV else {
            return .gray
        }
        
        if hrv >= baseline * 1.1 {
            return .green // 顯著高於基準線
        } else if hrv <= baseline * 0.9 {
            return .orange // 顯著低於基準線
        } else {
            return .blue // 接近基準線
        }
    }
} 