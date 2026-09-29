// 라이브 DB 에서 안 읽은 채팅 조회
//
// 안 읽은 수  = NTChatRoom.countOfNewMessage
// 안 읽은 메시지 = 그 방의 logId > NTChatRoom.lastSeenLogId 인 메시지 (내가 보낸 것·내부 feed 제외)
import Foundation

struct UnreadMessage {
    let logId: Int64
    let author: String
    let text: String
    let sentAt: Date
}

struct UnreadRoom {
    let chatId: Int64
    let name: String
    let count: Int
    let muted: Bool
    let isOpenChat: Bool            // 오픈채팅 (NTChatRoom.linkId != 0)
    let mentioned: Bool             // 안 읽은 메시지 중 나를 멘션한 것이 있음
    let replied: Bool               // 안 읽은 메시지 중 내 메시지에 답장한 것이 있음
    let messages: [UnreadMessage]   // 오래된 → 최신
    var lastAt: Date { messages.last?.sentAt ?? .distantPast }
}

/// 설정 화면의 채팅방 선택용
struct RoomInfo: Identifiable, Hashable {
    let chatId: Int64
    let name: String
    let isOpenChat: Bool
    let lastAt: Date
    var id: Int64 { chatId }
}

final class KakaoStore {
    let db: SQLCipherDB
    let dbPath: String
    let me: Int64
    private var users: [Int64: String] = [:]
    private var titles: [Int64: String] = [:]
    private var links: [Int64: String] = [:]
    private var namesLoadedAt = Date.distantPast

    init() throws {
        guard let dev = KakaoKey.deviceUUID() else { throw SQLCipherError.load("IOPlatformUUID 없음") }
        guard let path = KakaoKey.encryptedDBPath() else { throw SQLCipherError.load("암호화 DB 없음(카카오톡 컨테이너 접근 권한 확인)") }
        guard let uid = KakaoKey.userId(dev: dev, dbName: path.lastPathComponent) else {
            throw SQLCipherError.load("userId 복원 실패")
        }
        me = uid
        dbPath = path.path
        db = try SQLCipherDB(path: path.path, passphrase: KakaoKey.secureKey(userId: uid, dev: dev))
    }

    /// 닉네임/단톡방 제목/오픈채팅명 캐시 (새 친구·방 반영 위해 60초마다 갱신)
    fileprivate func loadNames() {
        guard Date().timeIntervalSince(namesLoadedAt) > 60 else { return }
        namesLoadedAt = Date()
        func dict(_ sql: String) -> [Int64: String] {
            var d: [Int64: String] = [:]
            for r in (try? db.query(sql)) ?? [] { if let k = r[0].int, let v = r[1].string { d[k] = v } }
            return d
        }
        // 내가 지정한 이름(friendNickName) 우선 → 닉네임 → 표시명
        users = dict("SELECT userId, COALESCE(NULLIF(friendNickName,''),NULLIF(nickName,''),NULLIF(displayName,''),userId) FROM NTUser")
        titles = dict("SELECT chatId, content FROM NTChatMeta WHERE type=3 AND content<>''")
        links = dict("SELECT linkId, linkName FROM NTOpenLink WHERE linkName<>''")
    }

    /// 방 이름: 사용자 지정명 → 단톡방 제목 → 오픈채팅명 → 멤버 닉네임
    fileprivate func roomName(chatId: Int64, name: String?, members: Data?, linkId: Int64) -> String {
        if let name, !name.isEmpty { return name }
        if let t = titles[chatId] { return t }
        if linkId != 0, let l = links[linkId] { return l }
        var names: [String] = []
        if let members,
           let arr = try? PropertyListSerialization.propertyList(from: members, format: nil) as? [Any] {
            for m in arr {
                guard let id = (m as? NSNumber)?.int64Value ?? Int64("\(m)"), id != me else { continue }
                names.append(users[id] ?? String(id))
            }
        }
        if !names.isEmpty {
            var s = names.prefix(4).joined(separator: ", ")
            if names.count > 4 { s += " 외 \(names.count - 4)명" }
            return s
        }
        return "(\(chatId))"
    }

