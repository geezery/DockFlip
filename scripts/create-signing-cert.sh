#!/bin/sh
# Creates a self-signed code-signing certificate in the login keychain.
#
# Why: macOS ties Accessibility and Screen Recording permissions to an app's
# signature. Ad-hoc signatures change with every build, so permissions would be
# lost on every rebuild or update. A stable self-signed certificate fixes that
# without an Apple account.
#
# Runs once; does nothing if the certificate already exists. macOS asks for your
# login password once, to trust the certificate for code signing.

set -eu

NAME="${1:-Plinth Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
    exit 0
fi

echo "Creating code-signing certificate \"$NAME\" (one-time)…"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cfg" <<EOF
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[ dn ]
CN = $NAME

[ ext ]
basicConstraints = critical, CA:false
keyUsage         = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# /usr/bin/openssl is LibreSSL on macOS; its PKCS#12 output imports cleanly.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cfg" >/dev/null 2>&1

/usr/bin/openssl pkcs12 -export -name "$NAME" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -passout pass:plinth >/dev/null 2>&1

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P plinth -T /usr/bin/codesign >/dev/null

# Trust the certificate for code signing (user domain; asks for your password).
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
    echo "Done: \"$NAME\" is ready."
else
    echo "error: the certificate was created but is not valid for code signing." >&2
    exit 1
fi
