import Foundation
import LocalAuthentication

enum Biometrics {
    /// 是否禁止「指纹不可用时回退到系统密码/Apple Watch」。
    /// 置 MACASKPASS_STRICT=1 后，没有指纹就直接失败。
    static var strict: Bool {
        let v = ProcessInfo.processInfo.environment["MACASKPASS_STRICT"] ?? "0"
        return v == "1" || v.lowercased() == "true" || v.lowercased() == "yes"
    }

    /// 整体等待上限，避免 sudo 永远挂在那里。
    static var timeout: Int {
        let raw = ProcessInfo.processInfo.environment["MACASKPASS_TIMEOUT"] ?? ""
        if let n = Int(raw), n > 0 { return n }
        return 120
    }

    static func biometryName(_ type: LABiometryType) -> String {
        switch type {
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .faceID: return "Face ID"
        default: return "生物识别"
        }
    }

    static func availability() -> (available: Bool, name: String, reason: String) {
        let context = LAContext()
        var error: NSError?
        let ok = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return (ok, biometryName(context.biometryType), error?.localizedDescription ?? "")
    }

    /// 弹出系统的指纹对话框；成功返回，失败抛错。
    static func authenticate(reason: String) throws {
        let context = LAContext()
        context.localizedCancelTitle = "取消"

        var policy: LAPolicy = .deviceOwnerAuthenticationWithBiometrics
        var error: NSError?
        if !context.canEvaluatePolicy(policy, error: &error) {
            let why = error?.localizedDescription ?? "未知原因"
            if strict { throw MacAskpassError.biometryUnavailable(why) }
            // 退回到「设备所有者验证」：仍然优先走指纹，指纹不可用时允许 Apple Watch / 输入登录密码。
            policy = .deviceOwnerAuthentication
            var fallbackError: NSError?
            guard context.canEvaluatePolicy(policy, error: &fallbackError) else {
                throw MacAskpassError.biometryUnavailable(
                    "\(why)；回退方式同样不可用：\(fallbackError?.localizedDescription ?? "未知原因")")
            }
        }

        let semaphore = DispatchSemaphore(value: 0)
        var succeeded = false
        var evaluationError: Error?

        context.evaluatePolicy(policy, localizedReason: reason) { ok, err in
            succeeded = ok
            evaluationError = err
            semaphore.signal()
        }

        // 一边等回调一边跑主线程 runloop（命令行程序没有现成的事件循环）。
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        var timedOut = false
        while semaphore.wait(timeout: .now() + 0.05) == .timedOut {
            if Date() >= deadline {
                timedOut = true
                break
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        if timedOut {
            context.invalidate()
            throw MacAskpassError.authTimedOut(timeout)
        }
        if succeeded { return }

        if let laError = evaluationError as? LAError {
            switch laError.code {
            case .userCancel, .systemCancel, .appCancel:
                throw MacAskpassError.authCancelled
            case .userFallback:
                throw MacAskpassError.authFailed("用户选择了其他验证方式，但本工具未启用该方式")
            case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout:
                throw MacAskpassError.biometryUnavailable(laError.localizedDescription)
            default:
                throw MacAskpassError.authFailed(laError.localizedDescription)
            }
        }
        throw MacAskpassError.authFailed(evaluationError?.localizedDescription ?? "未知原因")
    }
}
