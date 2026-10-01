// KakaoMenu — 카카오톡 메뉴바 메뉴(열기/모두 읽음 처리/잠금모드/로그아웃/종료)를 그대로 제공하는 wrapper.
// 실제 동작은 KakaoTalk 의 앱 메뉴(카카오톡 ▸ ...) 항목을 접근성(AX) API 로 눌러서 수행한다.
import Cocoa
import ApplicationServices

let kakaoBundleID = "com.kakao.KakaoTalkMac"

// MARK: - KakaoTalk 제어

enum Kakao {
    // 앱 메뉴 항목 제목(ko/en/ja). 바이너리의 Appmenu_KakaoTalk_* 로컬라이즈 문자열과 동일.
    static let readAllTitles = ["모두 읽음 처리", "Read All", "全て既読"]
    static let lockTitles    = ["잠금모드", "Lock mode", "ロックモード"]
    static let logoutTitles  = ["로그아웃", "Log out", "ログアウト"]

    static var app: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: kakaoBundleID).first
    }

    static let openTitles    = ["카카오톡 열기", "Open KakaoTalk", "KakaoTalkを開く"]

    /// 실행 중이면 카카오톡 메뉴바 아이콘 메뉴의 '카카오톡 열기'를 눌러 창을 띄우고,
    /// 꺼져 있거나 그 항목을 못 찾으면 앱을 open 한다.
    static func open() {
        if app != nil, AXIsProcessTrusted(), let item = statusMenuOpenItem(),
           AXUIElementPerformAction(item, kAXPressAction as CFString) == .success {
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: kakaoBundleID) else {
            alert("카카오톡을 찾을 수 없습니다."); return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg)
    }

    /// 상태 아이템 메뉴의 '카카오톡 열기'. 제목이 다른 언어면 메뉴의 첫 항목(항상 '열기')을 쓴다.
    private static func statusMenuOpenItem() -> AXUIElement? {
        guard let pid = app?.processIdentifier,
              let extras: AXUIElement = AXUIElementCreateApplication(pid).attr("AXExtrasMenuBar") else { return nil }
        if let hit = find(in: extras, titles: Set(openTitles), depth: 0) { return hit }
        return extras.children.first?.children.first?.children.first { $0.role == kAXMenuItemRole }
    }

    static func quit() { app?.terminate() }

    /// 제목이 일치하는 메뉴 항목. 카카오톡 상태 아이템(메뉴바 아이콘) 메뉴를 먼저 보고,
    /// 없으면 앱 메뉴(카카오톡 ▸ …)를 본다. '모두 읽음 처리'는 상태 아이템 메뉴에만 있다.
    /// Apple 메뉴('oein 로그아웃' 등)와 섞이지 않게 앱 메뉴는 두 번째 메뉴바 항목만 검색.
    static func menuItem(_ titles: [String]) -> AXUIElement? {
        guard let pid = app?.processIdentifier else { return nil }
        let root = AXUIElementCreateApplication(pid)
        let set = Set(titles)
        if let extras: AXUIElement = root.attr("AXExtrasMenuBar"), let hit = find(in: extras, titles: set, depth: 0) {
            return hit
        }
        if let bar: AXUIElement = root.attr(kAXMenuBarAttribute) {
            let items = bar.children
            if items.count > 1, let hit = find(in: items[1], titles: set, depth: 0) { return hit }
        }
        return nil
    }

    private static func find(in el: AXUIElement, titles: Set<String>, depth: Int) -> AXUIElement? {
        if depth > 4 { return nil }
        for child in el.children {
            if child.role == kAXMenuItemRole, let t: String = child.attr(kAXTitleAttribute), titles.contains(t) {
                return child
            }
            if let hit = find(in: child, titles: titles, depth: depth + 1) { return hit }
        }
        return nil
    }

    static func isEnabled(_ titles: [String]) -> Bool {
        guard let item = menuItem(titles) else { return false }
        return (item.attr(kAXEnabledAttribute) as Bool?) ?? false
    }

    static func press(_ titles: [String]) {
        guard AXIsProcessTrusted() else { Permission.request(); return }
        guard app != nil else { alert("카카오톡이 실행 중이 아닙니다."); return }
        guard let item = menuItem(titles) else { alert("카카오톡 메뉴에서 '\(titles[0])' 항목을 찾지 못했습니다."); return }
        let err = AXUIElementPerformAction(item, kAXPressAction as CFString)
        if err != .success { alert("'\(titles[0])' 실행 실패 (AXError \(err.rawValue))") }
    }

    /// Dock 아이콘 배지(안 읽은 메시지 수). Dock 에 카카오톡이 없으면 nil.
    static func dockBadge() -> String? {
        guard AXIsProcessTrusted(), app != nil,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }
        let kakaoURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: kakaoBundleID)?.standardizedFileURL
        for list in AXUIElementCreateApplication(dock.processIdentifier).children {
            for item in list.children {
                guard let url: URL = item.attr(kAXURLAttribute), url.standardizedFileURL == kakaoURL else { continue }
                let label: String? = item.attr("AXStatusLabel")
                return (label?.isEmpty ?? true) ? nil : label
            }
        }
        return nil
    }
}

