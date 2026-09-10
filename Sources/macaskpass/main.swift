import Foundation
import LocalAuthentication

let macaskpassVersion = "1.0.0"
let installedPath = "/usr/local/bin/macaskpass"

let account = NSUserName()
let keychain = Keychain(account: account)

// MARK: - 帮助

func usageText() -> String {
    """
    macaskpass \(macaskpassVersion) —— 用指纹解锁 sudo 密码的 askpass 程序

    用法：
      macaskpass [提示语]        askpass 模式：弹出 Touch ID 对话框，
                                验证通过后把密码打印到标准输出（sudo 就是这么调用它的）
      macaskpass --set-password [--no-verify]
                                保存 / 更新钥匙串里的密码
      macaskpass --delete        从钥匙串删除密码
      macaskpass --status        查看当前状态（不读取密码，不弹指纹）
      macaskpass --test          完整跑一遍：指纹 -> 取密码 -> 校验密码是否仍然有效
      macaskpass --setup         打印需要加进 shell 配置的两行
      macaskpass --help | --version

    环境变量：
      SUDO_ASKPASS=\(installedPath)   sudo -A 用到的路径
      MACASKPASS_STRICT=1            只认指纹，不回退到「输入登录密码 / Apple Watch」
      MACASKPASS_TIMEOUT=120         等待验证的秒数上限（默认 120）
    """
}

func setupSnippet() -> String {
    """
    # 加到 ~/.zshrc（或 ~/.bashrc）：
    export SUDO_ASKPASS=\(installedPath)
    alias sudo='sudo -A'
    """
}

// MARK: - 子命令

func cmdAskpass(prompt: String?) throws {
    guard keychain.exists() else { throw MacAskpassError.noStoredPassword }

    var reason = "验证指纹后，把 \(account) 的密码交给 sudo"
    if let command = ProcessInfo.processInfo.environment["SUDO_COMMAND"], !command.isEmpty {
        reason = "验证指纹后执行：\(command)"
    } else if let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              prompt.count <= 120 {
        reason = "验证指纹以继续：\(prompt.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    try Biometrics.authenticate(reason: reason)

    var data = try keychain.load()
    data.append(0x0A) // sudo 按行读取
    FileHandle.standardOutput.write(data)
    data.resetBytes(in: 0..<data.count)
}

func cmdSetPassword(verify: Bool) throws {
    let hint = "请输入 \(account) 的登录密码（sudo 用的那个）"
    var password: String?

    if isatty(STDIN_FILENO) == 1 {
        password = Prompt.readPasswordFromTTY("\(hint)：")
        if !verify {
            let again = Prompt.readPasswordFromTTY("再输入一次确认：")
            guard password == again else {
                throw MacAskpassError.invalidPassword("两次输入不一致")
            }
        }
    } else {
        password = Prompt.readPasswordFromGUI("\(hint)。它会存进登录钥匙串，只有通过 Touch ID 才会交给 sudo。")
    }

    guard var pw = password, !pw.isEmpty else { throw MacAskpassError.emptyPassword }
    guard !pw.contains("\n"), !pw.contains("\r") else {
        throw MacAskpassError.invalidPassword("密码里不能包含换行")
    }

    if verify {
        if case .failure = DirectoryAuth.verify(password: pw, user: account) {
            throw MacAskpassError.passwordRejected
        }
    }

    var data = Data(pw.utf8)
    try keychain.save(data)
    data.resetBytes(in: 0..<data.count)
    pw = ""

    Prompt.err("已保存到登录钥匙串（服务名 \(Keychain.service)，账户 \(account)）。")
    Prompt.err("接下来可以跑：macaskpass --test")
}

func cmdDelete() throws {
    let removed = try keychain.delete()
    Prompt.err(removed ? "已从钥匙串删除保存的密码。" : "钥匙串里本来就没有保存的密码。")
}

func cmdStatus() {
    let bio = Biometrics.availability()
    let stored = keychain.exists()

    var lines: [String] = []
    lines.append("macaskpass \(macaskpassVersion)")
    lines.append("当前用户        : \(account)")
    lines.append("可执行文件      : \(CommandLine.arguments.first ?? "?")")
    lines.append("已安装到        : \(FileManager.default.isExecutableFile(atPath: installedPath) ? installedPath : "（还没装到 \(installedPath)）")")
    lines.append("生物识别        : \(bio.available ? "可用（\(bio.name)）" : "不可用 —— \(bio.reason)")")
    lines.append("严格指纹模式    : \(Biometrics.strict ? "开（MACASKPASS_STRICT=1）" : "关（指纹不可用时可回退到登录密码 / Apple Watch）")")
    lines.append("钥匙串中的密码  : \(stored ? "已保存" : "未保存 —— 请运行 macaskpass --set-password")")
    if let date = keychain.modificationDate() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        lines.append("最后更新时间    : \(formatter.string(from: date))")
    }
    let askpassEnv = ProcessInfo.processInfo.environment["SUDO_ASKPASS"] ?? "（未设置）"
    lines.append("SUDO_ASKPASS    : \(askpassEnv)")
    print(lines.joined(separator: "\n"))
}

func cmdTest() throws {
    guard keychain.exists() else { throw MacAskpassError.noStoredPassword }
    try Biometrics.authenticate(reason: "验证指纹以测试 macaskpass 能否取出密码")

    var data = try keychain.load()
    let password = String(decoding: data, as: UTF8.self)
    data.resetBytes(in: 0..<data.count)

    switch DirectoryAuth.verify(password: password, user: account) {
    case .success:
        print("✅ 一切正常：指纹通过，钥匙串取出的密码与当前登录密码一致。")
    case .failure:
        print("⚠️  指纹通过、密码也取到了，但它已经不是 \(account) 当前的登录密码。")
        print("    改过密码的话，重新运行：macaskpass --set-password")
        exit(2)
    }
}

// MARK: - 入口

do {
    let args = Array(CommandLine.arguments.dropFirst())
    switch args.first {
    case "--help", "-h":
        print(usageText())
    case "--version", "-V":
        print("macaskpass \(macaskpassVersion)")
    case "--status":
        cmdStatus()
    case "--setup":
        print(setupSnippet())
    case "--set-password", "--set":
        try cmdSetPassword(verify: !args.contains("--no-verify"))
    case "--delete", "--remove":
        try cmdDelete()
    case "--test":
        try cmdTest()
    case let arg? where arg.hasPrefix("--"):
        throw MacAskpassError.usage("未知选项 \(arg)\n\n\(usageText())")
    default:
        // sudo 会把提示语作为第一个参数传进来；没有参数时也走这条路。
        try cmdAskpass(prompt: args.first)
    }
} catch {
    Prompt.err("macaskpass: \(error)")
    exit(1)
}
