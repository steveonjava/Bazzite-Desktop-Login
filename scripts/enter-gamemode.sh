#!/usr/bin/bash
# Arm a one-shot autologin into game mode, log out of the desktop, then restart the
# display manager so it actually picks the autologin up. Run as root by
# enter-gamemode.service.

set -uo pipefail

IMAGE_INFO="/usr/share/ublue-os/image-info.json"
BASE_IMAGE_NAME="$(jq -r '."base-image-name"' < "$IMAGE_INFO")"

DESKTOP_USER="$(id -nu 1000)"
DESKTOP_HOME="$(getent passwd "$DESKTOP_USER" | cut -d: -f6)"

HERE="$(dirname "$0")"

# Which display-manager unit to restart. Same binary probe the helper uses.
if [[ -x /usr/bin/plasmalogin ]]; then
    DM_UNIT="plasmalogin.service"
elif [[ -x /usr/bin/sddm ]]; then
    DM_UNIT="sddm.service"
else
    echo "❌ No supported display manager found." >&2
    exit 1
fi

# Is the desktop user still holding a graphical session?
user_graphical_session_active() {
    local s name class type
    for s in $(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}'); do
        name="$(loginctl show-session "$s" -p Name --value 2>/dev/null)"
        class="$(loginctl show-session "$s" -p Class --value 2>/dev/null)"
        type="$(loginctl show-session "$s" -p Type --value 2>/dev/null)"
        if [[ "$name" == "$DESKTOP_USER" && "$class" == "user" ]] \
           && [[ "$type" == "wayland" || "$type" == "x11" ]]; then
            return 0
        fi
    done
    return 1
}

# Arm autologin for the gamescope session. If this fails - no session file found,
# Steam not installed, unwritable config dir - do NOT log out: that would drop the
# user at the greeter for no reason, which is indistinguishable from "nothing
# happened" and is precisely how the pre-plasmalogin breakage presented.
if ! "$HERE/ensure-bazzite-desktop-login.sh" \
        "$DESKTOP_USER" "$DESKTOP_HOME" "enter-gamemode"; then
    echo "❌ Could not arm game-mode autologin; staying on the desktop." >&2
    exit 1
fi

# Log out cleanly.
qdbus_bin="$(command -v qdbus || command -v qdbus6 || command -v qdbus-qt6)"

if [[ $BASE_IMAGE_NAME == "kinoite" ]]; then
    if [[ -z "$qdbus_bin" ]]; then
        echo "❌ No qdbus binary found; cannot log out of Plasma." >&2
        "$HERE/ensure-bazzite-desktop-login.sh" "$DESKTOP_USER" "$DESKTOP_HOME" "clear"
        exit 1
    fi
    sudo -Eu "$DESKTOP_USER" "$qdbus_bin" org.kde.Shutdown /Shutdown org.kde.Shutdown.logout
elif [[ $BASE_IMAGE_NAME == "silverblue" ]]; then
    sudo -Eu "$DESKTOP_USER" gnome-session-quit --logout --no-prompt
else
    echo "❌ Unknown base image '$BASE_IMAGE_NAME'; not logging out." >&2
    "$HERE/ensure-bazzite-desktop-login.sh" "$DESKTOP_USER" "$DESKTOP_HOME" "clear"
    exit 1
fi

# Wait for the session to actually end before restarting the display manager, so the
# logout stays clean rather than being cut short.
for _ in $(seq 1 60); do
    user_graphical_session_active || break
    sleep 0.5
done

if user_graphical_session_active; then
    # Logout did not take. Disarm rather than leaving a live autologin behind, and do
    # not restart the display manager - that would kill the session the user still has.
    echo "❌ Desktop session did not end within 30s; disarming and staying put." >&2
    "$HERE/ensure-bazzite-desktop-login.sh" "$DESKTOP_USER" "$DESKTOP_HOME" "clear"
    exit 1
fi

# The display manager reads its configuration only when it starts. Arming the autologin
# while it is already running has no effect - it will just show the greeter, which is
# exactly what happened before this step existed. Restarting it makes it re-read the
# config and honour the autologin, the same way it does at boot.
#
# --no-block so this oneshot is not waiting on a unit that is tearing down the very
# session tree it was launched from.
echo "🔄 Restarting $DM_UNIT to apply the autologin..."
systemctl restart --no-block "$DM_UNIT"
