import Foundation
import Security

enum MacAskpassError: Error, CustomStringConvertible {
    case keychain(OSStatus)
    case noStoredPassword
    case biometryUnavailable(String)
    case authFailed(String)
    case authCancelled
    case authTimedOut(Int)
    case passwordRejected
    case emptyPassword
    case invalidPassword(String)
    case usage(String)

    var description: String {
        switch self {
        case .keychain(let status):
            let msg = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
            return "钥匙串操作失败（OSStatus \(status)）：\(msg)"
        case .noStoredPassword:
            return "钥匙串里还没有保存密码，请先运行：macaskpass --set-password"
        case .biometryUnavailable(let why):
            return "无法使用 Touch ID：\(why)"
        case .authFailed(let why):
            return "身份验证失败：\(why)"
        case .authCancelled:
            return "身份验证已取消"
        case .authTimedOut(let seconds):
            return "身份验证超时（\(seconds) 秒内没有完成）"
        case .passwordRejected:
            return "系统拒绝了这个密码（与当前用户的登录密码不符）。确认无误可加 --no-verify 跳过校验。"
        case .emptyPassword:
            return "密码为空，未保存"
        case .invalidPassword(let why):
            return "密码不可用：\(why)"
        case .usage(let msg):
            return msg
        }
    }
}
