# macaskpass

macOS 上的 `sudo` askpass 程序：**用指纹解锁保存在钥匙串里的密码，再交给 sudo**。

跑 `sudo -A ...` 时会弹出系统的 Touch ID 对话框，按一下指纹，密码就自动送进 sudo，
不用再手打密码。

```
$ sudo -A softwareupdate -l
        ┌─────────────────────────────────┐
        │   👆  验证指纹以继续：           │
        │       [sudo] password for you:  │
        │        [ 取消 ]                 │
        └─────────────────────────────────┘
```

## 工作原理

1. 你的登录密码存在**登录钥匙串**里（服务名 `macaskpass`，账户为当前用户名）。
2. sudo 通过 `SUDO_ASKPASS` 调用本程序，并把提示语作为第一个参数传进来。
3. 本程序先用 LocalAuthentication 弹出 Touch ID 对话框；
4. 验证通过后才去钥匙串取密码，打印到标准输出交给 sudo；验证失败则什么都不输出并以非 0 退出。

## 安全模型

两道锁，都要过：

| 谁想拿到密码 | 会发生什么 |
| --- | --- |
| 你自己跑 `sudo -A` | 弹 Touch ID，按指纹即可 |
| 别的程序直接读这条钥匙串 | 被钥匙串 ACL 拦住，弹出「钥匙串访问」框，必须输入**登录密码**授权 |
| 别人跑 `/usr/local/bin/macaskpass` | 照样弹 Touch ID，没有你的手指拿不到 |

钥匙串条目的 ACL 在创建时绑定了本程序的代码签名（ad-hoc / cdhash）。
实测：同一个二进制再次读取是**免授权、无弹窗**的；换一个二进制读取会被拦下来要求输入登录密码。

需要注意的边界：

- 这毕竟是把登录密码**明文存在钥匙串里**（钥匙串本身是加密的，且随登录钥匙串锁定而锁定）。
  安全性 ≈ 「你的钥匙串 + 你的手指」，比一次次手打密码方便，但不等于零风险。
- 想要更强的保证（密钥进 Secure Enclave、没有指纹连密文都取不出来），需要用
  data protection keychain + 生物识别访问控制，而那要求程序带
  `keychain-access-groups` entitlement 并用付费开发者证书签名 —— ad-hoc 签名会被系统直接拒绝
  （`SecItemAdd` 返回 `-34018`，强行加 entitlement 的 ad-hoc 二进制会被 kill -9）。
- 如果你觉得「存密码」这件事本身不可接受，看下面的 [不存密码的替代方案](#不存密码的替代方案)。

## 安装

```sh
cd ~/macaskpass
make                 # 编译（Swift 6，无第三方依赖）
sudo make install    # 装到 /usr/local/bin/macaskpass
```

然后保存密码（**不要加 sudo**，否则条目会存到 root 的钥匙串里）：

```sh
macaskpass --set-password
```

输入的密码会先用 OpenDirectory 校验一次是不是你当前的登录密码，
避免把打错的密码存进去导致以后每次 sudo 都失败。确认无误但校验不过（比如网络账户），
可以用 `macaskpass --set-password --no-verify` 跳过。

最后让 sudo 用上它，把这两行加进 `~/.zshrc`：

```sh
export SUDO_ASKPASS=/usr/local/bin/macaskpass
alias sudo='sudo -A'
```

（`macaskpass --setup` 会直接把这两行打出来。）
不想改 alias 的话，也可以只在需要时手动写 `sudo -A <命令>`。

## 用法

```
macaskpass [提示语]                     askpass 模式（sudo 就是这么调用的）
macaskpass --set-password [--no-verify] 保存 / 更新密码
macaskpass --delete                     从钥匙串删除密码
macaskpass --status                     查看状态（不读密码、不弹指纹）
macaskpass --test                       完整跑一遍：指纹 → 取密码 → 校验密码是否仍然有效
macaskpass --setup                      打印要加进 shell 配置的两行
macaskpass --help | --version
```

环境变量：

| 变量 | 作用 |
| --- | --- |
| `SUDO_ASKPASS` | 指向 `/usr/local/bin/macaskpass`，`sudo -A` 用 |
| `MACASKPASS_STRICT=1` | 只认指纹。默认情况下指纹不可用时会回退到系统验证对话框（可输入登录密码或用 Apple Watch） |
| `MACASKPASS_TIMEOUT=120` | 等待验证的秒数上限，超时就失败，避免 sudo 一直挂着 |

## 常见问题

**重新编译或重装之后，sudo 时弹出「钥匙串访问」要我输入登录密码？**
新编出来的二进制 cdhash 变了，不再匹配旧条目的 ACL。在弹框里点「始终允许」即可，
或者干脆重跑一次 `macaskpass --set-password`（会删掉旧条目、按新二进制重建 ACL）。

**改了 Mac 登录密码之后 sudo 失败？**
重跑 `macaskpass --set-password`。平时可以用 `macaskpass --test` 检查存的密码是否还有效。

**在 tmux / screen 里没反应？**
tmux 的 server 进程不在 GUI 会话的 bootstrap 命名空间里，LocalAuthentication 弹不出对话框
（`pam_tid` 的 Touch ID sudo 也有同样的问题）。解决办法是装
[`pam_reattach`](https://github.com/fabianishere/pam_reattach)，或者在这种场景下用普通的 `sudo`。

**通过 SSH 登录时？**
没有 GUI 会话，指纹用不了。非严格模式下会尝试回退，通常也会失败并以非 0 退出，
此时 sudo 会正常报认证失败 —— 直接用不带 `-A` 的 `sudo` 手打密码即可。

**指纹连错太多次被锁了？**
系统会要求先用登录密码解锁一次 Touch ID（`biometryLockout`）。锁屏后用密码解锁即可恢复。

## 不存密码的替代方案

如果只是想「sudo 时按指纹」，macOS 自带更干净的做法，**完全不需要存密码**：

```sh
sudo cp /etc/pam.d/sudo_local.template /etc/pam.d/sudo_local
sudo vi /etc/pam.d/sudo_local     # 取消 pam_tid.so 那一行的注释
```

它由 PAM 直接完成认证，比本工具更安全。本工具的价值在于：
密码是真的被交给了 sudo，因此在 `pam_tid` 覆盖不到、但仍需要密码走 stdin 的场景里也能用，
并且可以按需切换（只在 `sudo -A` 时生效）。

## 卸载

```sh
macaskpass --delete      # 先清掉钥匙串里的密码
sudo make uninstall      # 再删掉可执行文件
```

## 项目结构

```
Sources/macaskpass/
  main.swift           命令行入口与各子命令
  Biometrics.swift     Touch ID（LocalAuthentication），含超时与回退策略
  Keychain.swift       登录钥匙串读写
  DirectoryAuth.swift  用 OpenDirectory 校验密码是否为当前登录密码
  Prompt.swift         终端无回显输入 / 无 tty 时的图形输入框
  Errors.swift         错误类型与中文提示
```
