import SwiftUI
import HealthKit

struct WelcomeView: View {
    // 由外部提供的權限管理器
    @ObservedObject var permissionManager: PermissionManager
    
    // 當前步驟索引
    @State private var currentStep = 0
    @State private var isRequestingHealthKit = false
    
    // 完成引導時的回調
    var onComplete: () -> Void
    
    // 引導步驟內容
    let steps = [
        WelcomeStep(
            title: "歡迎使用PowerNap",
            description: "讓您的休息更有效率。科學小睡助您快速恢復精力，提高工作和學習效率。",
            imageName: "sparkles",
            bgGradient: [Color.indigo.opacity(0.8), Color.teal.opacity(0.7)]
        ),
        WelcomeStep(
            title: "科學小睡，精準喚醒",
            description: "NASA研究顯示，短暫小睡可提升警覺度54%、工作表現34%。PowerNap結合心率與動作監測，讓每次休息效果最大化。",
            imageName: "bed.double.fill",
            bgGradient: [Color.blue.opacity(0.8), Color.purple.opacity(0.7)]
        ),
        WelcomeStep(
            title: "個人化睡眠檢測",
            description: "PowerNap會分析您的睡眠模式，逐步優化檢測算法。建議晚上睡覺時也配戴手錶，讓系統收集睡眠數據，提高白天小睡的檢測準確度。",
            imageName: "person.text.rectangle.fill",
            bgGradient: [Color.purple.opacity(0.7), Color.pink.opacity(0.6)]
        ),
        WelcomeStep(
            title: "需要健康權限",
            description: "我們需要訪問您的心率數據來檢測您的休息狀態。請點擊下一步並授予健康權限。",
            imageName: "heart.fill",
            bgGradient: [Color.red.opacity(0.6), Color.orange.opacity(0.5)]
        ),
        WelcomeStep(
            title: "準備完成",
            description: "現在您可以開始使用PowerNap來優化您的休息時間了！",
            imageName: "checkmark.circle.fill",
            bgGradient: [Color.green.opacity(0.7), Color.blue.opacity(0.5)]
        )
    ]
    
    var body: some View {
        // 使用ZStack將背景和內容疊加
        ZStack {
            // 動態背景
            LinearGradient(
                gradient: Gradient(colors: steps[currentStep].bgGradient),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // 主要內容
            VStack {
                // 顯示當前步驟
                if currentStep < steps.count {
                    stepView(for: steps[currentStep])
                }
                
                Spacer()
                
                // 按鈕區域
                if currentStep == 1 && permissionManager.healthPermissionStatus != .granted {
                    // 健康權限請求按鈕
                    Button(action: requestHealthKitAuthorization) {
                        if isRequestingHealthKit {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("授權健康訪問")
                                .bold()
                                .foregroundColor(.white)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .clipShape(Capsule())
                    .padding(.horizontal)
                    .disabled(isRequestingHealthKit)
                } else {
                    HStack {
                        // 上一步按鈕（如果不是第一步）
                        if currentStep > 0 {
                            Button(action: previousStep) {
                                Image(systemName: "chevron.left")
                                    .font(.body)
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        // 下一步或完成按鈕
                        Button(action: {
                            if currentStep == steps.count - 1 {
                                // 最後一步，完成引導
                                permissionManager.completeOnboarding()
                                onComplete()
                            } else {
                                // 進入下一步
                                nextStep()
                            }
                        }) {
                            HStack {
                                if currentStep == steps.count - 1 {
                                    Text("開始使用")
                                        .bold()
                                        .foregroundColor(.white)
                                } else {
                                    Text("下一步")
                                        .bold()
                                        .foregroundColor(.white)
                                }
                                
                                Image(systemName: "chevron.right")
                                    .font(.body)
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(Color.black.opacity(0.3))
                            .clipShape(Capsule())
                        }
                        // 如果是健康權限步驟且未授權，則禁用下一步
                        .disabled(currentStep == 1 && permissionManager.healthPermissionStatus != .granted)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
    
    // 顯示特定步驟的視圖
    func stepView(for step: WelcomeStep) -> some View {
        VStack(spacing: 20) {
            // 圖標區域，使用圓形背景
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 120, height: 120)
                
                Image(systemName: step.imageName)
                    .font(.system(size: 60))
                    .foregroundColor(.white)
            }
            .padding(.top, 30)
            
            // 標題，使用較大字體和白色顯示
            Text(step.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // 描述，使用淺色背景卡片提高可讀性
            Text(step.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.1))
                .cornerRadius(15)
                .padding(.horizontal)
        }
    }
    
    // 請求HealthKit授權
    func requestHealthKitAuthorization() {
        isRequestingHealthKit = true
        
        Task {
            let success = await permissionManager.requestHealthPermissions()
            
            // 更新UI
            isRequestingHealthKit = false
            
            // 如果成功授權，自動進入下一步
            if success {
                nextStep()
            }
        }
    }
    
    // 進入下一步
    func nextStep() {
        withAnimation(.easeInOut) {
            if currentStep < steps.count - 1 {
                currentStep += 1
            }
        }
    }
    
    // 返回上一步
    func previousStep() {
        withAnimation(.easeInOut) {
            if currentStep > 0 {
                currentStep -= 1
            }
        }
    }
}

// 歡迎步驟模型
struct WelcomeStep {
    let title: String
    let description: String
    let imageName: String
    let bgGradient: [Color]    // 添加背景漸變顏色陣列
}

#if DEBUG
struct WelcomeViewPreview: PreviewProvider {
    static var previews: some View {
        let permissionManager = PermissionManager()
        return WelcomeView(permissionManager: permissionManager, onComplete: {})
    }
}
#endif 