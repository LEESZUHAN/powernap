import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: PowerNapViewModel
    @State private var showAgeSelector = false
    
    var body: some View {
        List {
            Section(header: Text("睡眠設定")) {
                // 其他設定...
                
                // 添加個人化心率模型入口
                NavigationLink(destination: HealthStatsSettingsView(viewModel: viewModel)) {
                    HStack {
                        Image(systemName: "heart.text.square.fill")
                            .foregroundColor(.red)
                        
                        Text("睡眠檢測設置")
                        
                        Spacer()
                        
                        Text("\(String(format: "%.1f", viewModel.optimizedHRThresholdPercentage * 100))%")
                            .foregroundColor(.gray)
                    }
                }
            }
            
            Section(header: Text("個人設定")) {
                // 年齡設定（將被轉移到心率設置中）
                Button(action: { showAgeSelector = true }) {
                    HStack {
                        Image(systemName: "person.crop.circle")
                            .foregroundColor(.blue)
                        
                        Text("年齡組")
                        
                        Spacer()
                        
                        Text(viewModel.ageGroupService.currentAgeGroup.rawValue)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            Section(header: Text("關於")) {
                // 關於信息...
                
                // 測試報告入口
                NavigationLink(destination: TestReportView()) {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.blue)
                        
                        Text("測試報告")
                        
                        Spacer()
                        
                        Text("傳送到iPhone")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("設定")
        .sheet(isPresented: $showAgeSelector) {
            AgeSelectionView(ageGroupService: viewModel.ageGroupService)
        }
    }
} 