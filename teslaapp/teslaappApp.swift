import SwiftUI

@main
struct teslaappApp: App {
    init() {
        // 启动动态字体监听（系统「文字大小」变化时重建界面）
        DispatchQueue.main.async {
            TypoScale.start()
            CrashLogger.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
