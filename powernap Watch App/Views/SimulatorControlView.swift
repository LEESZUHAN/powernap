import SwiftUI

/// 模擬器控制視圖 - 僅在模擬器環境中顯示並使用
#if targetEnvironment(simulator)
struct SimulatorControlView: View {
    @ObservedObject var healthService: HealthKitService
    
    var body: some View {
        VStack(spacing: 16) {
            Text("模擬器測試控制")
                .font(.headline)
                .padding(.top)
            
            Divider()
            
            // 心率設置
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("當前心率:")
                    Text("\(Int(healthService.simulatedHeartRate)) bpm")
                        .fontWeight(.bold)
                }
                
                Slider(
                    value: Binding(
                        get: { self.healthService.simulatedHeartRate },
                        set: { self.healthService.setSimulatedHeartRate($0) }
                    ),
                    in: 40...120,
                    step: 1
                ) {
                    Text("模擬心率")
                }
            }
            .padding(.horizontal)
            
            // 靜息心率設置
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("靜息心率:")
                    Text("\(Int(healthService.simulatedRestingHeartRate)) bpm")
                        .fontWeight(.bold)
                }
                
                Slider(
                    value: Binding(
                        get: { self.healthService.simulatedRestingHeartRate },
                        set: { self.healthService.setSimulatedRestingHeartRate($0) }
                    ),
                    in: 40...100,
                    step: 1
                ) {
                    Text("模擬靜息心率")
                }
            }
            .padding(.horizontal)
            
            // 睡眠狀態切換
            Toggle(
                "模擬睡眠狀態",
                isOn: Binding(
                    get: { self.healthService.simulatedSleepState },
                    set: { self.healthService.setSimulatedSleepState($0) }
                )
            )
            .padding(.horizontal)
            
            // 睡眠狀態說明
            if healthService.simulatedSleepState {
                Text("睡眠狀態下，心率將逐漸降低至靜息心率的85-90%")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }
            
            // 睡眠檢測說明
            HStack {
                Text("睡眠檢測閾值:")
                Text("\(Int(healthService.restingHeartRate * 0.9)) bpm")
                    .fontWeight(.bold)
            }
            .padding(.top, 8)
            
            // 當前心率狀態
            HStack {
                Text("當前是否低於閾值:")
                Text(healthService.isHeartRateBelowThreshold() ? "是" : "否")
                    .fontWeight(.bold)
                    .foregroundColor(healthService.isHeartRateBelowThreshold() ? .green : .red)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.black.opacity(0.1))
        .cornerRadius(16)
    }
}
#endif 