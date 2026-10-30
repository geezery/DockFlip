#!/bin/sh
# Turns macOS's own edge tiling back on for `make uninstall`. DockFlip's setup and
# menu offer to switch it off (NativeEdgeTiling.turnOff writes false into
# com.apple.WindowManager), and nothing else would ever switch it back on.
#
# Only a key that reads 0 is deleted: macOS's default is on, and a key that is
# already on or was never written needs nothing. The keys are
# NativeEdgeTiling.keys; scripts/uninstall-tests.ps1 checks that they match.
#
#   scripts/restore-edge-tiling.sh           com.apple.WindowManager, then restarts WindowManager
#   scripts/restore-edge-tiling.sh <domain>  another domain or a plist path, no restart (for tests)

domain="${1:-com.apple.WindowManager}"
changed=

for key in EnableTilingByEdgeDrag EnableTopTilingByEdgeDrag; do
    if [ "$(defaults read "$domain" "$key" 2>/dev/null)" = 0 ]; then
        defaults delete "$domain" "$key" && changed=1
    fi
done

[ -n "$changed" ] || exit 0

# WindowManager reads the keys at launch only; macOS relaunches it at once.
if [ "$domain" = com.apple.WindowManager ]; then
    killall WindowManager >/dev/null 2>&1
fi
echo "Turned macOS's own edge tiling back on (System Settings > Desktop & Dock)."
