import SwiftUI

/// 年齡組選擇視圖，允許用戶手動選擇年齡組
struct AgeSelectionView: View {
    /// 年齡組服務
    @ObservedObject var ageGroupService: AgeGroupService
    
    /// 用於關閉視圖的狀態
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("選擇您的年齡組")) {
                    ForEach(AgeGroup.allCases, id: \.self) { ageGroup in
                        Button(action: {
                            ageGroupService.setAgeGroup(ageGroup)
                            dismiss()
                        }) {
                            HStack {
                                Text(ageGroup.rawValue)
                                    .foregroundColor(.primary)
                                Spacer()
                                if ageGroupService.currentAgeGroup == ageGroup {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .listRowBackground(ageGroupService.currentAgeGroup == ageGroup ? Color.blue.opacity(0.1) : nil)
                    }
                }
                
                Section(footer: Text("年齡組將影響PowerNap檢測入睡的靈敏度和所需時間。若可能，我們會自動從您的健康資料中獲取年齡。")) {
                    EmptyView()
                }
            }
            .navigationTitle("年齡設定")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#if DEBUG
struct AgeSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        AgeSelectionView(ageGroupService: AgeGroupService())
    }
}
#endif 