import Foundation

/// 内置凭据：App 启动时用它自动换会话，用户无需输入密钥或密码
enum AppConfig {
    /// 服务器免密密钥（与 /opt/tesla-dash/data/.access-key 一致）
    static let accessKey = "10100b02adc6c960b45c77054e3b4d1cea845ea47d1bb6fc"

    /// 默认服务器地址
    static let serverURL = "https://www.zhangweiwei.cc"
}
