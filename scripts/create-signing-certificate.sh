#!/bin/sh
# Creates the self-signed code-signing certificate that scripts/build-app.sh signs Ripcord with,
# in the login keychain, once. Signed with the same certificate, every build is the same app to
# macOS, so permissions such as Accessibility survive a rebuild or an update; an ad-hoc build is
# a new app each time. macOS asks for your password once, to trust the certificate for code
# signing.
set -eu

name="Ripcord Self-Signed"
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$name" "$keychain" >/dev/null 2>&1; then
  echo "\"$name\" is already in the login keychain."
  exit 0
fi

# The private key exists on disk only inside this folder, removed on exit.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat >"$work/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# macOS's LibreSSL, whose PKCS#12 files `security import` reads.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$work/cert.cnf" \
  -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
password="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
  -out "$work/identity.p12" -passout "pass:$password"

# -T lets codesign use the key without asking each build.
security import "$work/identity.p12" -k "$keychain" -P "$password" -T /usr/bin/codesign >/dev/null
# codesign only signs with a certificate trusted for code signing; this is the password prompt.
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$work/cert.pem"

echo "Created \"$name\". scripts/build-app.sh now signs with it."
echo "Grant Accessibility to the next build once more; later builds keep it."
