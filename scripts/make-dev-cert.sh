#!/bin/zsh
# Creates a self-signed code signing identity so TCC grants survive rebuilds.
# Ad-hoc signing names the app by cdhash, which changes on every build; a stable
# certificate makes the designated requirement identifier+certificate instead.
set -euo pipefail
name=${1:-Understage Dev}
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$name\""; then
  echo "$name already installed"
  exit 0
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$work/key.pem" -out "$work/cert.pem" \
  -subj "/CN=$name" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1
openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
  -out "$work/id.p12" -passout pass:understage -legacy >/dev/null 2>&1
security import "$work/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P understage \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security add-trusted-cert -r trustRoot -p codeSign \
  -k "$HOME/Library/Keychains/login.keychain-db" "$work/cert.pem" 2>/dev/null ||
  echo "warning: could not auto-trust; run Keychain Access > $name > Trust > Code Signing: Always Trust" >&2
security find-identity -v -p codesigning | grep "$name"
echo "Use it with: CODESIGN_IDENTITY=\"$name\" make no-xcode"
