#!/bin/bash

# Resolve script directory so relative paths work from anywhere
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

# Prefer the invoking user when run via sudo; otherwise fall back to uid 1000
DESKTOP_USER="${SUDO_USER:-$(id -nu 1000)}"
DESKTOP_HOME="$(getent passwd "$DESKTOP_USER" | cut -d: -f6)"

# Check if the OS is Bazzite
if ! grep -q "Bazzite" /etc/*-release; then
    echo "❌ This script is intended for Bazzite OS only. Exiting."
    exit 1
fi

echo "✅ Bazzite OS detected, proceeding."

IMAGE_INFO="/usr/share/ublue-os/image-info.json"
command -v jq >/dev/null 2>&1 || { echo "❌ jq is required."; exit 1; }
BASE_IMAGE_NAME=$(jq -r '."base-image-name"' < "$IMAGE_INFO")

# Check desktop via base image name
if [[ "$BASE_IMAGE_NAME" == "silverblue" ]]; then
    echo "❌ This script does not work on GNOME (Silverblue). Aborting install."
    exit 1
elif [[ "$BASE_IMAGE_NAME" == "kinoite" ]]; then
    echo "✅ KDE variant detected, proceeding."
else
    echo "❌ Aborting install due to unknown base image: $BASE_IMAGE_NAME"
    exit 1
fi

# Detect the display manager. Key on the binary, not the config directory:
# /etc/sddm.conf.d/ survives the plasmalogin migration as a stale leftover.
if [[ -x /usr/bin/plasmalogin ]]; then
    DM_NAME="plasmalogin"
elif [[ -x /usr/bin/sddm ]]; then
    DM_NAME="sddm"
else
    echo "❌ No supported display manager found (looked for plasmalogin and sddm). Aborting."
    exit 1
fi
echo "✅ Display manager detected: $DM_NAME"

# Move the enter gamemode script
echo "📦 Copying enter gamemode script..."
if sudo cp "$SCRIPTS_DIR/enter-gamemode.sh" /usr/local/bin/enter-gamemode.sh; then
    sudo chmod +x /usr/local/bin/enter-gamemode.sh || {
        echo "❌ Failed to make script executable."
        exit 1
    }
else
    echo "❌ Failed to copy enter-gamemode.sh to /usr/local/bin/"
    exit 1
fi

# Copy the helper scripts
echo "📦 Copying helper scripts..."
for helper in ensure-bazzite-desktop-login.sh bazzite-clear-autologin.sh; do
    if sudo cp "$SCRIPTS_DIR/$helper" "/usr/local/bin/$helper"; then
        sudo chmod +x "/usr/local/bin/$helper" || {
            echo "❌ Failed to make $helper executable."
            exit 1
        }
    else
        echo "❌ Failed to copy $helper to /usr/local/bin/"
        exit 1
    fi
done

# Disarm autologin so the first reboot shows the login screen
if ! sudo /usr/local/bin/ensure-bazzite-desktop-login.sh "$DESKTOP_USER" "$DESKTOP_HOME" "install"; then
    echo "❌ Failed to initialise autologin configuration."
    exit 1
fi

WAYLAND_SESS_DIR="/usr/local/share/wayland-sessions"
SRC_SESSION="/usr/share/wayland-sessions/plasma.desktop"
DST_SESSION="$WAYLAND_SESS_DIR/00-plasma.desktop"

# This symlink is an SDDM sort-order hack: it makes plasma.desktop sort first so an
# empty Session= lands on Plasma. plasmalogin is a different implementation and does
# not document scanning /usr/local/share/wayland-sessions, so only do it for SDDM.
if [[ "$DM_NAME" == "sddm" ]]; then
    echo "📦 Creating session override in $WAYLAND_SESS_DIR..."
    if sudo install -d -m 0755 "$WAYLAND_SESS_DIR"; then
        if ! sudo ln -sf "$SRC_SESSION" "$DST_SESSION"; then
            echo "❌ Failed to create session symlink: $DST_SESSION"
            exit 1
        fi
    else
        echo "❌ Failed to create directory: $WAYLAND_SESS_DIR"
        exit 1
    fi
else
    echo "⏭️  Skipping $WAYLAND_SESS_DIR override (not needed on $DM_NAME)."
fi

# Move the systemd service file
echo "🛠️  Installing systemd service..."
if sudo cp "$SCRIPTS_DIR/enter-gamemode.service" /etc/systemd/system/enter-gamemode.service; then
    sudo systemctl daemon-reload || echo "⚠️ Warning: daemon-reload failed."
else
    echo "❌ Failed to copy enter-gamemode.service to /etc/systemd/system/"
    exit 1
fi

# Drop-in that disarms the autologin the moment game mode actually starts, making it
# one-shot. Applied to the TEMPLATE unit so it covers every client (@ogui-steam,
# @steam, ...), not just the one currently in use.
GAMESCOPE_DROPIN_DIR="/etc/systemd/user/gamescope-session-plus@.service.d"
echo "🛠️  Installing one-shot autologin drop-in..."
if sudo install -d -m 0755 "$GAMESCOPE_DROPIN_DIR"; then
    if sudo install -m 0644 "$SCRIPTS_DIR/gamescope-clear-autologin.conf" \
            "$GAMESCOPE_DROPIN_DIR/10-clear-autologin.conf"; then
        sudo systemctl --global daemon-reload 2>/dev/null || true
    else
        echo "❌ Failed to install drop-in to $GAMESCOPE_DROPIN_DIR"
        exit 1
    fi
else
    echo "❌ Failed to create directory: $GAMESCOPE_DROPIN_DIR"
    exit 1
fi

USER_APP_DIR="$DESKTOP_HOME/.local/share/applications"
USER_DESKTOP_FILE="$USER_APP_DIR/enter-gamemode.desktop"

# Install desktop launcher to user location (Bazzite /usr is immutable)
echo "🧩 Installing desktop launcher..."
mkdir -p "$USER_APP_DIR" || {
    echo "❌ Failed to create user applications directory: $USER_APP_DIR"
    exit 1
}

if cp "$SCRIPTS_DIR/enter-gamemode.desktop" "$USER_DESKTOP_FILE"; then
    sudo chown "$DESKTOP_USER:$DESKTOP_USER" "$USER_DESKTOP_FILE" || true
    echo "✅ Installed to $USER_APP_DIR!"
else
    echo "❌ Failed to copy desktop file to $USER_APP_DIR"
    exit 1
fi

# Update desktop database so the app appears in menus
echo "🔄 Updating desktop database..."
if [[ -f "$USER_DESKTOP_FILE" ]]; then
    update-desktop-database "$USER_APP_DIR" >/dev/null 2>&1 || true
fi

USER_DESKTOP_DIR="$DESKTOP_HOME/Desktop"
ENTER_DESKTOP_LINK="$USER_DESKTOP_DIR/Enter.desktop"
RETURN_DESKTOP="$USER_DESKTOP_DIR/Return.desktop"
RETURN_DESKTOP_BACKUP="$USER_DESKTOP_DIR/.Return.desktop"

# Create Desktop link for Enter Gaming Mode
echo "🖥️  Creating Desktop link for Enter Gaming Mode..."
if ! mkdir -p "$USER_DESKTOP_DIR"; then
    echo "❌ Failed to ensure Desktop directory exists: $USER_DESKTOP_DIR"
    exit 1
fi

# Use user-local desktop file
if [[ -f "$USER_DESKTOP_FILE" ]]; then
    SRC_DESKTOP_FILE="$USER_DESKTOP_FILE"
else
    echo "❌ Could not find enter-gamemode.desktop in $USER_APP_DIR."
    exit 1
fi

if ! ln -sf "$SRC_DESKTOP_FILE" "$ENTER_DESKTOP_LINK"; then
    echo "❌ Failed to create Desktop link: $ENTER_DESKTOP_LINK"
    exit 1
fi

chmod +x "$ENTER_DESKTOP_LINK" || true
sudo chown "$DESKTOP_USER:$DESKTOP_USER" "$ENTER_DESKTOP_LINK" || true

# Hide default Return to Gaming Mode Desktop icon (by moving it aside)
echo "🙈 Hiding default Return to Gaming Mode Desktop icon (if present)..."
if [[ -f "$RETURN_DESKTOP" ]]; then
    if [[ ! -f "$RETURN_DESKTOP_BACKUP" ]]; then
        if ! sudo mv -f "$RETURN_DESKTOP" "$RETURN_DESKTOP_BACKUP"; then
            echo "⚠️  Warning: Failed to hide $RETURN_DESKTOP"
        fi
        sudo chown "$DESKTOP_USER:$DESKTOP_USER" "$RETURN_DESKTOP_BACKUP" || true
    fi
fi

echo "🔐 Configuring sudoers for passwordless service execution..."

SYSTEMCTL_PATH="$(command -v systemctl)"
SUDOERS_FILE="/etc/sudoers.d/enter-gamemode"
# Two commands: starting the transition service, and the no-argument clear helper
# invoked from the gamescope session. The helper takes no arguments precisely so this
# rule needs no wildcard.
SUDO_RULE="$DESKTOP_USER ALL=(root) NOPASSWD: $SYSTEMCTL_PATH start enter-gamemode.service, /usr/local/bin/bazzite-clear-autologin.sh"

# Validate in a temp file BEFORE installing: a malformed drop-in in /etc/sudoers.d can
# break sudo for every command on the system.
SUDOERS_TMP="$(mktemp)"
printf '%s\n' "$SUDO_RULE" > "$SUDOERS_TMP"
chmod 0440 "$SUDOERS_TMP"

if ! sudo visudo -cf "$SUDOERS_TMP" >/dev/null 2>&1; then
    echo "❌ sudoers validation failed; not installing."
    sudo visudo -cf "$SUDOERS_TMP" || true
    rm -f "$SUDOERS_TMP"
    exit 1
fi

if ! sudo install -m 0440 -o root -g root "$SUDOERS_TMP" "$SUDOERS_FILE"; then
    echo "❌ Failed to install sudoers file."
    rm -f "$SUDOERS_TMP"
    exit 1
fi
rm -f "$SUDOERS_TMP"

echo "✅ Passwordless sudo configured for enter-gamemode.service"

echo
echo "🎉 Installation complete."
