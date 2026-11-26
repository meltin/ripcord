#!/bin/sh
# Creates the self-signed code-signing certificate that scripts/build-app.sh signs Ripcord with,
# in the login keychain, once. Signed with the same certificate, every build is the same app to
# macOS, so permissions such as Accessibility survive a rebuild or an update; an ad-hoc build is
# a new app each time. macOS asks for your password once, to trust the certificate for code
# signing.
set -eu

name="Ripcord Self-Signed"
keychain="$HOME/Library/Keychains/login.keychain-db"

# Usable: in the keychain with its key, trusted for code signing and not expired.
if security find-identity -v -p codesigning | grep -qF "\"$name\""; then
  echo "\"$name\" is already set up."
  exit 0
fi
# Left untrusted by a run stopped at the password prompt: trust it now.
if security find-certificate -a -c "$name" "$keychain" 2>/dev/null |
  grep -qF "\"labl\"<blob>=\"$name\""; then
  cert="$(mktemp)"
  trap 'rm -f "$cert"' EXIT
  security find-certificate -c "$name" -p "$keychain" >"$cert"
  security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$cert"
  if security find-identity -v -p codesigning | grep -qF "\"$name\""; then
    echo "Trusted \"$name\" for code signing."
    exit 0
  fi
  echo "\"$name\" is in the login keychain but can't sign (expired, or its key is missing)." >&2
  echo "Delete it in Keychain Access, then run this again." >&2
  exit 1
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
# -name labels the key, which macOS's prompts name; it'd be "identity" otherwise.
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -name "$name" \
  -out "$work/identity.p12" -passout "pass:$password"

# -T lets codesign use the key. If macOS still asks on the first build ("codesign wants to
# access key"), choose Always Allow: it lets only codesign use this one key.
security import "$work/identity.p12" -k "$keychain" -P "$password" -T /usr/bin/codesign >/dev/null
# codesign only signs with a certificate trusted for code signing; this is the password prompt.
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$work/cert.pem"

echo "Created \"$name\". scripts/build-app.sh now signs with it."
echo "Once more: remove Ripcord under Privacy & Security > Accessibility (or run"
echo "tccutil reset Accessibility io.github.meltin.ripcord) and grant it to the next build."
echo "Later builds keep it."
