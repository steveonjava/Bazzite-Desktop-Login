#!/bin/bash
set -euo pipefail

# Prefer the invoking user when run via sudo; otherwise fall back to uid 1000
DESKTOP_USER="${SUDO_USER:-$(id -nu 1000)}"
DESKTOP_HOME="$(getent passwd "$DESKTOP_USER" | cut -d: -f6)"

USER_DESKTOP_DIR="$DESKTOP_HOME/Desktop"
ENTER_DESKTOP_LINK="$USER_DESKTOP_DIR/Enter.desktop"
RETURN_DESKTOP="$USER_DESKTOP_DIR/Return.desktop"
RETURN_DESKTOP_BACKUP="$USER_DESKTOP_DIR/.Return.desktop"

echo "🧹 Uninstalling Bazzite Desktop Login..."

# Paths installed by installer
BIN_SCRIPT="/usr/local/bin/enter-gamemode.sh"
SYSTEMD_UNIT="/etc/systemd/system/enter-gamemode.service"
SUDOERS_FILE="/etc/sudoers.d/enter-gamemode"
WAYLAND_LINK="/usr/local/share/wayland-sessions/00-plasma.desktop"

# Desktop launcher (system or user)
DESKTOP_SYSTEM="/usr/share/applications/enter-gamemode.desktop"
DESKTOP_USER_LAUNCHER="$DESKTOP_HOME/.local/share/applications/enter-gamemode.desktop"

# Files created/used by enter-gamemode.sh
# Note: do NOT remove zz-steamos-autologin.conf (managed/modified by Steam gamemode too)
SDDM_DEFAULT_OVERRIDE_CONF="/etc/sddm.conf.d/yy-default-session-override.conf"

echo "🛑 Disabling systemd service (if present)..."
sudo systemctl disable --now enter-gamemode.service >/dev/null 2>&1 || true

echo "🧽 Removing installed files..."

if [[ -f "$BIN_SCRIPT" ]]; then
  sudo rm -f "$BIN_SCRIPT"
fi

if [[ -L "$WAYLAND_LINK" || -f "$WAYLAND_LINK" ]]; then
  sudo rm -f "$WAYLAND_LINK"
fi

sudo rmdir /usr/local/share/wayland-sessions 2>/dev/null || true

if [[ -f "$SDDM_DEFAULT_OVERRIDE_CONF" ]]; then
  sudo rm -f "$SDDM_DEFAULT_OVERRIDE_CONF"
fi

if [[ -f "$SUDOERS_FILE" ]]; then
  sudo rm -f "$SUDOERS_FILE"
fi

if [[ -f "$DESKTOP_SYSTEM" ]]; then
  sudo rm -f "$DESKTOP_SYSTEM"
fi

if [[ -f "$DESKTOP_USER_LAUNCHER" ]]; then
  rm -f "$DESKTOP_USER_LAUNCHER"
fi

if [[ -f "$ENTER_DESKTOP_LINK" || -L "$ENTER_DESKTOP_LINK" ]]; then
  rm -f "$ENTER_DESKTOP_LINK"
fi

# Unhide Return to Gaming Mode Desktop icon (restore backup if we hid it)
if [[ -f "$RETURN_DESKTOP_BACKUP" ]]; then
  if [[ -f "$RETURN_DESKTOP" ]]; then
    rm -f "$RETURN_DESKTOP"
  fi
  sudo mv -f "$RETURN_DESKTOP_BACKUP" "$RETURN_DESKTOP" || true
  sudo chown "$DESKTOP_USER:$DESKTOP_USER" "$RETURN_DESKTOP" || true
fi

if [[ -f "$SYSTEMD_UNIT" ]]; then
  sudo rm -f "$SYSTEMD_UNIT"
fi

echo "🔄 Reloading systemd..."
sudo systemctl daemon-reload || true

echo "✅ Uninstall complete."