    /// DB·WAL 파일의 (수정 시각, 크기). 카카오톡이 커밋하면 WAL 이 바뀌므로 변경 감지에 쓴다.
    /// (카카오톡 SQLCipher 는 SQLite 3.8.4 라 PRAGMA data_version 이 없다.) stat() 두 번이라 매우 싸다.
    func changeStamp() -> [Int64] {
        [dbPath, dbPath + "-wal"].flatMap { path -> [Int64] in
            var st = stat()
            guard stat(path, &st) == 0 else { return [0, 0, 0] }
            return [Int64(st.st_mtimespec.tv_sec), Int64(st.st_mtimespec.tv_nsec), Int64(st.st_size)]
        }
    }

    func totalUnread() throws -> Int {
        Int(try db.query("SELECT COALESCE(sum(countOfNewMessage),0) FROM NTChatRoom WHERE countOfNewMessage>0 AND hidden=0")
            .first?.first?.int ?? 0)
    }

    /// 안 읽은 메시지가 있는 방들 (최근 메시지 순). 방마다 최대 messageLimit 개의 안 읽은 메시지.
    func unreadRooms(messageLimit: Int = 20) throws -> [UnreadRoom] {
        loadNames()
        let rows = try db.query("""
            SELECT chatId, chatName, displayMemberIds, linkId, countOfNewMessage, pushAlert, lastSeenLogId
            FROM NTChatRoom WHERE countOfNewMessage>0 AND hidden=0
            """)
        var rooms: [UnreadRoom] = []
        for r in rows {
            guard let chatId = r[0].int else { continue }
            let seen = r[6].int ?? 0
            let msgs = try db.query("""
                SELECT logId, authorId, type, message, sentAt FROM NTChatMessage
                WHERE chatId=? AND logId>? AND authorId<>? ORDER BY logId DESC LIMIT ?
                """, [chatId, seen, me, messageLimit])
            let unread: [UnreadMessage] = msgs.reversed().compactMap { m in
                let text = m[3].string
                if MessageRenderer.isHiddenFeed(text) { return nil }
                let author = m[1].int.map { users[$0] ?? String($0) } ?? ""
                return UnreadMessage(logId: m[0].int ?? 0, author: author,
                                     text: MessageRenderer.render(type: Int(m[2].int ?? -1), message: text),
                                     sentAt: Date(timeIntervalSince1970: TimeInterval(m[4].int ?? 0)))
            }
            let (mentioned, replied) = try mentionsOfMe(chatId: chatId, after: seen)
            rooms.append(UnreadRoom(chatId: chatId,
                                    name: roomName(chatId: chatId, name: r[1].string, members: r[2].data, linkId: r[3].int ?? 0),
                                    count: Int(r[4].int ?? 0), muted: (r[5].int ?? 1) == 0,
                                    isOpenChat: (r[3].int ?? 0) != 0, mentioned: mentioned, replied: replied,
                                    messages: unread))
        }
        return rooms.sorted { $0.lastAt > $1.lastAt }
    }

    /// 안 읽은 메시지(logId > seen) 중 나를 멘션한 것 / 내 메시지에 답장한 것이 있는지.
    /// attachment 예: {"mentions":[{"user_id":123,"len":3,"at":[1]}]} · 답장(type 26) {"src_userId":123,...}
    /// 오픈채팅에서도 내 userId 는 같다. 내 id 가 들어간 attachment 만 SQL 로 거른 뒤 JSON 으로 확인.
    private func mentionsOfMe(chatId: Int64, after seen: Int64) throws -> (mentioned: Bool, replied: Bool) {
        let rows = try db.query("""
            SELECT type, attachment FROM NTChatMessage
            WHERE chatId=? AND logId>? AND authorId<>? AND attachment LIKE ?
            """, [chatId, seen, me, "%\(me)%"])
        var mentioned = false, replied = false
        for r in rows {
            guard let d = MessageRenderer.json(r[1].string) else { continue }
            if let ms = d["mentions"] as? [[String: Any]],
               ms.contains(where: { ($0["user_id"] as? NSNumber)?.int64Value == me }) { mentioned = true }
            if r[0].int == 26, (d["src_userId"] as? NSNumber)?.int64Value == me { replied = true }
            if mentioned && replied { break }
        }
        return (mentioned, replied)
    }
}

