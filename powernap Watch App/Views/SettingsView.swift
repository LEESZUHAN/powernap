import SwiftUI

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @AppStorage("playAudio") private var playAudio = true
    @AppStorage("vibrationEnabled") private var vibrationEnabled = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    
    @ObservedObject var viewModel: PowerNapViewModel
    
    var body: some View {
        ScrollView {
            ScrollViewReader { proxy in
                VStack(spacing: 15) {
                    Group {
                        HStack {
                            Image(systemName: "speaker.wave.2")
                            Text("音效")
                                .id("audio_setting")
                            Spacer()
                            Toggle("", isOn: $playAudio)
                                .labelsHidden()
                        }
                        
                        Divider()
                        
                        HStack {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                            Text("震動")
                                .id("vibration_setting")
                            Spacer()
                            Toggle("", isOn: $vibrationEnabled)
                                .labelsHidden()
                        }
                        
                        Divider()
                        
                        HStack {
                            Image(systemName: "bed.double")
                            Text("自動檢測睡眠")
                                .id("sleep_detection_setting")
                            Spacer()
                            Toggle("", isOn: $viewModel.isSleepDetectionEnabled)
                                .labelsHidden()
                        }
                        
                        Divider()
                        
                        HStack {
                            Image(systemName: "bell")
                            Text("通知")
                                .id("notification_setting")
                            Spacer()
                            Toggle("", isOn: $notificationsEnabled)
                                .labelsHidden()
                        }
                        
                        Divider()
                        
                        Button(action: viewModel.sendFeedback) {
                            HStack {
                                Image(systemName: "envelope.fill")
                                Text("發送測試報告")
                                    .id("feedback_button")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("完成")
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(8)
                            .id("done_button")
                    }
                    .padding(.horizontal)
                    .buttonStyle(PlainButtonStyle())
                    
                    VStack(spacing: 2) {
                        Text("PowerNap")
                            .font(.footnote)
                            .fontWeight(.medium)
                        Text("版本 1.0.0")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical)
                    .id("version_info")
                }
            }
        }
        .navigationTitle("設置")
    }
} 