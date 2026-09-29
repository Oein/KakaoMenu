// KakaoMenu 설정 창 (권한 / 일반 / N 배지 조건 / 메뉴바 아이콘)
import Cocoa
import SwiftUI
import Combine
import ServiceManagement

enum Prefs {
    static let showUnreadCount = "showUnreadCount"
    static let badgeStyle = "badgeStyle"
    static let badgeRing = "badgeRing"
    static let watchedRooms = "watchedRooms"            // [chatId 문자열] — 노란 N
    static let watchedRoomNames = "watchedRoomNames"    // [chatId: 방 이름] — 표시용 캐시
    static let ignoredRooms = "ignoredRooms"            // [chatId 문자열] — N 표시 안 함
    static let ignoredRoomNames = "ignoredRoomNames"    // [chatId: 방 이름] — 표시용 캐시
    static let includeMuted = "includeMuted"
    static let showBubble = "showBubble"
    // 멘션(@나) / 답장(내 메시지에 답장) — 따로 설정
    static let mentionBypass = "mentionBypass"          // 무시·알림 꺼진 방이라도 N 표시
    static let replyBypass = "replyBypass"
    static let mentionMark = "mentionMark"              // 배지 글자 N → @
    static let replyMark = "replyMark"                  // 배지 글자 N → ↩

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showUnreadCount: false, badgeStyle: BadgeStyle.triangle.rawValue, badgeRing: RingStyle.shade.rawValue,
            watchedRooms: [String](), watchedRoomNames: [String: String](), includeMuted: true, showBubble: true,
            ignoredRooms: [String](), ignoredRoomNames: [String: String](),
            mentionBypass: true, replyBypass: false, mentionMark: true, replyMark: true,
        ])
        // 예전 'N만 표시' 배치 → 가로로 겹치기 + 말풍선 끔
        if UserDefaults.standard.string(forKey: badgeStyle) == "badgesOnly" {
            UserDefaults.standard.set(BadgeStyle.row.rawValue, forKey: badgeStyle)
            UserDefaults.standard.set(false, forKey: showBubble)
        }
    }

    static var watched: Set<Int64> { ids(watchedRooms) }
    static var ignored: Set<Int64> { ids(ignoredRooms) }
    private static func ids(_ key: String) -> Set<Int64> {
        Set((UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap { Int64($0) })
    }

    /// 메뉴바 아이콘에 반영할 상태
    struct IconState {
        var badges: [NBadge] = []               // 앞=빨강 → 파랑 → 노랑
        var marks: [NBadge: BadgeMark] = [:]    // 배지 글자 (@ · ↩, 없으면 N)
        var total = 0                           // 무시한 방을 뺀 안 읽은 수
    }

    /// 안 읽은 방 → 켤 N 배지
    ///   🟡 등록한 방(오픈채팅이어도 노랑) · 🔵 오픈채팅 · 🔴 그 외 일반 채팅
    ///   무시한 방·(설정 시) 알림 꺼진 방은 빼되, 멘션/답장 예외가 켜져 있으면 표시.
    static func iconState(for rooms: [UnreadRoom]) -> IconState {
        let d = UserDefaults.standard
        let watched = watched, ignored = ignored
        let includeMuted = d.bool(forKey: includeMuted)
        let mentionBypass = d.bool(forKey: mentionBypass), replyBypass = d.bool(forKey: replyBypass)
        let mentionMark = d.bool(forKey: mentionMark), replyMark = d.bool(forKey: replyMark)
        var on = Set<NBadge>()
        var state = IconState()
        for r in rooms where r.count > 0 {
            let bypass = (r.mentioned && mentionBypass) || (r.replied && replyBypass)
            if ignored.contains(r.chatId) && !bypass { continue }
            state.total += r.count
            let kind: NBadge = watched.contains(r.chatId) ? .yellow : (r.isOpenChat ? .blue : .red)
            if kind != .yellow && r.muted && !includeMuted && !bypass { continue }
            on.insert(kind)
            let mark: BadgeMark = r.mentioned && mentionMark ? .mention : (r.replied && replyMark ? .reply : .n)
            if mark > state.marks[kind] ?? .n { state.marks[kind] = mark }
        }
        state.badges = NBadge.allCases.filter(on.contains)
        return state
    }

    static func kind(of r: UnreadRoom) -> NBadge {
        watched.contains(r.chatId) ? .yellow : (r.isOpenChat ? .blue : .red)
    }
    static var style: BadgeStyle { BadgeStyle(rawValue: UserDefaults.standard.string(forKey: badgeStyle) ?? "") ?? .triangle }
    static var bubble: Bool { UserDefaults.standard.bool(forKey: showBubble) }
    static var ring: RingStyle { RingStyle(rawValue: UserDefaults.standard.string(forKey: badgeRing) ?? "") ?? .shade }
}

