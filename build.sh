#!/bin/zsh
# KakaoMenu.app 빌드 + 고정 인증서로 코드사인 (재빌드해도 접근성 권한 유지)
#   ./build.sh           → build/KakaoMenu.app
#   ./build.sh install   → 빌드 후 /Applications/KakaoMenu.app 로 설치하고 실행
set -euo pipefail
cd "${0:A:h}"
IDENTITY="${SIGN_IDENTITY:-KakaoMenu Local Signing}"
APP=build/KakaoMenu.app

./make-cert.sh >/dev/null
[[ -f AppIcon.icns ]] || swift tools/make-icon.swift AppIcon.icns
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
swiftc -O -target arm64-apple-macos13.0 -o "$APP/Contents/MacOS/KakaoMenu" *.swift
codesign --force --timestamp=none -s "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
codesign -d -r- "$APP" 2>&1 | grep designated
echo "빌드 완료: $PWD/$APP"

if [[ "${1:-}" == "install" ]]; then
  DEST=/Applications/KakaoMenu.app
  pkill -x KakaoMenu 2>/dev/null && sleep 0.5 || true
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  codesign --verify --strict "$DEST"
  touch "$DEST"   # Finder/Launchpad 아이콘 캐시 갱신
  open "$DEST"
  echo "설치 완료: $DEST"
fi