extension KakaoStore {
    /// 숨기지 않은 모든 채팅방 (최근 활동 순)
    func allRooms() throws -> [RoomInfo] {
        loadNames()
        return try db.query("""
            SELECT chatId, chatName, displayMemberIds, linkId, lastUpdatedAt FROM NTChatRoom
            WHERE hidden=0 ORDER BY lastUpdatedAt DESC
            """).compactMap { r in
            guard let chatId = r[0].int else { return nil }
            return RoomInfo(chatId: chatId,
                            name: roomName(chatId: chatId, name: r[1].string, members: r[2].data, linkId: r[3].int ?? 0),
                            isOpenChat: (r[3].int ?? 0) != 0,
                            lastAt: Date(timeIntervalSince1970: TimeInterval(r[4].int ?? 0)))
        }
    }
}

// MARK: - 메시지 → 표시 문자열

enum MessageRenderer {
    static let typeLabel: [Int: String] = [
        2: "[사진]", 3: "[동영상]", 5: "[음성]", 12: "[이모티콘]", 20: "[이모티콘]",
        6: "[링크]", 16: "[연락처]", 18: "[파일]", 27: "[사진]", 71: "[삭제된 메시지]",
        26: "[답장]", 23: "[선물]", 24: "[일정]", 25: "[투표]",
    ]
    static let placeholder: [String: String] = [
        "photo": "[사진]", "video": "[동영상]", "audio": "[음성]",
        "emoticon": "[이모티콘]", "file": "[파일]", "contact": "[연락처]",
    ]
    /// 화면에 표시하지 않는 내부 feed (숨김/리비전/봇/블라인드 등)
    static let hiddenFeeds: Set<Int> = [14, 25, 18, 26]

    static func json(_ message: String?) -> [String: Any]? {
        guard let m = message?.trimmingCharacters(in: .whitespacesAndNewlines), m.hasPrefix("{"),
              let d = m.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    static func isHiddenFeed(_ message: String?) -> Bool {
        guard let d = json(message), let ft = d["feedType"] as? Int else { return false }
        if hiddenFeeds.contains(ft) { return true }
        return (d["hidden"] as? Bool) == true && d["member"] == nil && d["members"] == nil
    }

    static func render(type: Int, message: String?) -> String {
        if type == 51 { return "[통화]" }
        if let m = message?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
            if let d = json(m) {
                if d["feedType"] != nil { return renderFeed(d) }
                if let t = d["type"] as? String, ["invite", "cinvite", "bye"].contains(t) { return "[통화]" }
                return typeLabel[type] ?? "[메시지]"      // 기타 구조화 메시지: 원시 JSON 숨김
            }
            return placeholder[m] ?? m
        }
        return typeLabel[type] ?? "[메시지]"
    }

    private static func renderFeed(_ d: [String: Any]) -> String {
        func nm(_ o: Any?) -> String {
            if let o = o as? [String: Any] { return (o["nickName"] as? String) ?? "\(o["userId"] ?? "")" }
            return o.map { "\($0)" } ?? ""
        }
        func names(_ l: Any?) -> String { ((l as? [Any]) ?? []).map(nm).joined(separator: ", ") }
        switch d["feedType"] as? Int {
        case 1: return "\(nm(d["inviter"]))님이 \(names(d["members"]))님을 초대했습니다"
        case 2: return (d["kicked"] as? Bool) == true ? "\(nm(d["member"]))님이 내보내졌습니다" : "\(nm(d["member"]))님이 나갔습니다"
        case 4: return "\(names(d["members"]))님이 들어왔습니다"
        case 11: return "\(nm(d["member"]))님이 내보내졌습니다"
        case 15: return "방장이 \(nm(d["newHost"]))님으로 변경되었습니다"
        case 13: return "삭제된 메시지입니다"
        default:
            if d["member"] != nil || d["members"] != nil {
                let n = names(d["members"])
                return "\(n.isEmpty ? nm(d["member"]) : n) 관련 알림"
            }
            return "시스템 메시지"
        }
    }
}
