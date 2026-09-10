import Foundation
import Security

/// 判断当前进程处在什么样的登录会话里。
///
/// 关键依据是 Security.framework 的 `SessionGetInfo`，它不依赖任何环境变量，
/// 因此 sudo 的 env_reset 剥不掉，别人也伪造不了：
///
///   本机图形登录：attrs=0x6030  hasGraphicAccess=true  isRemote=false
///   SSH 登录    ：attrs=0x5020  hasGraphicAccess=false isRemote=true
///
/// 非图形会话里 Touch ID 对话框会弹到物理屏幕上（等于骚扰机器前的人），
/// 而且随后的钥匙串读取必定以 -25308（User interaction is not allowed）失败 ——
/// 白等一场。所以这类请求直接拦掉，不要等指纹。
struct SessionContext {
    let hasGraphicAccess: Bool
    let isRemote: Bool
    let sshConnection: String?
    let sshClient: String?

    /// 需要拦截的条件：拿不到图形访问，或者明摆着是 SSH 进来的。
    ///
    /// 这里刻意不提供任何环境变量放行开关 —— 那种开关攻击者自己就能设，
    /// 等于把闸门的钥匙留在门口，而它换来的“便利”在非图形会话里并不存在
    /// （钥匙串照样以 -25308 失败）。
    var shouldBlock: Bool {
        !hasGraphicAccess || sshConnection != nil || sshClient != nil
    }

    /// 给人看的来源描述，例如 “SSH 来自 192.168.1.7”。
    var originDescription: String {
        if let raw = sshConnection ?? sshClient {
            let host = raw.split(separator: " ").first.map(String.init) ?? raw
            return "SSH 来自 \(host)"
        }
        return hasGraphicAccess ? "本机图形会话" : "非图形会话"
    }

    var attributeSummary: String {
        "图形访问=\(hasGraphicAccess ? "有" : "无") 远程=\(isRemote ? "是" : "否")"
    }

    static func current() -> SessionContext {
        var sid: SecuritySessionId = 0
        var attrs = SessionAttributeBits(rawValue: 0)
        let status = SessionGetInfo(callerSecuritySession, &sid, &attrs)
        let env = ProcessInfo.processInfo.environment
        // 万一取不到会话信息，就按“有图形访问”处理，避免误伤本机的正常使用；
        // 真正的防线是钥匙串 ACL，这里的拦截主要是省掉无谓的等待并给出提醒。
        let ok = status == noErr
        return SessionContext(
            hasGraphicAccess: ok ? attrs.contains(.sessionHasGraphicAccess) : true,
            isRemote: ok ? attrs.contains(.sessionIsRemote) : false,
            sshConnection: env["SSH_CONNECTION"],
            sshClient: env["SSH_CLIENT"]
        )
    }
}

/// 往机器前那块屏幕上推一条通知。
///
/// 非图形会话里弹不出模态对话框（osascript 的 `display alert` 会立刻返回、什么都不显示），
/// 但 `display notification` 是可以送达的，所以用带声音的通知横幅来提醒。
enum ConsoleAlert {
    static func notify(title: String, subtitle: String, message: String) {
        let script = "display notification \(Prompt.appleScriptString(message))"
            + " with title \(Prompt.appleScriptString(title))"
            + " subtitle \(Prompt.appleScriptString(subtitle))"
            + " sound name \"Basso\""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return }

        // 最多等 3 秒就走，绝不因为通知没送出去而把 sudo 拖住。
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning { process.terminate() }
    }
}
