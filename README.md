# KakaoMenu

카카오톡(macOS) 메뉴바 메뉴(열기 / 모두 읽음 처리 / 잠금모드 / 로그아웃 / 종료)를 그대로 제공하면서,
안 읽은 메시지가 있는 방의 종류에 따라 🔴🔵🟡 N 배지를 보여주는 메뉴바 앱.

> [!WARNING]
> **비공식 프로젝트입니다.** Kakao Corp.가 만들거나 승인·후원한 프로젝트가 아니며, 카카오톡 업데이트로 언제든 동작이 중단될 수 있습니다.
> 사용으로 생기는 모든 결과(계정 제한, 데이터 손실, 약관 위반 등)의 책임은 전적으로 사용자에게 있습니다.

## 기능

각 동작은 KakaoTalk 앱 메뉴(카카오톡 ▸ …) 항목을 접근성 API 로 눌러서 수행한다.
메뉴 하단 `설정…`(⌘,) / `KakaoMenu 종료`(⌘Q).

**메뉴바 아이콘** — 설치된 카카오톡 앱의 에셋(Assets.car 의 MenuIcon/DarkMenuIcon/Loggedout…)을 실행 시 불러와 그린다. N 배지는 `MenuIconWithNew` 의 빨간 배지 모양을 마스크로 뽑아 빨강/파랑/노랑으로 칠함. 배경화면 색에 상관없이 보이도록 N 은 뚫지 않고 채움(흰색, 노랑 배지는 검정) + 진한 배지색 + 옅은 그림자 테두리.
'말풍선 표시' 토글: 끄면 알림이 있을 때 같은 배치의 N 배지만 — 배지 영역만 잘라 높이 21pt(최대 1.45배)로 확대, 확대 시 N 은 벡터로. 알림이 없으면 말풍선. 설정 창에 현재 설정의 아이콘 미리보기(어두운/밝은 메뉴바 × 알림 없음·🔴·🔴🔵·🔴🔵🟡).
배치(설정에서 선택): 삼각형으로 모으기(기본, 1개일 땐 원본 그대로, 지름 8pt 배지 — 아래 오른쪽 빨강·왼쪽 파랑, 위 노랑) / 점으로 표시 / 바깥 링 / 위로 살짝 겹치기 / 한 배지 나눠 칠하기 / 가로로 겹치기 / 뒤로 겹치기 / 오른쪽에 세로로 쌓기. 어두운 메뉴바 테두리: 어둡게(기본)/흰색/없음.
1x 화면의 작은 배지는 픽셀 격자 4×4 N 을 직접 찍는다. 비교 시트: `KakaoMenu --compare-icons out.png [--2x]` (카카오 원본 에셋이 들어가므로 로컬에서만 생성).

**N 배지 조건** — 안 읽은 메시지가 있는 방의 종류로 켠다:
🔴 일반 채팅 · 🔵 오픈채팅(`NTChatRoom.linkId != 0`) · 🟡 설정에서 등록한 채팅방(오픈채팅이어도 노랑만).
알림 꺼진 방 포함 여부는 설정(기본 포함).

**설정 창** — 권한(손쉬운 사용 / 카카오톡 데이터) 상태·요청, 로그인 시 자동 실행, 노란 N 채팅방 등록(검색해서 체크), 알림 꺼진 방 포함, 안 읽은 수 표시, 배지 배치/테두리.
카카오톡 데이터 권한: 컨테이너 파일을 직접 열어 TCC 요청을 유도하고, 거부 상태면 '전체 디스크 접근 권한' 설정을 연다.

