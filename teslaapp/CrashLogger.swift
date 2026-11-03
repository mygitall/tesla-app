import Foundation
import UIKit

/// 极简崩溃记录：不依赖第三方 SDK
/// - 用「会话标记」判断上次是否异常退出（安全，不涉及信号处理）
/// - 额外捕获 Objective-C 异常
enum CrashLogger {
    private static let markerKey = "session-running"
    private static let logFile = "crash.log"

    private static var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(logFile)
    }

    /// 启动时调用：上次没正常退出就记一条
    static func start() {
        let ud = UserDefaults.standard
        if ud.bool(forKey: markerKey) {
            append("异常退出（上次会话没有正常结束）")
        }
        ud.set(true, forKey: markerKey)

        NSSetUncaughtExceptionHandler { ex in
            CrashLogger.append("崩溃：\(ex.name.rawValue) — \(ex.reason ?? "")")
        }
    }

    /// 正常进入后台时调用，表示这次会话是干净的
    static func markCleanExit() {
        UserDefaults.standard.set(false, forKey: markerKey)
    }

    static func append(_ line: String) {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        let text = "[\(f.string(from: Date()))] \(line)\n"
        guard let url = fileURL else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(text.utf8))
            try? h.close()
        } else {
            try? Data(text.utf8).write(to: url)
        }
    }

    static func read() -> String {
        guard let url = fileURL, let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
