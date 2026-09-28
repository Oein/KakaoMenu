// 카카오톡 로컬 대화 DB 키 도출
//
//   deviceUUID       = IOPlatformUUID
//   hashedDeviceUUID = base64(SHA1(dev) ++ SHA256(dev))
//   pbkdf2(s, salt)  = hex(PBKDF2-HMAC-SHA256(utf8(s), utf8(salt), 100000, 128B))   # 256 hex
//   databaseName     = pbkdf2(".".join([".","F",uid,"A","F",rev(dev),".","|"]), rev(hdu))[28:106]
//   secureKey        = pbkdf2(rev("F".join(["A",hdu,"|","F",dev[:5],"H",uid,"|",dev[7:]])), dev[10:])
//
// userId 는 키체인에만 있어서, 계정 미디어 디렉토리명(= SHA512(str(userId)).hex()[40:80])을
// 오라클로 브루트포스해 복원하고, databaseName 이 실제 DB 파일명과 같은지로 검증한다.
import Foundation
import IOKit
import CommonCrypto
import CryptoKit

enum KakaoKey {
    static let appSupport = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Containers/com.kakao.KakaoTalkMac/Data/Library/Application Support/com.kakao.KakaoTalkMac")

    static func deviceUUID() -> String? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        return IORegistryEntryCreateCFProperty(svc, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    static func hashedDeviceUUID(_ dev: String) -> String {
        let d = Data(dev.utf8)
        return (Data(Insecure.SHA1.hash(data: d)) + Data(SHA256.hash(data: d))).base64EncodedString()
    }

    static func pbkdf2Hex(_ s: String, _ salt: String) -> String {
        let pw = Array(s.utf8), sl = Array(salt.utf8)
        var out = [UInt8](repeating: 0, count: 128)
        pw.withUnsafeBufferPointer { p in
            _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     p.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                                     pw.count, sl, sl.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 100_000, &out, out.count)
        }
        return out.hex
    }

    static func databaseName(userId: Int64, dev: String) -> String {
        let hdu = hashedDeviceUUID(dev)
        let body = [".", "F", String(userId), "A", "F", String(dev.reversed()), ".", "|"].joined(separator: ".")
        return String(Array(pbkdf2Hex(body, String(hdu.reversed())))[28..<106])
    }

    static func secureKey(userId: Int64, dev: String) -> String {
        let hdu = hashedDeviceUUID(dev)
        let body = ["A", hdu, "|", "F", String(dev.prefix(5)), "H", String(userId), "|", String(dev.dropFirst(7))]
            .joined(separator: "F")
        let salt = String(dev.dropFirst(Int(Double(dev.count) * 0.3)))    // = dev[10:]
        return pbkdf2Hex(String(body.reversed()), salt)
    }

    // MARK: - 파일 탐색

    private static func hexEntries(length: Int, directory: Bool) -> [URL] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])) ?? []
        return items.filter { u in
            let n = u.lastPathComponent
            guard n.count == length, n.allSatisfy({ "0123456789abcdef".contains($0) }) else { return false }
            return ((try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) == directory
        }
    }

    /// 본체 DB = 78자 hex 파일 중 가장 큰 것.
    static func encryptedDBPath() -> URL? {
        hexEntries(length: 78, directory: false).max { a, b in
            ((try? a.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) <
            ((try? b.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// 계정 미디어 디렉토리(40자 hex) 중 하위 항목이 가장 많은 것.
    static func accountDirHash() -> String? {
        hexEntries(length: 40, directory: true).max { a, b in
            ((try? FileManager.default.contentsOfDirectory(atPath: a.path).count) ?? 0) <
            ((try? FileManager.default.contentsOfDirectory(atPath: b.path).count) ?? 0)
        }?.lastPathComponent
    }

    // MARK: - userId 복원

    private static let defaultsKey = "kakaoUserId"

    /// 캐시(UserDefaults) → 브루트포스 순. 결과는 databaseName 으로 검증 후 캐시.
    static func userId(dev: String, dbName: String) -> Int64? {
        let cached = Int64(UserDefaults.standard.integer(forKey: defaultsKey))
        if cached > 0, databaseName(userId: cached, dev: dev) == dbName { return cached }
        guard let acct = accountDirHash(), let uid = bruteForceUserId(accountHash: acct),
              databaseName(userId: uid, dev: dev) == dbName else { return nil }
        UserDefaults.standard.set(uid, forKey: defaultsKey)
        return uid
    }

    /// SHA512(str(n)).hex()[40:80] == accountHash 인 n 을 모든 코어로 탐색.
    static func bruteForceUserId(accountHash: String, end: Int64 = 10_000_000_000) -> Int64? {
        guard let target = Data(hexString: accountHash), target.count == 20 else { return nil }
        let t = [UInt8](target)
        let cores = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        let chunk: Int64 = 5_000_000
        let lock = NSLock()
        var found: Int64?
        var next: Int64 = 1

        DispatchQueue.concurrentPerform(iterations: cores) { _ in
            var buf = [UInt8](repeating: 0, count: 20)
            while true {
                lock.lock()
                let lo = next; next += chunk
                let stop = found != nil || lo >= end
                lock.unlock()
                if stop { return }
                var n = lo
                let hi = min(lo + chunk, end)
                while n < hi {
                    // 10진 문자열을 직접 만들어 해시 (String 할당 회피)
                    var len = 0, v = n
                    repeat { buf[19 - len] = UInt8(48 + v % 10); v /= 10; len += 1 } while v > 0
                    let digest = buf.withUnsafeBufferPointer { p in
                        SHA512.hash(data: UnsafeRawBufferPointer(rebasing: UnsafeRawBufferPointer(p)[(20 - len)...]))
                    }
                    let hit = digest.withUnsafeBytes { d in (0..<20).allSatisfy { d[20 + $0] == t[$0] } }
                    if hit { lock.lock(); found = n; lock.unlock(); return }
                    n += 1
                }
            }
        }
        return found
    }
}

extension Sequence where Element == UInt8 {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

extension Data {
    init?(hexString s: String) {
        var d = Data(), chars = Array(s)
        guard chars.count % 2 == 0 else { return nil }
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let b = UInt8(String(chars[i...i + 1]), radix: 16) else { return nil }
            d.append(b)
        }
        self = d
    }
}