**안 읽은 채팅(실시간)** — 기기에 저장된 카카오톡 로컬 DB 를 읽기전용으로 열어 조회한다.
- 안 읽은 수 = `NTChatRoom.countOfNewMessage`, 안 읽은 메시지 = 그 방의 `logId > lastSeenLogId`(내 메시지·내부 feed 제외).
- 0.2초마다 DB·`-wal` 파일 stat(수정 시각·크기)을 확인해 바뀌었을 때만 재조회(조회 2~4ms). 카카오톡 SQLCipher 는 SQLite 3.8.4 라 `PRAGMA data_version` 이 없고, FSEvents 는 WAL 쓰기를 놓치거나 늦어서 이 방식을 쓴다. `KakaoMenu --watch [초]` 로 변경 감지를 확인. 아이콘 옆 숫자 = 전체 안 읽은 수(설정에서 켤 때). 메뉴에는 안 읽은 목록을 띄우지 않는다(원본 메뉴와 동일).
- 첫 실행 시 계정 식별 정보를 로컬에서 계산(~15초)해 UserDefaults 에 캐시한다. 어떤 데이터도 외부로 전송하지 않는다.
- CLI: `build/KakaoMenu.app/Contents/MacOS/KakaoMenu --unread`
- SQLCipher 는 설치된 카카오톡 앱의 `SQLCipher.framework` 를 dlopen 한다. 다른 팀 서명 프레임워크라 hardened runtime 은 끈다.

## 설치 (릴리스)

[Releases](../../releases) 에서 `KakaoMenu.zip` 을 받는다. 공증(notarization)되지 않은 자체 서명 앱이므로:

    shasum -a 256 KakaoMenu.zip                      # 릴리스에 적힌 SHA-256 과 일치하는지 확인
    unzip KakaoMenu.zip && mv KakaoMenu.app /Applications/
    xattr -dr com.apple.quarantine /Applications/KakaoMenu.app

신뢰할 수 없으면 아래처럼 직접 빌드해서 쓰는 걸 권장한다.

## 빌드 / 설치

요구사항: Apple Silicon Mac, macOS 13+, Xcode Command Line Tools, `/Applications/KakaoTalk.app` 설치.

    ./make-cert.sh             # (최초 1회) 로컬 코드사이닝 인증서 생성
    ./build.sh install         # 빌드 + 코드사인 + /Applications/KakaoMenu.app 설치·실행
    ./build.sh                 # 빌드만 → build/KakaoMenu.app

- 처음 실행 시 손쉬운 사용 권한과 카카오톡 데이터(또는 전체 디스크 접근) 권한 허용 필요.
- `make-cert.sh` 가 로그인 키체인에 자체 서명 인증서("KakaoMenu Local Signing")를 한 번 만들고,
  항상 그 인증서로 서명한다 → 재빌드해도 권한이 유지된다(ad-hoc 서명은 빌드마다 권한 초기화).
- 앱 아이콘은 `tools/make-icon.swift` 로 생성(AppIcon.icns, 없으면 빌드 시 자동 생성).

## 파일

KakaoKey.swift(키 도출) · SQLCipher.swift(카카오톡 SQLCipher.framework dlopen) · KakaoStore.swift(조회/렌더/감시) ·
StatusIcon.swift(아이콘) · Settings.swift(설정) · main.swift(메뉴바)

## 면책 / 비제휴

- 이 프로젝트는 카카오톡 macOS 앱과의 상호운용성 및 **본인 기기에 저장된 본인 데이터 열람**을 위한 개인 프로젝트입니다.
  타인의 기기·계정·데이터에 사용하지 마세요.
- KakaoTalk, 카카오톡 및 관련 명칭·상표·아이콘·애플리케이션 자산의 권리는 각 권리자에게 있습니다.
- 저장소와 릴리스에는 Kakao 실행 파일, 앱 번들, 프레임워크, 원본 아이콘, `Assets.car` 또는 거기서 파생된 이미지를 **포함하거나 재배포하지 않습니다.**
  메뉴바 아이콘과 SQLCipher 는 사용자의 Mac 에 설치된 공식 카카오톡 앱에서 실행 시 로컬로 불러옵니다.
- 이 소프트웨어는 어떠한 보증도 없이 "있는 그대로" 제공되며, 관련 법이 허용하는 범위에서 작성자는 어떠한 손해에도 책임지지 않습니다.
- 이 문서의 내용은 법률 자문이 아닙니다.

## 라이선스

[WTFPL](LICENSE) — 이 프로젝트가 직접 작성한 소스 코드에만 적용됩니다. 카카오 및 제3자의 자산에는 적용되지 않습니다.
