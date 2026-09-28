// 카카오톡 앱에 포함된 SQLCipher.framework 를 dlopen 해서 암호화 DB 를 읽기전용으로 연다.
// 원본 DB/WAL 을 그대로 열어 항상 최신 상태를 본다.
import Foundation

enum SQLValue {
    case int(Int64), double(Double), text(String), blob(Data), null

    var int: Int64? { if case .int(let v) = self { return v }; return nil }
    var string: String? {
        switch self {
        case .text(let s): return s
        case .int(let v): return String(v)
        default: return nil
        }
    }
    var data: Data? {
        switch self {
        case .blob(let d): return d
        case .text(let s): return Data(s.utf8)
        default: return nil
        }
    }
}

enum SQLCipherError: Error, CustomStringConvertible {
    case load(String), open(Int32), key(String), prepare(String)
    var description: String {
        switch self {
        case .load(let s): return "SQLCipher 로드 실패: \(s)"
        case .open(let rc): return "DB 열기 실패 rc=\(rc)"
        case .key(let s): return "복호화 실패: \(s)"
        case .prepare(let s): return "쿼리 실패: \(s)"
        }
    }
}

final class SQLCipherDB {
    static let frameworkPath = "/Applications/KakaoTalk.app/Contents/Frameworks/SQLCipher.framework/SQLCipher"

    private typealias OpenV2 = @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<OpaquePointer?>, Int32, UnsafePointer<CChar>?) -> Int32
    private typealias Key = @convention(c) (OpaquePointer, UnsafeRawPointer, Int32) -> Int32
    private typealias Exec = @convention(c) (OpaquePointer, UnsafePointer<CChar>, OpaquePointer?, OpaquePointer?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
    private typealias Prepare = @convention(c) (OpaquePointer, UnsafePointer<CChar>, Int32, UnsafeMutablePointer<OpaquePointer?>, OpaquePointer?) -> Int32
    private typealias StmtInt = @convention(c) (OpaquePointer) -> Int32
    private typealias ColInt = @convention(c) (OpaquePointer, Int32) -> Int32
    private typealias ColInt64 = @convention(c) (OpaquePointer, Int32) -> Int64
    private typealias ColDouble = @convention(c) (OpaquePointer, Int32) -> Double
    private typealias ColPtr = @convention(c) (OpaquePointer, Int32) -> UnsafeRawPointer?
    private typealias BindInt64 = @convention(c) (OpaquePointer, Int32, Int64) -> Int32
    private typealias BindText = @convention(c) (OpaquePointer, Int32, UnsafePointer<CChar>, Int32, Int) -> Int32
    private typealias ErrMsg = @convention(c) (OpaquePointer) -> UnsafePointer<CChar>?
    private typealias Close = @convention(c) (OpaquePointer) -> Int32

    private let openV2: OpenV2, key: Key, exec: Exec, prepare: Prepare
    private let step: StmtInt, finalize: StmtInt, columnCount: StmtInt
    private let columnType: ColInt, columnBytes: ColInt
    private let columnInt64: ColInt64, columnDouble: ColDouble
    private let columnText: ColPtr, columnBlob: ColPtr
    private let bindInt64: BindInt64, bindText: BindText
    private let errmsg: ErrMsg, close: Close
    private var db: OpaquePointer?

    init(path: String, passphrase: String, pageSize: Int = 1024, kdfIter: Int = 64000) throws {
        guard let h = dlopen(Self.frameworkPath, RTLD_NOW) else {
            throw SQLCipherError.load(String(cString: dlerror()))
        }
        func sym<T>(_ name: String) throws -> T {
            guard let p = dlsym(h, name) else { throw SQLCipherError.load(name) }
            return unsafeBitCast(p, to: T.self)
        }
        openV2 = try sym("sqlite3_open_v2"); key = try sym("sqlite3_key"); exec = try sym("sqlite3_exec")
        prepare = try sym("sqlite3_prepare_v2"); step = try sym("sqlite3_step"); finalize = try sym("sqlite3_finalize")
        columnCount = try sym("sqlite3_column_count"); columnType = try sym("sqlite3_column_type")
        columnBytes = try sym("sqlite3_column_bytes"); columnInt64 = try sym("sqlite3_column_int64")
        columnDouble = try sym("sqlite3_column_double"); columnText = try sym("sqlite3_column_text")
        columnBlob = try sym("sqlite3_column_blob"); bindInt64 = try sym("sqlite3_bind_int64")
        bindText = try sym("sqlite3_bind_text"); errmsg = try sym("sqlite3_errmsg"); close = try sym("sqlite3_close")

        // 읽기전용 + URI(WAL 공유)
        let uri = "file:\(path)?mode=ro"
        let rc = openV2(uri, &db, 0x01 | 0x40, nil)   // SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard rc == 0, let db else { throw SQLCipherError.open(rc) }
        let k = Array(passphrase.utf8)
        _ = key(db, k, Int32(k.count))
        for p in ["PRAGMA cipher_page_size = \(pageSize);", "PRAGMA kdf_iter = \(kdfIter);", "PRAGMA query_only = 1;"] {
            _ = exec(db, p, nil, nil, nil)
        }
        guard exec(db, "SELECT count(*) FROM sqlite_master;", nil, nil, nil) == 0 else {
            throw SQLCipherError.key(lastError)
        }
    }

    deinit { if let db { _ = close(db) } }

    private var lastError: String { db.flatMap { errmsg($0) }.map { String(cString: $0) } ?? "?" }

    func query(_ sql: String, _ params: [Any] = []) throws -> [[SQLValue]] {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard prepare(db, sql, -1, &stmt, nil) == 0, let stmt else { throw SQLCipherError.prepare(lastError) }
        defer { _ = finalize(stmt) }
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            if let v = p as? Int64 { _ = bindInt64(stmt, idx, v) }
            else if let v = p as? Int { _ = bindInt64(stmt, idx, Int64(v)) }
            else { _ = bindText(stmt, idx, "\(p)", -1, -1) }     // SQLITE_TRANSIENT
        }
        var rows: [[SQLValue]] = []
        while step(stmt) == 100 {   // SQLITE_ROW
            let n = columnCount(stmt)
            var row: [SQLValue] = []
            row.reserveCapacity(Int(n))
            for c in 0..<n {
                switch columnType(stmt, c) {
                case 1: row.append(.int(columnInt64(stmt, c)))
                case 2: row.append(.double(columnDouble(stmt, c)))
                case 3:
                    let len = Int(columnBytes(stmt, c))
                    if let p = columnText(stmt, c) {
                        row.append(.text(String(decoding: UnsafeRawBufferPointer(start: p, count: len), as: UTF8.self)))
                    } else { row.append(.text("")) }
                case 4:
                    let len = Int(columnBytes(stmt, c))
                    row.append(.blob(columnBlob(stmt, c).map { Data(bytes: $0, count: len) } ?? Data()))
                default: row.append(.null)
                }
            }
            rows.append(row)
        }
        return rows
    }
}
