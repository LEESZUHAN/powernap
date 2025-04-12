import SwiftUI

/// 測試報告界面
struct TestReportView: View {
    @StateObject private var reportService = TestReportService()
    @Environment(\.presentationMode) private var presentationMode
    @State private var showHelp = false
    
    var body: some View {
        List {
            Section(header: Text("報告功能")) {
                // 報告狀態
                HStack {
                    Text("報告狀態")
                    Spacer()
                    statusText
                }
                
                // 生成並共享報告按鈕
                Button(action: generateAndShareReport) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.blue)
                        Text("生成並共享報告")
                    }
                }
                .disabled(reportService.isGeneratingReport)
                
                // 幫助按鈕
                Button(action: { showHelp = true }) {
                    HStack {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.green)
                        Text("使用説明")
                    }
                }
            }
            
            Section(header: Text("注意事項"), footer: Text("您可以通過系統共享表單將報告發送到任何支援的應用，例如郵件、訊息或備忘錄等。")) {
                // 使用提示信息
                Text("報告包含應用狀態和設備信息，用於診斷問題")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("測試報告")
        .alert(isPresented: $showHelp) {
            Alert(
                title: Text("使用說明"),
                message: Text("此功能用於生成診斷報告。\n\n1. 點擊「生成並共享報告」按鈕\n2. 系統會顯示共享選項\n3. 選擇您想要的分享方式（郵件、訊息等）\n4. 輸入收件人並發送"),
                dismissButton: .default(Text("了解"))
            )
        }
    }
    
    // 根據狀態顯示不同的文本
    private var statusText: some View {
        Group {
            switch reportService.lastReportStatus {
            case .none:
                Text("等待生成")
                    .foregroundColor(.secondary)
            case .generating:
                HStack {
                    Text("生成中...")
                        .foregroundColor(.orange)
                    ProgressView()
                        .scaleEffect(0.7)
                }
            case .ready:
                Text("準備就緒")
                    .foregroundColor(.green)
            case .failed(let error):
                VStack(alignment: .trailing) {
                    Text("生成失敗")
                        .foregroundColor(.red)
                    if !error.isEmpty {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
    
    // 生成並共享報告
    private func generateAndShareReport() {
        reportService.generateAndShareReport()
    }
}

#if DEBUG
struct TestReportView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            TestReportView()
        }
    }
}
#endif 