import SwiftUI
import HealthKit

struct PermissionReminderView: View {
    @ObservedObject var permissionManager: PermissionManager
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.slash.fill")
                .font(.system(size: 40))
                .foregroundColor(.red)
                .padding(.top, 20)
            
            Text("需要健康權限")
                .font(.headline)
                .fontWeight(.bold)
            
            Text("PowerNap需要訪問您的心率數據來檢測睡眠狀態。請授予健康權限以確保應用正常工作。")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            Button(action: {
                permissionManager.openHealthSettings()
                permissionManager.markUserReminded()
                isPresented = false
            }) {
                Text("前往設置")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            
            Button(action: {
                permissionManager.markUserReminded()
                isPresented = false
            }) {
                Text("稍後再說")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.secondary.opacity(0.3))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
    }
}

// 為了避免預覽錯誤，使用私有類型
#if DEBUG
struct PermissionReminderViewPreview: PreviewProvider {
    static var previews: some View {
        let manager = PermissionManager()
        return PermissionReminderView(
            permissionManager: manager,
            isPresented: .constant(true)
        )
    }
}
#endif 