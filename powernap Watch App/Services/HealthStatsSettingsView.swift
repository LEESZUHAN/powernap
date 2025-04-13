import SwiftUI

/// 健康數據設置視圖，顯示個人化心率模型的相關數據
struct HealthStatsSettingsView: View {
    @ObservedObject var viewModel: PowerNapViewModel
    @State private var selectedAdjustment: Int = 0 // 0%, 5%, 10%, 15%
    private let adjustmentOptions = [0, 5, 10, 15]
    
    var body: some View {
        List {
            // 心率閾值設置
            Section(header: Text("心率閾值設置")) {
                HStack {
                    Text("心率閾值")
                    Spacer()
                    Text("\(String(format: "%.1f", viewModel.optimizedHRThresholdPercentage * 100))%")
                        .foregroundColor(.gray)
                }
                
                if viewModel.restingHeartRate > 0 {
                    HStack {
                        Text("實際閾值")
                        Spacer()
                        Text("\(Int(viewModel.optimizedHRThreshold)) bpm")
                            .foregroundColor(.gray)
                    }
                    
                    HStack {
                        Text("靜息心率")
                        Spacer()
                        Text("\(Int(viewModel.restingHeartRate)) bpm")
                            .foregroundColor(.gray)
                    }
                }
                
                // 重置個人化模型（僅在測試時使用）
                #if DEBUG
                Button(action: {
                    viewModel.resetPersonalizedModel()
                }) {
                    Text("重置個人化模型")
                        .foregroundColor(.red)
                }
                #endif
            }
            
            // 放寬入睡判定 (新增)
            Section(header: Text("入睡判定調整"), footer: Text("若您發現入睡計時器沒有自動啟動，可以適當放寬判定標準。建議先使用預設值，如有需要再逐步調整。")) {
                Picker("放寬入睡判定", selection: $selectedAdjustment) {
                    ForEach(0..<adjustmentOptions.count, id: \.self) { index in
                        Text("\(adjustmentOptions[index])%").tag(index)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: selectedAdjustment) { newValue in
                    viewModel.setUserSleepAdjustment(percentage: Double(adjustmentOptions[newValue]))
                }
            }
            
            // 年齡設置，影響預設心率閾值
            Section(header: Text("年齡組設置")) {
                HStack {
                    Text("當前年齡組")
                    Spacer()
                    Text(viewModel.ageGroupService.currentAgeGroup.rawValue)
                        .foregroundColor(.gray)
                }
                
                NavigationLink(destination: AgeSelectionView(ageGroupService: viewModel.ageGroupService)) {
                    Text("更改年齡組")
                }
            }
            
            // 說明部分
            Section(header: Text("個人化模型說明"), footer: Text("PowerNap會根據您的睡眠數據逐步優化心率閾值，提高睡眠檢測的準確性。該過程需要多次使用後才能獲得最佳效果。")) {
                HStack {
                    Text("優化類型")
                    Spacer()
                    Text("自動")
                        .foregroundColor(.gray)
                }
                
                HStack {
                    Text("下次更新")
                    Spacer()
                    // 這裡可以顯示下次更新時間，如果有的話
                    Text("使用後7天")
                        .foregroundColor(.gray)
                }
            }
        }
        .navigationTitle("睡眠檢測設置")
        .onAppear {
            // 載入當前調整值
            let currentAdjustment = viewModel.getUserSleepAdjustment()
            selectedAdjustment = adjustmentOptions.firstIndex(of: Int(currentAdjustment)) ?? 0
        }
    }
}

#if DEBUG
struct HealthStatsSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            HealthStatsSettingsView(viewModel: PowerNapViewModel())
        }
    }
}
#endif 