// MARK: - 접근성 권한

enum Permission {
    /// 카카오톡 컨테이너(다른 앱 데이터) 읽기 가능 여부
    static var hasContainerAccess: Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: KakaoKey.appSupport.path)) != nil
    }

    /// 컨테이너 파일을 직접 열어 TCC(다른 앱 데이터 접근) 요청 창을 띄운다.
    /// 이미 거부됐으면 창이 안 뜨므로 전체 디스크 접근 설정을 연다.
    static func requestContainerAccess(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global().async {
            let targets = [KakaoKey.appSupport.path,
                           KakaoKey.appSupport.deletingLastPathComponent().deletingLastPathComponent()
                               .appendingPathComponent("Preferences/com.kakao.KakaoTalkMac.plist").path]
            for t in targets {
                let fd = open(t, O_RDONLY)
                if fd >= 0 { close(fd) }
            }
            let ok = hasContainerAccess
            DispatchQueue.main.async {
                if !ok {
                    NSApp.activate(ignoringOtherApps: true)
                    let a = NSAlert()
                    a.messageText = "카카오톡 데이터 접근 권한이 필요합니다"
                    a.informativeText = "안 읽은 메시지를 읽으려면 카카오톡 컨테이너에 접근해야 합니다.\n"
                        + "시스템 설정 ▸ 개인정보 보호 및 보안 ▸ 전체 디스크 접근 권한에서 KakaoMenu 를 켜 주세요."
                    a.addButton(withTitle: "설정 열기")
                    a.addButton(withTitle: "취소")
                    if a.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                }
                completion(ok)
            }
        }
    }

    static func request() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}

// MARK: - AX 헬퍼

extension AXUIElement {
    func attr<T>(_ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &v) == .success else { return nil }
        return v as? T
    }
    var children: [AXUIElement] { attr(kAXChildrenAttribute) ?? [] }
    var role: String? { attr(kAXRoleAttribute) }
}

/// 디버그: 카카오톡 메뉴바/상태 메뉴 AX 트리를 파일로 덤프 (open build/KakaoMenu.app --args --dump <path>)
func dumpMenus(to path: String) {
    var out = "trusted=\(AXIsProcessTrusted())\n"
    func walk(_ el: AXUIElement, _ depth: Int) {
        if depth > 5 { return }
        let t: String = el.attr(kAXTitleAttribute) ?? ""
        let d: String = el.attr(kAXDescriptionAttribute) ?? ""
        let en: Bool? = el.attr(kAXEnabledAttribute)
        out += String(repeating: "  ", count: depth) + "\(el.role ?? "?") title=\(t) desc=\(d) enabled=\(en.map(String.init) ?? "-")\n"
        for c in el.children { walk(c, depth + 1) }
    }
    if let pid = Kakao.app?.processIdentifier {
        let root = AXUIElementCreateApplication(pid)
        out += "== menubar\n"; if let b: AXUIElement = root.attr(kAXMenuBarAttribute) { walk(b, 0) }
        out += "== extras\n"; if let b: AXUIElement = root.attr("AXExtrasMenuBar") { walk(b, 0) }
        if let b: AXUIElement = root.attr("AXExtrasMenuBar") {
            for it in b.children {
                var pos: CFTypeRef?, size: CFTypeRef?
                AXUIElementCopyAttributeValue(it, kAXPositionAttribute as CFString, &pos)
                AXUIElementCopyAttributeValue(it, kAXSizeAttribute as CFString, &size)
                var p = CGPoint.zero, sz = CGSize.zero
                if let pos { AXValueGetValue(pos as! AXValue, .cgPoint, &p) }
                if let size { AXValueGetValue(size as! AXValue, .cgSize, &sz) }
                out += "kakao status item frame: \(p) \(sz)\n"
            }
        }
    }
    try? out.write(toFile: path, atomically: true, encoding: .utf8)
}

