import SwiftUI

@main
struct teslaappApp: App {
    init() {
        // 启动动态字体监听（系统「文字大小」变化时重建界面）
        DispatchQueue.main.async {
            TypoScale.start()
            CrashLogger.start()
            Notify.requestPermission()
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { phase in
            // 任意页面切到后台都算干净退出，避免下次启动误报"异常退出"
            if phase != .active { CrashLogger.markCleanExit() }
        }
    }
}
