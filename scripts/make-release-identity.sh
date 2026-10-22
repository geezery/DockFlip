#!/bin/sh
# Creates the identity that signs DockFlip's public releases, and hands it to
# GitHub as the RELEASE_IDENTITY secret. Run it once, on your Mac:
#
#   ./scripts/make-release-identity.sh
#
# Why: macOS ties a user's Accessibility permission to the app's signature.
# Every release must be signed with the same identity, or users would have to
# allow DockFlip again after each update. Without an Apple account the identity
# is self-signed; it lives only here (as a backup) and in GitHub's secrets.
#
# KEEP THE BACKUP. If it is lost, the next release is signed with a new
# identity and every user has to allow DockFlip once more.

set -eu

NAME="DockFlip Release"
REPO="geezery/DockFlip"
SUPPORT="$HOME/Library/Application Support/DockFlip"
BACKUP="$SUPPORT/release-identity.p12"
SECRETS_URL="https://github.com/$REPO/settings/secrets/actions/new"

mkdir -p "$SUPPORT"
chmod 700 "$SUPPORT"
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
    /usr/bin/openssl req -x509 -newkey rsa:3072 -nodes -days 7300 \
        -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cfg" >/dev/null 2>&1
    # The file is protected by GitHub's secret storage; its own password is fixed.
    /usr/bin/openssl pkcs12 -export -name "$NAME" \
        -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
        -out "$BACKUP" -passout pass:dockflip >/dev/null 2>&1
    chmod 600 "$BACKUP"
    echo "Backup saved: $BACKUP"
    echo "Put a copy in your password manager too."
fi

ENCODED="$(base64 -i "$BACKUP" | tr -d '\n')"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    printf '%s' "$ENCODED" | gh secret set RELEASE_IDENTITY --repo "$REPO"
    echo "Done: the RELEASE_IDENTITY secret is set on $REPO."
else
    printf '%s' "$ENCODED" | pbcopy
    echo
    echo "The identity is now on your clipboard. In the page that opens:"
    echo "  Name:   RELEASE_IDENTITY"
    echo "  Secret: paste (⌘V)"
    echo "  then press \"Add secret\"."
    open "$SECRETS_URL"
fi
