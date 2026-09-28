#!/bin/zsh
# 로컬 코드사이닝용 자체 서명 인증서를 로그인 키체인에 한 번만 만든다.
# 같은 인증서로 계속 서명해야 재빌드해도 접근성(TCC) 권한이 유지된다.
set -euo pipefail
NAME="${SIGN_IDENTITY:-KakaoMenu Local Signing}"
KC="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KC" >/dev/null 2>&1; then
  echo "이미 있음: $NAME"; exit 0
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cfg" <<CFG
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CFG
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cfg" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -out "$TMP/id.p12" -passout pass:kakaomenu 2>/dev/null
security import "$TMP/id.p12" -k "$KC" -P kakaomenu -T /usr/bin/codesign -f pkcs12
echo "생성됨: $NAME"
