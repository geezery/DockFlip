#!/bin/bash
# Double-click this file in Finder to build and install DockFlip.
# It does the same as `make install`, and first makes sure the tools are there.

cd "$(dirname "$0")" || exit 1

finish() {
    echo
    read -r -n 1 -s -p "Press any key to close this window."
    echo
    exit "$1"
}

trap 'echo; echo "Something went wrong. Nothing was changed after the failing step."; \
      echo "Copy the text above into an issue or message so it can be fixed."; finish 1' ERR
set -e

clear
echo "DockFlip installer"
echo "=================="
echo

# macOS 26 or later.
version=$(sw_vers -productVersion)
if [ "${version%%.*}" -lt 26 ]; then
    echo "DockFlip needs macOS 26 or later. This Mac has macOS $version."
    finish 1
fi

# Apple's free Command Line Tools: the compiler DockFlip is built with.
tools_ready() {
    local dir
    dir=$(xcode-select -p 2>/dev/null) && [ -x "$dir/usr/bin/swift" ]
}
if ! tools_ready; then
    echo "Step 1 of 2: Apple's Command Line Tools (free, a few GB, takes a while)."
    echo "A window opens: click Install and accept the licence."
    xcode-select --install >/dev/null 2>&1 || true
    echo "Waiting for the installation to finish…"
    until tools_ready; do sleep 10; done
    echo "Command Line Tools installed."
    echo
fi

echo "Step 2 of 2: building and installing DockFlip (a minute or two)."
echo "The first time, macOS asks for your login password once: DockFlip creates"
echo "its own signing certificate so its permissions survive updates."
echo
make install

trap - ERR
echo
echo "Done. DockFlip is in Applications and running — look for its icon in the menu bar."
echo "Its setup window asks for one permission: Accessibility. Follow the steps there."
finish 0
