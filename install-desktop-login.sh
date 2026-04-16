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

# Copy the ensure-bazzite-desktop-login script and run it
echo "📦 Copying the ensure-bazzite-desktop-login script and run it..."
if sudo cp "$SCRIPTS_DIR/ensure-bazzite-desktop-login.sh" /usr/local/bin/ensure-bazzite-desktop-login.sh; then
    sudo chmod +x /usr/local/bin/ensure-bazzite-desktop-login.sh || {
        echo "❌ Failed to make ensure-bazzite-desktop-login.sh executable."
        exit 1
    }
    # Run the script to ensure the config file is created
    sudo /usr/local/bin/ensure-bazzite-desktop-login.sh "$DESKTOP_USER" "$DESKTOP_HOME"
else
    echo "❌ Failed to copy ensure-bazzite-desktop-login.sh to /usr/local/bin/"
    exit 1
fi

WAYLAND_SESS_DIR="/usr/local/share/wayland-sessions"
SRC_SESSION="/usr/share/wayland-sessions/plasma.desktop"
DST_SESSION="$WAYLAND_SESS_DIR/00-plasma.desktop"

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

# Move the systemd service file
echo "🛠️  Installing systemd service..."
if sudo cp "$SCRIPTS_DIR/enter-gamemode.service" /etc/systemd/system/enter-gamemode.service; then
    sudo systemctl daemon-reload || echo "⚠️ Warning: daemon-reload failed."
else
    echo "❌ Failed to copy enter-gamemode.service to /etc/systemd/system/"
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
SUDO_RULE="$DESKTOP_USER ALL=(root) NOPASSWD: $SYSTEMCTL_PATH start enter-gamemode.service"

if ! sudo bash -c "echo '$SUDO_RULE' > '$SUDOERS_FILE'"; then
    echo "❌ Failed to write sudoers file."
    exit 1
fi

if ! sudo chmod 0440 "$SUDOERS_FILE"; then
    echo "❌ Failed to set permissions on $SUDOERS_FILE"
    exit 1
fi

if ! sudo visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1; then
    echo "❌ sudoers validation failed. Removing invalid file."
    sudo rm -f "$SUDOERS_FILE"
    exit 1
fi

echo "✅ Passwordless sudo configured for enter-gamemode.service"

echo
echo "🎉 Installation complete."
