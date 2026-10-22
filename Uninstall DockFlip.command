#!/bin/bash
# Double-click this file in Finder to remove DockFlip completely.

cd "$(dirname "$0")" || exit 1
clear
echo "DockFlip uninstaller"
echo "===================="
echo
echo "This quits DockFlip and removes the app, its permissions, its settings"
echo "and its signing certificate. macOS's own ⌘Tab comes back."
echo
read -r -p "Remove DockFlip? [y/N] " answer
case "$answer" in
    [yY]*) ;;
    *) echo "Nothing removed."; read -r -n 1 -s -p "Press any key to close."; exit 0 ;;
esac

make uninstall

echo
echo "DockFlip is removed. If it is still listed under System Settings → General →"
echo "Login Items, that entry no longer does anything and can be deleted there."
echo
read -r -n 1 -s -p "Press any key to close this window."
echo
