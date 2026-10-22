#!/bin/sh
# Creates the identity that signs DockFlip's public releases, and hands it to
# GitHub as the RELEASE_IDENTITY secret. Run it once, on a Mac or in Git Bash
# on Windows:
#
#   ./scripts/make-release-identity.sh
#
# Why: macOS ties a user's Accessibility permission to the app's signature.
# Every release must be signed with the same identity, or users would have to
# allow DockFlip again after each update. Without an Apple account the identity
# is self-signed; it lives only in the backup file and in GitHub's secrets.
#
# KEEP THE BACKUP (and a copy in your password manager). If it is lost, the
# next release is signed with a new identity and every user has to allow
# DockFlip once more.

set -eu

NAME="DockFlip Release"
REPO="geezery/DockFlip"
SECRETS_URL="https://github.com/$REPO/settings/secrets/actions/new"

case "$(uname -s)" in
    Darwin) PLATFORM=mac;     SUPPORT="$HOME/Library/Application Support/DockFlip" ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM=windows; SUPPORT="$HOME/.dockflip" ;;
    *)      PLATFORM=other;   SUPPORT="$HOME/.dockflip" ;;
esac
BACKUP="$SUPPORT/release-identity.p12"

# macOS ships LibreSSL at /usr/bin/openssl; elsewhere use the one on PATH.
OPENSSL=openssl
[ -x /usr/bin/openssl ] && OPENSSL=/usr/bin/openssl
command -v "$OPENSSL" >/dev/null 2>&1 || { echo "error: openssl not found (on Windows, run this in Git Bash)." >&2; exit 1; }

mkdir -p "$SUPPORT"
chmod 700 "$SUPPORT" 2>/dev/null || true
umask 077

if [ -f "$BACKUP" ]; then
    echo "Using the existing release identity: $BACKUP"
else
    echo "Creating the release identity \"$NAME\" (one-time)…"
    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT
    cat > "$WORK/cert.cfg" <<CFG
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
CFG
    # 20 years: the identity has to outlive many releases.
    "$OPENSSL" req -x509 -newkey rsa:3072 -nodes -days 7300 \
        -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cfg" >/dev/null 2>&1
    # macOS's keychain imports PKCS#12 files with 3DES encryption most reliably;
    # OpenSSL 3 defaults to AES, so ask for 3DES explicitly. The file is
    # protected by GitHub's secret storage; its own password is fixed.
    PBE=""
    "$OPENSSL" version | grep -q "^OpenSSL 3" && PBE="-keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1"
    # shellcheck disable=SC2086
    "$OPENSSL" pkcs12 -export -name "$NAME" $PBE \
        -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
        -out "$BACKUP" -passout pass:dockflip >/dev/null 2>&1
    chmod 600 "$BACKUP" 2>/dev/null || true
    echo "Backup saved: $BACKUP"
    echo "Put a copy in your password manager too."
fi

ENCODED="$(base64 < "$BACKUP" | tr -d '\r\n')"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    printf '%s' "$ENCODED" | gh secret set RELEASE_IDENTITY --repo "$REPO"
    echo "Done: the RELEASE_IDENTITY secret is set on $REPO."
    exit 0
fi

case "$PLATFORM" in
    mac)     printf '%s' "$ENCODED" | pbcopy;   open "$SECRETS_URL" ;;
    windows) printf '%s' "$ENCODED" | clip.exe; cmd.exe //c start "" "$SECRETS_URL" 2>/dev/null || true ;;
    *)       printf '%s\n' "$ENCODED" > "$SUPPORT/release-identity.b64"
             echo "Copy the contents of $SUPPORT/release-identity.b64 and open $SECRETS_URL" ;;
esac
echo
echo "The identity is on your clipboard. On the GitHub page that opened:"
echo "  Name:   RELEASE_IDENTITY"
echo "  Secret: paste it (Ctrl+V / ⌘V)"
echo "  then press \"Add secret\"."
