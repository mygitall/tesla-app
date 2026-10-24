import Foundation

/// BLE 手机钥匙的运行参数
enum BLEConfig {
    static let vin = "LRWYGCFJ3TC947372"

    /// 从 App 资源里读取已注册的手机钥匙私钥
    static var keyPEM: String {
        guard let url = Bundle.main.url(forResource: "phone-key", withExtension: "pem"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return text
    }
}
