import Foundation
import OpenDirectory

/// 用 OpenDirectory 校验密码是否就是当前用户的登录密码。
/// 目的：避免把打错的密码存进钥匙串，导致之后每次 sudo 都莫名其妙失败。
/// 走 API 而不是 `dscl . -authonly <user> <password>`，密码不会出现在进程参数里被 ps 看到。
enum DirectoryAuth {
    static func verify(password: String, user: String) -> Result<Void, Error> {
        do {
            let session = ODSession.default()
            let node = try ODNode(session: session, type: ODNodeType(kODNodeTypeAuthentication))
            let record = try node.record(withRecordType: kODRecordTypeUsers,
                                         name: user,
                                         attributes: nil)
            try record.verifyPassword(password)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