func alert(_ msg: String) {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.messageText = "KakaoMenu"
    a.informativeText = msg
    a.runModal()
}

// MARK: - 메뉴바

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var permissionItem: NSMenuItem!
    private var dataPermissionItem: NSMenuItem!
    private var readAllItem: NSMenuItem!
    private var lockItem: NSMenuItem!
    private var logoutItem: NSMenuItem!
    private var quitItem: NSMenuItem!
    private var dockBadge: String?      // DB 를 못 열었을 때의 폴백

    // 안 읽은 채팅 (라이브 DB)
    private let dbQueue = DispatchQueue(label: "kakao.db")
    private var store: KakaoStore?
    private var storeError: String?
    private var poller: DispatchSourceTimer?
    private var lastStamp: [Int64] = []
    private var unread: [UnreadRoom] = []

    func applicationDidFinishLaunching(_ note: Notification) {
        if let i = CommandLine.arguments.firstIndex(of: "--dump"), i + 1 < CommandLine.arguments.count {
            dumpMenus(to: CommandLine.arguments[i + 1]); exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--diag"), i + 1 < CommandLine.arguments.count {
            var out = "dir=\(KakaoKey.appSupport.path)\n"
            let fd = open(KakaoKey.appSupport.path, O_RDONLY); out += "open fd=\(fd) errno=\(errno)\n"; if fd >= 0 { close(fd) }
            do { out += "list ok: \(try FileManager.default.contentsOfDirectory(atPath: KakaoKey.appSupport.path).count)\n" }
            catch { out += "list error: \(error)\n" }
            out += "db=\(KakaoKey.encryptedDBPath()?.path ?? "nil")\n"
            try? out.write(toFile: CommandLine.arguments[i + 1], atomically: true, encoding: .utf8); exit(0)
        }
        Prefs.registerDefaults()
        buildMenu()
        updateIcon()
        // 설정(등록한 방·배치 등) 변경 즉시 반영
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateIcon()
        }
        if !AXIsProcessTrusted() { Permission.request() }
        startStore()
        // 카카오톡 실행/종료 시 아이콘(흐림) 갱신
        for n in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: n, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if app?.bundleIdentifier == kakaoBundleID { self?.updateIcon() }
            }
        }
        startPolling()
        // 디버그: 실행하자마자 설정 창 (KakaoMenu --open-settings)
        if CommandLine.arguments.contains("--open-settings") { openSettings() }
    }

    // MARK: 안 읽은 채팅

    func startStore() {
        dbQueue.async { [weak self] in
            do {
                let s = try KakaoStore()
                DispatchQueue.main.async { self?.store = s; self?.storeError = nil; self?.refreshUnread() }
            } catch {
                let msg = Permission.hasContainerAccess ? "\(error)" : "카카오톡 데이터 접근 권한 없음"
                DispatchQueue.main.async { self?.storeError = msg; self?.refreshUnread() }
            }
        }
    }

    /// 0.2초마다 DB·WAL 파일 stat 을 확인해 바뀌었을 때만 다시 조회 (읽음 처리 즉시 반영).
    /// DB 를 못 열었으면 2초마다 Dock 배지로 폴백.
    private func startPolling() {
        let t = DispatchSource.makeTimerSource(queue: dbQueue)
        var tick = 0
        t.schedule(deadline: .now() + 0.2, repeating: 0.2, leeway: .milliseconds(30))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            tick += 1
            guard let store = self.store else {
                if tick % 10 == 0 { DispatchQueue.main.async { self.refreshBadge() } }
                return
            }
            let stamp = store.changeStamp()
            guard stamp != self.lastStamp else { return }
            self.lastStamp = stamp
            self.queryUnread(store)
        }
        t.resume()
        poller = t
    }

    /// 즉시 다시 조회 (스토어 준비 직후 등)
    private func refreshUnread() {
        guard let store else { refreshBadge(); return }
        dbQueue.async { [weak self] in self?.queryUnread(store) }
    }

    /// dbQueue 에서 호출
    private func queryUnread(_ store: KakaoStore) {
        let rooms = (try? store.unreadRooms()) ?? []
        DispatchQueue.main.async {
            self.unread = rooms
            self.updateIcon()
        }
    }

    private func item(_ title: String, _ action: Selector?) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        return it
    }

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        permissionItem = item("접근성 권한 허용 필요…", #selector(askPermission))
        menu.addItem(permissionItem)
        dataPermissionItem = item("카카오톡 데이터 접근 권한 요청…", #selector(askDataPermission))
        menu.addItem(dataPermissionItem)

        menu.addItem(item("카카오톡 열기", #selector(openKakao)))
        menu.addItem(.separator())
        readAllItem = item("모두 읽음 처리", #selector(readAll))
        menu.addItem(readAllItem)
        menu.addItem(.separator())
        lockItem = item("잠금모드", #selector(lock))
        menu.addItem(lockItem)
        menu.addItem(.separator())
        logoutItem = item("로그아웃", #selector(logout))
        menu.addItem(logoutItem)
        menu.addItem(.separator())
        quitItem = item("종료", #selector(quitKakao))
        menu.addItem(quitItem)
        menu.addItem(.separator())
        let settings = item("설정…", #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        let quitSelf = item("KakaoMenu 종료", #selector(quitSelf))
        quitSelf.keyEquivalent = "q"
        menu.addItem(quitSelf)

        status.menu = menu
    }

    // 메뉴가 열릴 때마다 카카오톡 쪽 항목 상태를 그대로 반영.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let trusted = AXIsProcessTrusted()
        let running = Kakao.app != nil
        permissionItem.isHidden = trusted
        dataPermissionItem.isHidden = store != nil
        readAllItem.isEnabled = trusted && running && Kakao.isEnabled(Kakao.readAllTitles)
        lockItem.isEnabled    = trusted && running && Kakao.isEnabled(Kakao.lockTitles)
        logoutItem.isEnabled  = trusted && running && Kakao.isEnabled(Kakao.logoutTitles)
        quitItem.isEnabled    = running
    }

    /// DB 를 못 열었을 때의 폴백: Dock 배지 (종류 구분 불가 → 빨강)
    private func refreshBadge() {
        let badge = Kakao.dockBadge()
        if badge != dockBadge { dockBadge = badge; updateIcon() }
    }

    /// 안 읽은 방 분류에 따라 N 배지(🔴 일반 · 🔵 오픈채팅 · 🟡 등록한 방)와 숫자를 갱신
    private func updateIcon() {
        guard let button = status.button else { return }
        let badges: [NBadge]
        let marks: [NBadge: BadgeMark]
        let total: Int?
        if store != nil {
            let state = Prefs.iconState(for: unread)
            (badges, marks, total) = (state.badges, state.marks, state.total)
        } else {
            badges = dockBadge == nil ? [] : [.red]
            marks = [:]
            total = dockBadge.flatMap { Int($0) }
        }
        let image = StatusIcon.image(badges: badges, marks: marks, style: Prefs.style, ring: Prefs.ring,
                                     dimmed: Kakao.app == nil, showBubble: Prefs.bubble)
        let showCount = UserDefaults.standard.bool(forKey: Prefs.showUnreadCount)
        let title = showCount ? (total.flatMap { $0 > 0 ? " \($0 > 999 ? "999+" : String($0))" : nil } ?? "") : ""
        // 같은 상태면 다시 그리지 않음
        let key = "\(badges)|\(NBadge.allCases.map { marks[$0]?.rawValue ?? 0 })|\(Prefs.style)|\(Prefs.ring)|\(Prefs.bubble)|\(Kakao.app == nil)|\(title)"
        guard key != lastIconKey else { return }
        lastIconKey = key
        button.image = image
        button.title = title
        button.imagePosition = .imageLeading
    }
    private var lastIconKey = ""

    /// 설정 화면의 채팅방 선택용 전체 목록
    func loadAllRooms(_ completion: @escaping (Result<[RoomInfo], Error>) -> Void) {
        guard let store else {
            completion(.failure(SQLCipherError.load(storeError ?? "DB 준비 안 됨"))); return
        }
        dbQueue.async {
            let result = Result { try store.allRooms() }
            DispatchQueue.main.async { completion(result) }
        }
    }

    @objc private func askPermission() { Permission.request() }
    @objc private func askDataPermission() {
        Permission.requestContainerAccess { [weak self] ok in if ok { self?.startStore() } }
    }
    @objc private func openKakao() { Kakao.open() }
    @objc private func readAll() { Kakao.press(Kakao.readAllTitles) }
    @objc private func lock() { Kakao.press(Kakao.lockTitles) }
    @objc private func logout() { Kakao.press(Kakao.logoutTitles) }
    @objc private func quitKakao() { Kakao.quit() }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func quitSelf() { NSApp.terminate(nil) }
}

// CLI: 설정 아이콘 미리보기 (KakaoMenu --render-preview <path>)
if let i = CommandLine.arguments.firstIndex(of: "--render-preview"), i + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated { renderIconPreview(to: CommandLine.arguments[i + 1]) }; exit(0)
}

// CLI: 스타일 비교 시트 (KakaoMenu --compare-icons <path>)
if let i = CommandLine.arguments.firstIndex(of: "--compare-icons"), i + 1 < CommandLine.arguments.count {
    let res = CommandLine.arguments.contains("--2x") ? 2 : 1
    StatusIcon.renderComparison(to: CommandLine.arguments[i + 1], res: res); exit(0)
}

// CLI: DB 변경 감시 (KakaoMenu --watch [초]) — data_version 변화와 안 읽은 수를 시각과 함께 출력
if let i = CommandLine.arguments.firstIndex(of: "--watch") {
    let secs = i + 1 < CommandLine.arguments.count ? Double(CommandLine.arguments[i + 1]) ?? 30 : 30
    do {
        let store = try KakaoStore()
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
        var last: [Int64] = []
        var lastTotal = -1
        let end = Date().addingTimeInterval(secs)
        while Date() < end {
            let v = store.changeStamp()
            if v != last {
                last = v
                let t0 = Date()
                let total = try store.unreadRooms().reduce(0) { $0 + $1.count }
                let dt = Date().timeIntervalSince(t0) * 1000
                print("\(f.string(from: Date()))  WAL 변경 (크기 \(v[5]))  안읽음=\(total)\(total != lastTotal ? " ←" : "")  (조회 \(String(format: "%.1f", dt))ms)")
                lastTotal = total
                fflush(stdout)
            }
            usleep(100_000)
        }
        exit(0)
    } catch { print("오류: \(error)"); exit(1) }
}

// CLI: 안 읽은 채팅 출력 (KakaoMenu --unread)
if CommandLine.arguments.contains("--unread") {
    do {
        let store = try KakaoStore()
        let rooms = try store.unreadRooms()
        Prefs.registerDefaults()
        print("안 읽은 메시지 \(rooms.reduce(0) { $0 + $1.count })개 / \(rooms.count)개 방")
        let state = Prefs.iconState(for: rooms)
        print("켜질 N 배지: \(state.badges.map { "\($0.rawValue)\(state.marks[$0].map { $0 == .mention ? "@" : $0 == .reply ? "↩" : "" } ?? "")" })")
        let ignored = Prefs.ignored
        for r in rooms {
            let tags = [r.muted ? "알림 꺼짐" : nil, ignored.contains(r.chatId) ? "무시" : nil,
                        r.mentioned ? "@멘션" : nil, r.replied ? "↩답장" : nil].compactMap { $0 }
            print("\n[\(r.name)] \(r.count)개\(tags.isEmpty ? "" : " (\(tags.joined(separator: ", ")))")  \(Prefs.kind(of: r).rawValue)\(r.isOpenChat ? " 오픈채팅" : "")  chatId=\(r.chatId)")
            for m in r.messages { print("  \(m.sentAt)  \(m.author): \(m.text)") }
        }
        exit(0)
    } catch {
        FileHandle.standardError.write("오류: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