/// 설정에서 관리하는 채팅방 목록 (한 방은 둘 중 하나에만)
private enum RoomList: String, Identifiable, CaseIterable {
    case watched, ignored
    var id: String { rawValue }
    var idsKey: String { self == .watched ? Prefs.watchedRooms : Prefs.ignoredRooms }
    var namesKey: String { self == .watched ? Prefs.watchedRoomNames : Prefs.ignoredRoomNames }
    var other: RoomList { self == .watched ? .ignored : .watched }
}

/// 설정 창 왼쪽 카테고리
private enum SettingsPane: String, CaseIterable, Identifiable {
    case general, icon, rooms, mentions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "일반"
        case .icon: return "메뉴바 아이콘"
        case .rooms: return "채팅방"
        case .mentions: return "멘션 · 답장"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .icon: return "menubar.rectangle"
        case .rooms: return "bubble.left.and.bubble.right.fill"
        case .mentions: return "at"
        }
    }
    var tint: Color {
        switch self {
        case .general: return .gray
        case .icon: return .blue
        case .rooms: return Color(NBadge.yellow.fill(dark: false))
        case .mentions: return Color(NBadge.red.fill(dark: false))
        }
    }
}

private struct SettingsView: View {
    @AppStorage(Prefs.showUnreadCount) private var showUnreadCount = false
    @AppStorage(Prefs.badgeStyle) private var badgeStyle = BadgeStyle.triangle.rawValue
    @AppStorage(Prefs.badgeRing) private var badgeRing = RingStyle.shade.rawValue
    @AppStorage(Prefs.includeMuted) private var includeMuted = true
    @AppStorage(Prefs.showBubble) private var showBubble = true
    @AppStorage(Prefs.mentionBypass) private var mentionBypass = true
    @AppStorage(Prefs.replyBypass) private var replyBypass = false
    @AppStorage(Prefs.mentionMark) private var mentionMark = true
    @AppStorage(Prefs.replyMark) private var replyMark = true
    @State private var roomIds: [RoomList: [String]] = Dictionary(uniqueKeysWithValues: RoomList.allCases.map {
        ($0, UserDefaults.standard.stringArray(forKey: $0.idsKey) ?? [])
    })
    @State private var roomNames: [RoomList: [String: String]] = Dictionary(uniqueKeysWithValues: RoomList.allCases.map {
        ($0, UserDefaults.standard.dictionary(forKey: $0.namesKey) as? [String: String] ?? [:])
    })
    @State private var picking: RoomList?
    @State private var axTrusted = AXIsProcessTrusted()
    @State private var dataAccess = Permission.hasContainerAccess
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @AppStorage("settingsPane") private var pane = SettingsPane.general.rawValue   // 마지막으로 본 카테고리

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsPane.allCases, selection: Binding(get: { SettingsPane(rawValue: pane) ?? .general },
                                                           set: { pane = $0.rawValue })) { p in
                HStack(spacing: 8) {
                    // Label 아이콘은 사이드바가 크기를 바꿔서 직접 그린다
                    Image(systemName: p.symbol)
                        .resizable().scaledToFit().fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(width: 12, height: 12)
                        .frame(width: 20, height: 20)
                        .background(p.tint.gradient, in: RoundedRectangle(cornerRadius: 5))
                    Text(p.title)
                    Spacer()
                    if p == .general && !(axTrusted && dataAccess) {
                        Circle().fill(.orange).frame(width: 7, height: 7).help("권한이 필요합니다")
                    }
                }
                .padding(.vertical, 2)
                .tag(p)
            }
            .listStyle(.sidebar)
            .frame(width: 190)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 520)
        .sheet(item: $picking) { list in
            RoomPicker(selected: Set(roomIds[list] ?? [])) { picked in
                if let picked { setRooms(list, picked) }
                picking = nil
            }
        }
        .onReceive(tick) { _ in
            axTrusted = AXIsProcessTrusted()
            dataAccess = Permission.hasContainerAccess
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    @ViewBuilder private var detail: some View {
        Form {
            switch SettingsPane(rawValue: pane) ?? .general {
            case .general: generalPane
            case .icon: iconPane
            case .rooms: roomsPane
            case .mentions: mentionsPane
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }

    @ViewBuilder private var generalPane: some View {
        Section("권한") {
            permissionRow("손쉬운 사용", detail: "카카오톡 메뉴(모두 읽음 처리·잠금모드 등) 제어", granted: axTrusted) { Permission.request() }
            permissionRow("카카오톡 데이터", detail: "안 읽은 메시지·멘션 확인", granted: dataAccess) {
                Permission.requestContainerAccess { ok in
                    dataAccess = ok
                    if ok { (NSApp.delegate as? AppDelegate)?.startStore() }
                }
            }
        }
        Section {
            Toggle("로그인 시 자동 실행", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
        }
    }

    @ViewBuilder private var iconPane: some View {
        Section {
            IconPreview(style: BadgeStyle(rawValue: badgeStyle) ?? .triangle,
                        ring: RingStyle(rawValue: badgeRing) ?? .shade, showBubble: showBubble,
                        mentionMark: mentionMark, replyMark: replyMark)
        }
        Section {
            Toggle(isOn: $mentionMark) {
                titled("멘션 오면 @ 로 표시", "나를 멘션한 방 색의 N 배지가 @ 로 바뀝니다.")
            }
            Toggle(isOn: $replyMark) {
                titled("답장 오면 ↩ 로 표시", "내 메시지에 답장한 방 색의 N 배지가 ↩ 로 바뀝니다.")
            }
        } footer: {
            Text("우선순위: @ 멘션 > ↩ 답장 > N").font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Toggle(isOn: $showBubble) {
                titled("말풍선 표시", "끄면 알림이 있을 때 N 배지만, 없으면 말풍선을 표시합니다.")
            }
            Toggle("안 읽은 메시지 수 표시", isOn: $showUnreadCount)
        }
        Section("N 배지") {
            Picker("배치", selection: $badgeStyle) {
                ForEach(BadgeStyle.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
            }
            Picker(selection: $badgeRing) {
                Text("어둡게").tag(RingStyle.shade.rawValue)
                Text("흰색").tag(RingStyle.white.rawValue)
                Text("없음").tag(RingStyle.none.rawValue)
            } label: {
                titled("테두리", "어두운 메뉴바에서 배지 둘레")
            }
        }
    }

    @ViewBuilder private var roomsPane: some View {
        Section {
            roomRows(.watched) {
                Circle().fill(Color(NBadge.yellow.fill(dark: false))).frame(width: 8, height: 8)
            }
        } header: {
            Text("노란 N — 등록한 채팅방")
        } footer: {
            Text("빨간 N: 일반 채팅 · 파란 N: 오픈채팅 · 노란 N: 등록한 채팅방(오픈채팅이어도 노랑)")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            roomRows(.ignored) {
                Image(systemName: "bell.slash.fill").font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("무시할 채팅방")
        } footer: {
            Text("안 읽은 메시지가 있어도 N 을 켜지 않고 안 읽은 수에서도 뺍니다. 멘션·답장 예외가 켜져 있으면 표시합니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Toggle(isOn: $includeMuted) {
                titled("알림 꺼진 채팅방도 N 표시", "카카오톡에서 알림을 끈 방")
            }
        }
    }

    @ViewBuilder private var mentionsPane: some View {
        Section("나를 멘션했을 때") {
            Toggle(isOn: $mentionBypass) {
                titled("무시한 방·알림 꺼진 방이라도 N 표시", "멘션이 온 방은 예외로 표시합니다.")
            }
        }
        Section {
            Toggle(isOn: $replyBypass) {
                titled("무시한 방·알림 꺼진 방이라도 N 표시", "내 메시지에 답장이 온 방은 예외로 표시합니다.")
            }
        } header: {
            Text("내 메시지에 답장했을 때")
        } footer: {
            Text("안 읽은 메시지 기준입니다. @ · ↩ 표시는 '메뉴바 아이콘'에서 켜고 끕니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// 제목 + 회색 설명 두 줄
    private func titled(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// 등록/무시 목록 행 + 추가 버튼
    @ViewBuilder
    private func roomRows(_ list: RoomList, @ViewBuilder icon: () -> some View) -> some View {
        let ids = roomIds[list] ?? []
        let icon = icon()
        ForEach(ids, id: \.self) { id in
            HStack {
                icon
                Text(roomNames[list]?[id] ?? id).lineLimit(1)
                Spacer()
                Button { removeRoom(list, id) } label: { Image(systemName: "minus.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
        if ids.isEmpty {
            Text(list == .watched ? "등록한 채팅방이 없습니다" : "무시할 채팅방이 없습니다").foregroundStyle(.secondary)
        }
        Button("채팅방 추가…") { picking = list }
    }

    /// 목록을 통째로 바꾼다. 새로 넣은 방은 다른 목록에서 뺀다.
    private func setRooms(_ list: RoomList, _ rooms: [RoomInfo]) {
        let ids = rooms.map { String($0.chatId) }
        roomIds[list] = ids
        var names = roomNames[list] ?? [:]
        for r in rooms { names[String(r.chatId)] = r.name }
        roomNames[list] = names.filter { ids.contains($0.key) }
        roomIds[list.other]?.removeAll { ids.contains($0) }
        roomNames[list.other] = roomNames[list.other]?.filter { !ids.contains($0.key) }
        save()
    }

    private func removeRoom(_ list: RoomList, _ id: String) {
        roomIds[list]?.removeAll { $0 == id }
        roomNames[list]?[id] = nil
        save()
    }

    private func save() {
        for list in RoomList.allCases {
            UserDefaults.standard.set(roomNames[list] ?? [:], forKey: list.namesKey)
            UserDefaults.standard.set(roomIds[list] ?? [], forKey: list.idsKey)
        }
    }

    private func permissionRow(_ title: String, detail: String, granted: Bool, request: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            titled(title, detail)
            Spacer()
            if granted { Text("허용됨").foregroundStyle(.secondary) } else { Button("권한 요청", action: request) }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            KakaoMenu.alert("로그인 시 자동 실행 설정 실패: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// 현재 설정으로 그린 메뉴바 아이콘 미리보기 (어두운/밝은 메뉴바 × 알림 없음·🔴·🔴🔵·🔴🔵🟡)
private struct IconPreview: View {
    let style: BadgeStyle
    let ring: RingStyle
    let showBubble: Bool
    var mentionMark = true
    var replyMark = true
    private let cases: [(String, [NBadge], [NBadge: BadgeMark])] = [
        ("알림 없음", [], [:]), ("일반", [.red], [:]), ("+오픈채팅", [.red, .blue], [:]),
        ("+등록한 방", [.red, .blue, .yellow], [:]), ("멘션", [.red], [.red: .mention]), ("답장", [.red, .blue], [.blue: .reply]),
    ]
    private let zoom: CGFloat = 1.5

    var body: some View {
        VStack(spacing: 6) {
            ForEach([true, false], id: \.self) { dark in
                HStack(spacing: 0) {
                    ForEach(cases.indices, id: \.self) { i in
                        let img = StatusIcon.snapshot(badges: cases[i].1, marks: cases[i].2.filter { $0.value == .mention ? mentionMark : replyMark }, style: style, ring: ring, showBubble: showBubble, dark: dark)
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: img.size.width * zoom, height: img.size.height * zoom)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 22 * zoom + 8)
                .background(dark ? Color(red: 0.16, green: 0.30, blue: 0.46) : Color(red: 0.62, green: 0.84, blue: 0.97),
                            in: RoundedRectangle(cornerRadius: 6))
            }
            HStack(spacing: 0) {
                ForEach(cases.indices, id: \.self) { i in
                    Text(cases[i].0).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// 채팅방 선택 시트: 검색 + 체크
private struct RoomPicker: View {
    @State var selected: Set<String>
    let done: ([RoomInfo]?) -> Void     // nil = 취소
    @State private var rooms: [RoomInfo] = []
    @State private var query = ""
    @State private var loading = true
    @State private var error: String?

    private var filtered: [RoomInfo] {
        query.isEmpty ? rooms : rooms.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("채팅방 검색", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            Divider()
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                Text(error).foregroundStyle(.secondary).padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { r in
                    let id = String(r.chatId)
                    Toggle(isOn: Binding(get: { selected.contains(id) },
                                         set: { on in if on { selected.insert(id) } else { selected.remove(id) } })) {
                        HStack(spacing: 6) {
                            Text(r.name).lineLimit(1)
                            if r.isOpenChat {
                                Text("오픈채팅").font(.caption2).padding(.horizontal, 4)
                                    .background(Color(NBadge.blue.fill(dark: false)).opacity(0.2), in: Capsule())
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Divider()
            HStack {
                Text("\(selected.count)개 선택").foregroundStyle(.secondary)
                Spacer()
                Button("취소") { done(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("완료") { done(rooms.filter { selected.contains(String($0.chatId)) }) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 400, height: 480)
        .onAppear {
            guard let app = NSApp.delegate as? AppDelegate else { return }
            app.loadAllRooms { result in
                loading = false
                switch result {
                case .success(let r): rooms = r
                case .failure(let e): error = "채팅방 목록을 불러오지 못했습니다: \(e)"
                }
            }
        }
    }
}

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        w.title = "KakaoMenu 설정"
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        super.init(window: w)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// 디버그: 설정의 아이콘 미리보기를 PNG 로 (KakaoMenu --render-preview <path>)
@MainActor func renderIconPreview(to path: String) {
    let view = VStack(spacing: 12) {
        IconPreview(style: .triangle, ring: .shade, showBubble: true)
        IconPreview(style: .triangle, ring: .shade, showBubble: false)
    }.padding().frame(width: 420).background(Color(white: 0.2))
    let r = ImageRenderer(content: view)
    r.scale = 2
    if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
