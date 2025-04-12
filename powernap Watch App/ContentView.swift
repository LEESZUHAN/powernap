//
//  ContentView.swift
//  powernap Watch App
//
//  Created by michaellee on 3/17/25.
//  版本2 - 添加版本標記
//

import SwiftUI
import Combine
import Foundation

// 使用 ViewModels 目錄中的 PowerNapViewModel

struct ContentView: View {
    @StateObject private var viewModel = PowerNapViewModel()
    @EnvironmentObject private var permissionManager: PermissionManager
    @State private var showPermissionReminder = false
    
    var body: some View {
        TabView {
            PowerNapView(viewModel: viewModel)
                .tabItem {
                    Label("電源休息", systemImage: "bed.double.fill")
                }
            
            StatsView(viewModel: viewModel)
                .tabItem {
                    Label("狀態", systemImage: "heart.text.square.fill")
                }
            
            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label("設置", systemImage: "gear")
                }
        }
        .onAppear {
            // 檢查權限狀態
            Task {
                await permissionManager.checkHealthPermissions()
                if permissionManager.shouldShowPermissionReminder() {
                    showPermissionReminder = true
                }
            }
        }
        // 顯示歡迎引導視圖
        .fullScreenCover(isPresented: .init(
            get: { !permissionManager.hasCompletedOnboarding },
            set: { _ in }
        )) {
            WelcomeView(
                permissionManager: permissionManager,
                onComplete: {
                    permissionManager.completeOnboarding()
                }
            )
        }
        // 顯示權限提醒彈窗
        .sheet(isPresented: $showPermissionReminder) {
            PermissionReminderView(
                permissionManager: permissionManager,
                isPresented: $showPermissionReminder
            )
        }
    }
}

struct NapView: View {
    @ObservedObject var viewModel: PowerNapViewModel
    
    var body: some View {
        VStack {
            // 顯示計時器
            ZStack {
                Circle()
                    .stroke(lineWidth: 8)
                    .opacity(0.3)
                    .foregroundColor(.gray)
                
                Circle()
                    .trim(from: 0.0, to: CGFloat(min(viewModel.progress, 1.0)))
                    .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .foregroundColor(viewModel.sleepDetected ? .green : .blue)
                    .rotationEffect(Angle(degrees: 270.0))
                    .animation(.linear, value: viewModel.progress)
                
                VStack {
                    Text(viewModel.formattedTimeRemaining())
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    
                    Text(viewModel.monitoringStatus)
                        .font(.system(size: 16))
                        .foregroundColor(viewModel.sleepDetected ? .green : .gray)
                }
            }
            .padding()
            
            // 睡眠狀態指示器（如果啟用睡眠檢測）
            if viewModel.isSleepDetectionEnabled && viewModel.isSessionActive {
                VStack(spacing: 6) {
                    StatusRow(label: "心率", value: viewModel.getHeartRateDescription(), icon: "waveform.path.ecg")
                    StatusRow(label: "動作", value: viewModel.getMotionDescription(), icon: "figure.walk")
                    StatusRow(label: "檢測", value: viewModel.getSleepDetectionStatus(), icon: "zzz")
                }
                .padding()
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            // 控制按鈕
            if !viewModel.isSessionActive {
                // 開始按鈕
                Button(action: {
                    viewModel.startNap()
                }) {
                    Text("開始休息")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
                
                // 時間選擇器
                ScrollView(.horizontal, showsIndicators: false) {
                    ScrollViewReader { proxy in
                        HStack(spacing: 8) {
                            ForEach(viewModel.availableDurations, id: \.self) { duration in
                                Button(action: {
                                    viewModel.setDuration(duration)
                                    withAnimation {
                                        proxy.scrollTo(duration, anchor: .center)
                                    }
                                }) {
                                    Text("\(duration)分鐘")
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 16)
                                        .background(
                                            viewModel.selectedDuration == duration ?
                                            Color.blue : Color.secondary.opacity(0.2)
                                        )
                                        .foregroundColor(
                                            viewModel.selectedDuration == duration ?
                                            Color.white : Color.primary
                                        )
                                        .cornerRadius(8)
                                }
                                .id(duration)
                            }
                        }
                        .padding(.horizontal)
                        .onAppear {
                            proxy.scrollTo(viewModel.selectedDuration, anchor: .center)
                        }
                    }
                }
            } else {
                // 控制按鈕
                HStack(spacing: 16) {
                    if viewModel.isPaused {
                        // 繼續按鈕
                        Button(action: {
                            viewModel.resumeNap()
                        }) {
                            Image(systemName: "play.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Circle().fill(Color.green))
                        }
                    } else {
                        // 暫停按鈕
                        Button(action: {
                            viewModel.pauseNap()
                        }) {
                            Image(systemName: "pause.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Circle().fill(Color.orange))
                        }
                    }
                    
                    // 停止按鈕
                    Button(action: {
                        viewModel.stopNap()
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Circle().fill(Color.red))
                    }
                }
                .padding()
            }
        }
    }
}

struct StatsView: View {
    @ObservedObject var viewModel: PowerNapViewModel
    
    var body: some View {
        ScrollView {
            ScrollViewReader { proxy in
                VStack(spacing: 16) {
                    // 心率數據
                    VStack(alignment: .leading, spacing: 8) {
                        Text("心率數據")
                            .font(.headline)
                            .id("hr_section")
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("靜息心率")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Text("\(Int(viewModel.restingHeartRate)) bpm")
                                    .font(.title3)
                                    .fontWeight(.medium)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Text("當前心率")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Text("\(Int(viewModel.heartRate)) bpm")
                                    .font(.title3)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(12)
                    
                    // 動作數據
                    VStack(alignment: .leading, spacing: 8) {
                        Text("動作水平")
                            .font(.headline)
                            .id("motion_section")
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("動作水平")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Text(String(format: "%.3f", viewModel.motionLevel))
                                    .font(.title3)
                                    .fontWeight(.medium)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Text("狀態")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Text(viewModel.isStill ? "靜止" : "移動")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(viewModel.isStill ? .green : .orange)
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(12)
                    
                    // 睡眠狀態
                    VStack(alignment: .leading, spacing: 8) {
                        Text("睡眠狀態")
                            .font(.headline)
                            .id("sleep_section")
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("當前狀態")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Text(viewModel.sleepState.rawValue)
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(sleepStateColor(viewModel.sleepState))
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Text("睡眠檢測")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Text(viewModel.sleepDetected ? "已檢測" : "未檢測")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(viewModel.sleepDetected ? .green : .gray)
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(12)
                }
                .padding()
            }
        }
    }
    
    // 根據睡眠狀態返回相應顏色
    private func sleepStateColor(_ state: SleepState) -> Color {
        switch state {
        case .awake:
            return .gray
        case .potentialSleep:
            return .orange
        case .asleep:
            return .green
        case .disturbed:
            return .red
        }
    }
}

// 輔助視圖
struct StatusRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24, height: 24)
                .foregroundColor(.blue)
            
            Text(label)
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    ContentView()
}
