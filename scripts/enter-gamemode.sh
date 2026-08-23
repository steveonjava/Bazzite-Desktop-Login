#!/usr/bin/bash
# Arm a one-shot autologin into game mode, then log out of the desktop so the
# display manager picks it up. Run as root by enter-gamemode.service.

set -uo pipefail

IMAGE_INFO="/usr/share/ublue-os/image-info.json"
BASE_IMAGE_NAME="$(jq -r '."base-image-name"' < "$IMAGE_INFO")"

DESKTOP_USER="$(id -nu 1000)"
DESKTOP_HOME="$(getent passwd "$DESKTOP_USER" | cut -d: -f6)"

# Arm autologin for the gamescope session. If this fails - no session file found,
# Steam not installed, unwritable config dir - do NOT log out: that would drop the
# user at the greeter for no reason, which is indistinguishable from "nothing
# happened" and is precisely how the pre-plasmalogin breakage presented.
if ! "$(dirname "$0")/ensure-bazzite-desktop-login.sh" \
        "$DESKTOP_USER" "$DESKTOP_HOME" "enter-gamemode"; then
    echo "❌ Could not arm game-mode autologin; staying on the desktop." >&2
    exit 1
fi

# Qt6 renamed the binary; accept either.
qdbus_bin="$(command -v qdbus || command -v qdbus6 || command -v qdbus-qt6)"

if [[ $BASE_IMAGE_NAME == "kinoite" ]]; then
    if [[ -z "$qdbus_bin" ]]; then
        echo "❌ No qdbus binary found; cannot log out of Plasma." >&2
        exit 1
    fi
    sudo -Eu "$DESKTOP_USER" "$qdbus_bin" org.kde.Shutdown /Shutdown org.kde.Shutdown.logout
elif [[ $BASE_IMAGE_NAME == "silverblue" ]]; then
    sudo -Eu "$DESKTOP_USER" gnome-session-quit --logout --no-prompt
else
    echo "❌ Unknown base image '$BASE_IMAGE_NAME'; not logging out." >&2
    exit 1
fi
