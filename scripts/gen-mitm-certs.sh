#!/bin/zsh
# Generates a dev CA + leaf for MITMing the game's TLS. Dev/spike only — a
# shipped product must generate a unique CA per install, not bundle a key.
set -euo pipefail
out=${0:A:h:h}/Sources/SnapCompanionProxy/Resources
mkdir -p "$out"
cd "$(mktemp -d)"

# CA
openssl genrsa -out ca.key 2048 >/dev/null 2>&1
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 \
  -subj "/CN=SnapCompanion Dev CA" -out ca.pem >/dev/null 2>&1

# Leaf for the game's realtime hosts
cat > leaf.ext <<EOF
subjectAltName=DNS:*.nvprod.snapgametech.com,DNS:nvprod.snapgametech.com,DNS:*.snapgametech.com
extendedKeyUsage=serverAuth
EOF
openssl genrsa -out leaf.key 2048 >/dev/null 2>&1
openssl req -new -key leaf.key -subj "/CN=*.nvprod.snapgametech.com" -out leaf.csr >/dev/null 2>&1
openssl x509 -req -in leaf.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
  -days 3650 -sha256 -extfile leaf.ext -out leaf.pem >/dev/null 2>&1

# Bundle for the extension (NIOSSL/BoringSSL uses PEM, not a SecIdentity):
#   leaf-chain.pem = leaf + CA (server cert chain), leaf.key = private key.
# dev-ca.pem is what the app installs into the trust store.
cat leaf.pem ca.pem > "$out/leaf-chain.pem"
cp leaf.key "$out/leaf.key"
cp ca.pem "$out/dev-ca.pem"
echo "wrote dev-ca.pem, leaf-chain.pem, leaf.key to $out"
