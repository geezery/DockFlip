#!/bin/sh
# Creates a self-signed code-signing identity for local builds of Plinth.
#
# Why: macOS ties Accessibility and Screen Recording permissions to an app's
# signature. Ad-hoc signatures change with every build, so permissions would be
# lost on every rebuild. A stable self-signed identity fixes that without an
# Apple account.
#
# The identity lives in its own keychain with a random password stored next to
# it (readable only by you), NOT in the login keychain. On Macs where the login
# keychain password differs from the login password (common on managed Macs),
# codesign would otherwise ask for a keychain password that nothing accepts.
#
# Runs once; does nothing if the identity already exists. macOS asks for your
# login password once, to trust the certificate for code signing.

set -eu

NAME="${1:-Plinth Signing}"
SUPPORT="$HOME/Library/Application Support/Plinth"
KEYCHAIN="$HOME/Library/Keychains/plinth-signing.keychain-db"
PASSFILE="$SUPPORT/signing-keychain-password"

mkdir -p "$SUPPORT"
chmod 700 "$SUPPORT"

if [ -f "$KEYCHAIN" ] && [ -f "$PASSFILE" ]; then
    security unlock-keychain -p "$(cat "$PASSFILE")" "$KEYCHAIN" 2>/dev/null || true
    if security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
        exit 0
    fi
fi

echo "Creating code-signing identity \"$NAME\" in its own keychain (one-time)…"

# Fresh keychain with a random password that never leaves this Mac.
rm -f "$KEYCHAIN"
umask 077
/usr/bin/openssl rand -hex 24 > "$PASSFILE"
chmod 600 "$PASSFILE"
PASS="$(cat "$PASSFILE")"
security create-keychain -p "$PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"          # no auto-lock
security unlock-keychain -p "$PASS" "$KEYCHAIN"

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
# Let codesign use the key without any prompt (needs this keychain's password, which we have).
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KEYCHAIN" >/dev/null

# Make the keychain searchable, keeping the existing search list.
EXISTING="$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/" *$//')"
if ! printf '%s\n' "$EXISTING" | grep -qx "$KEYCHAIN"; then
    # shellcheck disable=SC2086
    security list-keychains -d user -s "$KEYCHAIN" $EXISTING
fi

# Trust the certificate for code signing (user domain; asks for your login password).
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

if security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
    echo "Done: \"$NAME\" is ready."
else
    echo "error: the identity was created but is not valid for code signing." >&2
    exit 1
fi
