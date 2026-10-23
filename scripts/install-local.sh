#!/usr/bin/env bash
#
# install-local.sh - install the Fusion 360 launchers and desktop entries for
# the current user.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

install -Dm755 "$REPO_DIR/scripts/fusion360"                "$HOME/.local/bin/fusion360"
install -Dm755 "$REPO_DIR/scripts/fusion360-update"         "$HOME/.local/bin/fusion360-update"
install -Dm755 "$REPO_DIR/scripts/fusion-adskidmgr-direct"  "$HOME/.local/bin/fusion-adskidmgr-direct"

mkdir -p "$HOME/.local/share/fusion360"
install -Dm644 "$REPO_DIR/scripts/dxvk.conf"                "$HOME/.local/share/fusion360/dxvk.conf"

mkdir -p "$HOME/.local/share/applications"

sed "s#@@HOME@@#$HOME#g" \
  "$REPO_DIR/scripts/adskidmgr.desktop" > "$HOME/.local/share/applications/adskidmgr.desktop"

sed "s#@@HOME@@#$HOME#g" \
  "$REPO_DIR/scripts/autodesk-fusion360.desktop" > "$HOME/.local/share/applications/autodesk-fusion360.desktop"

sed "s#@@HOME@@#$HOME#g" \
  "$REPO_DIR/scripts/autodesk-fusion360-update.desktop" > "$HOME/.local/share/applications/autodesk-fusion360-update.desktop"

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
xdg-mime default adskidmgr.desktop x-scheme-handler/adskidmgr 2>/dev/null || true
kbuildsycoca6 --noincremental 2>/dev/null || true

echo "Installed Fusion 360 launchers:"
echo "  ~/.local/bin/fusion360"
echo "  ~/.local/bin/fusion360-update"
echo "  ~/.local/bin/fusion-adskidmgr-direct"
echo
echo "Launch Fusion from the KDE menu (Autodesk Fusion 360) or:"
echo "  ~/.local/bin/fusion360"
