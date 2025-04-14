import SwiftUI
import HealthKit

struct WelcomeView: View {
    // 用於處理權限和導航的狀態
    @State private var healthKitAuthorized = false
    @State private var isRequestingHealthKit = false
    @State private var currentStep = 0
    
    // 完成引導時的回調
    var onComplete: () -> Void
    
    // HealthKit服務
    @State private var healthStore = HKHealthStore()
    
    // 引導步驟內容
    let steps = [
        WelcomeStep(
            title: "歡迎使用PowerNap",
            description: "PowerNap能幫助您監測休息狀態，並在適當時間喚醒您，提高休息效率。",
            imageName: "bed.double.fill"
        ),
        WelcomeStep(
            title: "需要健康權限",
            description: "我們需要訪問您的心率數據來檢測您的休息狀態。請點擊下一步並授予健康權限。",
            imageName: "heart.fill"
        ),
        WelcomeStep(
            title: "準備完成",
            description: "現在您可以開始使用PowerNap來優化您的休息時間了！",
            imageName: "checkmark.circle.fill"
        )
    ]
    
    var body: some View {
        VStack {
            // 顯示當前步驟
            if currentStep < steps.count {
                stepView(for: steps[currentStep])
            }
            
            Spacer()
            
            // 按鈕區域
            if currentStep == 1 && !healthKitAuthorized {
                // 健康權限請求按鈕
                Button(action: requestHealthKitAuthorization) {
                    if isRequestingHealthKit {
                        ProgressView()
                    } else {
                        Text("授權健康訪問")
                            .bold()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isRequestingHealthKit)
            } else {
                HStack {
                    // 上一步按鈕（如果不是第一步）
                    if currentStep > 0 {
                        Button(action: previousStep) {
                            Image(systemName: "chevron.left")
                                .font(.body)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Spacer()
                    
                    // 下一步或完成按鈕
                    Button(action: {
                        if currentStep == steps.count - 1 {
                            // 最後一步，完成引導
                            onComplete()
                        } else {
                            // 進入下一步
                            nextStep()
                        }
                    }) {
                        if currentStep == steps.count - 1 {
                            Text("開始使用")
                                .bold()
                        } else {
                            Text("下一步")
                                .bold()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    // 如果是健康權限步驟且未授權，則禁用下一步
                    .disabled(currentStep == 1 && !healthKitAuthorized)
                }
            }
        }
        .padding()
    }
    
    // 顯示特定步驟的視圖
    func stepView(for step: WelcomeStep) -> some View {
        VStack(spacing: 15) {
            Image(systemName: step.imageName)
                .font(.system(size: 60))
                .foregroundStyle(.blue)
                .padding(.bottom, 10)
            
            Text(step.title)
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Text(step.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
    
    // 請求HealthKit授權
    func requestHealthKitAuthorization() {
        isRequestingHealthKit = true
        
        // 定義我們需要訪問的數據類型
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
        ]
        
        // 定義我們需要寫入的數據類型
        let typesToWrite: Set<HKSampleType> = []
        
        // 確保HealthKit在設備上可用
        guard HKHealthStore.isHealthDataAvailable() else {
            isRequestingHealthKit = false
            return
        }
        
        // 請求授權
        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { success, error in
            DispatchQueue.main.async {
                isRequestingHealthKit = false
                if success {
                    healthKitAuthorized = true
                    // 授權成功後自動進入下一步
                    nextStep()
                } else if let error = error {
                    print("健康授權錯誤: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // 進入下一步
    func nextStep() {
        withAnimation {
            if currentStep < steps.count - 1 {
                currentStep += 1
            }
        }
    }
    
    // 返回上一步
    func previousStep() {
        withAnimation {
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
}

#Preview {
    WelcomeView(onComplete: {})
} 