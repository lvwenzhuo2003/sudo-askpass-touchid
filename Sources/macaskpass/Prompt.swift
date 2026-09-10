import Foundation

enum Prompt {
    static func err(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    /// 从终端读一行密码（关闭回显）。没有 tty 时返回 nil。
    static func readPasswordFromTTY(_ prompt: String) -> String? {
        guard isatty(STDIN_FILENO) == 1 else { return nil }

        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { return nil }
        var quiet = original
        quiet.c_lflag &= ~tcflag_t(ECHO)
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &quiet) == 0 else { return nil }
        defer {
            var restore = original
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &restore)
        }

        FileHandle.standardError.write(Data(prompt.utf8))
        let line = readLine(strippingNewline: true)
        FileHandle.standardError.write(Data("\n".utf8))
        return line
    }

    /// 没有终端时（比如从 Finder / 快捷指令触发）用系统对话框输入。
    static func readPasswordFromGUI(_ message: String) -> String? {
        let script = """
        display dialog \(appleScriptString(message)) \
        default answer "" with hidden answer \
        with title "macaskpass" with icon caution \
        buttons {"取消", "保存"} default button "保存"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, "-e", "text returned of result"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        // osascript 会把两条 -e 的结果各输出一行，取最后一行非空内容。
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .last.map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
    }

    static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
