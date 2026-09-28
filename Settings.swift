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
    static let includeMuted = "includeMuted"
    static let showBubble = "showBubble"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showUnreadCount: false, badgeStyle: BadgeStyle.triangle.rawValue, badgeRing: RingStyle.shade.rawValue,
            watchedRooms: [String](), watchedRoomNames: [String: String](), includeMuted: true, showBubble: true,
        ])
        // 예전 'N만 표시' 배치 → 가로로 겹치기 + 말풍선 끔
        if UserDefaults.standard.string(forKey: badgeStyle) == "badgesOnly" {
            UserDefaults.standard.set(BadgeStyle.row.rawValue, forKey: badgeStyle)
            UserDefaults.standard.set(false, forKey: showBubble)
        }
    }

    static var watched: Set<Int64> {
        Set((UserDefaults.standard.stringArray(forKey: watchedRooms) ?? []).compactMap { Int64($0) })
    }

    /// 안 읽은 방 → 켤 N 배지 (앞=빨강 → 파랑 → 노랑)
    ///   🟡 등록한 방(오픈채팅이어도 노랑) · 🔵 오픈채팅 · 🔴 그 외 일반 채팅
    static func badges(for rooms: [UnreadRoom]) -> [NBadge] {
        let watched = watched
        let includeMuted = UserDefaults.standard.bool(forKey: includeMuted)
        var on = Set<NBadge>()
        for r in rooms where r.count > 0 {
            if watched.contains(r.chatId) { on.insert(.yellow); continue }
            if r.muted && !includeMuted { continue }
            on.insert(r.isOpenChat ? .blue : .red)
        }
        return NBadge.allCases.filter(on.contains)
    }

    static func kind(of r: UnreadRoom) -> NBadge {
        watched.contains(r.chatId) ? .yellow : (r.isOpenChat ? .blue : .red)
    }
    static var style: BadgeStyle { BadgeStyle(rawValue: UserDefaults.standard.string(forKey: badgeStyle) ?? "") ?? .triangle }
    static var bubble: Bool { UserDefaults.standard.bool(forKey: showBubble) }
    static var ring: RingStyle { RingStyle(rawValue: UserDefaults.standard.string(forKey: badgeRing) ?? "") ?? .shade }
}

private struct SettingsView: View {
    @AppStorage(Prefs.showUnreadCount) private var showUnreadCount = false
    @AppStorage(Prefs.badgeStyle) private var badgeStyle = BadgeStyle.triangle.rawValue
    @AppStorage(Prefs.badgeRing) private var badgeRing = RingStyle.shade.rawValue
    @AppStorage(Prefs.includeMuted) private var includeMuted = true
    @AppStorage(Prefs.showBubble) private var showBubble = true
    @State private var watchedNames: [String: String] = UserDefaults.standard.dictionary(forKey: Prefs.watchedRoomNames) as? [String: String] ?? [:]
    @State private var watchedIds: [String] = UserDefaults.standard.stringArray(forKey: Prefs.watchedRooms) ?? []
    @State private var showPicker = false
    @State private var axTrusted = AXIsProcessTrusted()
    @State private var dataAccess = Permission.hasContainerAccess
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("권한") {
                permissionRow("손쉬운 사용 (카카오톡 메뉴 제어)", granted: axTrusted) { Permission.request() }
                permissionRow("카카오톡 데이터 (안 읽은 메시지)", granted: dataAccess) {
                    Permission.requestContainerAccess { ok in
                        dataAccess = ok
                        if ok { (NSApp.delegate as? AppDelegate)?.startStore() }
                    }
                }
            }
            Section("일반") {
                Toggle("로그인 시 자동 실행", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            }
            Section {
                ForEach(watchedIds, id: \.self) { id in
                    HStack {
                        Circle().fill(Color(NBadge.yellow.fill(dark: false))).frame(width: 8, height: 8)
                        Text(watchedNames[id] ?? id).lineLimit(1)
                        Spacer()
                        Button { removeWatched(id) } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
                if watchedIds.isEmpty {
                    Text("등록한 채팅방이 없습니다").foregroundStyle(.secondary)
                }
                Button("채팅방 추가…") { showPicker = true }
            } header: {
                Text("노란 N — 등록한 채팅방")
            } footer: {
                Text("빨간 N: 일반 채팅 · 파란 N: 오픈채팅 · 노란 N: 등록한 채팅방(오픈채팅이어도 노랑)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("N 배지 조건") {
                Toggle("알림 꺼진 채팅방도 N 표시", isOn: $includeMuted)
            }
            Section("메뉴바 아이콘") {
                IconPreview(style: BadgeStyle(rawValue: badgeStyle) ?? .triangle,
                            ring: RingStyle(rawValue: badgeRing) ?? .shade, showBubble: showBubble)
                Toggle("안 읽은 메시지 수 표시", isOn: $showUnreadCount)
                Toggle("말풍선 표시", isOn: $showBubble)
                if !showBubble {
                    Text("알림이 있으면 N 배지만, 없으면 말풍선을 표시합니다.").font(.caption).foregroundStyle(.secondary)
                }
                Picker("N 배지 배치", selection: $badgeStyle) {
                    ForEach(BadgeStyle.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                Picker("배지 테두리 (어두운 메뉴바)", selection: $badgeRing) {
                    Text("어둡게").tag(RingStyle.shade.rawValue)
                    Text("흰색").tag(RingStyle.white.rawValue)
                    Text("없음").tag(RingStyle.none.rawValue)
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            RoomPicker(selected: Set(watchedIds)) { picked in
                if let picked { setWatched(picked) }
                showPicker = false
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
        .onReceive(tick) { _ in
            axTrusted = AXIsProcessTrusted()
            dataAccess = Permission.hasContainerAccess
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setWatched(_ rooms: [RoomInfo]) {
        watchedIds = rooms.map { String($0.chatId) }
        for r in rooms { watchedNames[String(r.chatId)] = r.name }
        watchedNames = watchedNames.filter { watchedIds.contains($0.key) }
        save()
    }

    private func removeWatched(_ id: String) {
        watchedIds.removeAll { $0 == id }
        watchedNames[id] = nil
        save()
    }

    private func save() {
        UserDefaults.standard.set(watchedNames, forKey: Prefs.watchedRoomNames)
        UserDefaults.standard.set(watchedIds, forKey: Prefs.watchedRooms)
    }

    private func permissionRow(_ title: String, granted: Bool, request: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(title)
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
    private let cases: [(String, [NBadge])] = [("알림 없음", []), ("일반", [.red]), ("+오픈채팅", [.red, .blue]), ("+등록한 방", [.red, .blue, .yellow])]
    private let zoom: CGFloat = 1.5

    var body: some View {
        VStack(spacing: 6) {
            ForEach([true, false], id: \.self) { dark in
                HStack(spacing: 0) {
                    ForEach(cases.indices, id: \.self) { i in
                        let img = StatusIcon.snapshot(badges: cases[i].1, style: style, ring: ring, showBubble: showBubble, dark: dark)
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
        w.styleMask = [.titled, .closable]
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
