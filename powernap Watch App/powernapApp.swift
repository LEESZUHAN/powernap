//
//  powernapApp.swift
//  powernap Watch App
//
//  Created by michaellee on 3/17/25.
//

import SwiftUI

/// 應用入口點
@main
struct PowerNapApp: App {
    // 使用環境對象儲存與共享權限管理器
    @StateObject private var permissionManager = PermissionManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(permissionManager)
                .onAppear {
                    Task {
                        await permissionManager.checkHealthPermissions()
                    }
                }
        }
    }
}
