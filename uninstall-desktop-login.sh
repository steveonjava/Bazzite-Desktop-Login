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
ENSURE_SCRIPT="/usr/local/bin/ensure-bazzite-desktop-login.sh"
CLEAR_SCRIPT="/usr/local/bin/bazzite-clear-autologin.sh"
SYSTEMD_UNIT="/etc/systemd/system/enter-gamemode.service"
GAMESCOPE_DROPIN="/etc/systemd/user/gamescope-session-plus@.service.d/10-clear-autologin.conf"
GAMESCOPE_DROPIN_DIR="/etc/systemd/user/gamescope-session-plus@.service.d"
SUDOERS_FILE="/etc/sudoers.d/enter-gamemode"
WAYLAND_LINK="/usr/local/share/wayland-sessions/00-plasma.desktop"

# Desktop launcher (user)
DESKTOP_USER_LAUNCHER="$DESKTOP_HOME/.local/share/applications/enter-gamemode.desktop"

# Files created/used by enter-gamemode.sh
# Note: do NOT remove zz-steamos-autologin.conf or zz-bazzite-autologin.conf - those are
# managed by Steam / Bazzite, not by us. Only remove drop-ins that carry our own name.
SDDM_DEFAULT_OVERRIDE_CONF="/etc/sddm.conf.d/yy-bazzite-desktop-login.conf"
OUR_AUTOLOGIN_CONFS=(
  "/etc/plasmalogin.conf.d/zz-bazzite-desktop-login-autologin.conf"
  "/etc/sddm.conf.d/zz-bazzite-desktop-login-autologin.conf"
)

echo "🛑 Disabling systemd service (if present)..."
sudo systemctl disable --now enter-gamemode.service >/dev/null 2>&1 || true

echo "🧽 Removing installed files..."

if [[ -f "$BIN_SCRIPT" ]]; then
  sudo rm -f "$BIN_SCRIPT"
fi

# Remove ensure-bazzite-desktop-login.sh if present
if [[ -f "$ENSURE_SCRIPT" ]]; then
  sudo rm -f "$ENSURE_SCRIPT"
fi

if [[ -f "$CLEAR_SCRIPT" ]]; then
  sudo rm -f "$CLEAR_SCRIPT"
fi

# Remove our own autologin drop-ins from whichever display manager is in use, so no
# stale autologin survives the uninstall.
for conf in "${OUR_AUTOLOGIN_CONFS[@]}"; do
  if [[ -f "$conf" ]]; then
    echo "   removing $conf"
    sudo rm -f "$conf"
  fi
done

# Remove the one-shot clear drop-in from the gamescope session template
if [[ -f "$GAMESCOPE_DROPIN" ]]; then
  sudo rm -f "$GAMESCOPE_DROPIN"
fi
sudo rmdir "$GAMESCOPE_DROPIN_DIR" 2>/dev/null || true

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

if [[ -f "$DESKTOP_USER_LAUNCHER" ]]; then
  rm -f "$DESKTOP_USER_LAUNCHER" || sudo rm -f "$DESKTOP_USER_LAUNCHER"
fi

if [[ -f "$ENTER_DESKTOP_LINK" || -L "$ENTER_DESKTOP_LINK" ]]; then
  rm -f "$ENTER_DESKTOP_LINK" || sudo rm -f "$ENTER_DESKTOP_LINK"
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

echo "🔄 Updating desktop database..."
if [[ -d "$DESKTOP_HOME/.local/share/applications" ]]; then
  update-desktop-database "$DESKTOP_HOME/.local/share/applications" >/dev/null 2>&1 || true
fi

echo "🔄 Reloading systemd..."
sudo systemctl daemon-reload || true

echo "✅ Uninstall complete."
