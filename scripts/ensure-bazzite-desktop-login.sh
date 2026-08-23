#!/bin/bash
# Manage the display manager's autologin drop-in for Bazzite Desktop Login.
#
# Modes:
#   install         disarm autologin, so the next boot shows the login prompt
#   enter-gamemode  arm a one-shot autologin into the gamescope session
#   clear           disarm autologin again (run once gamescope is up)
#
# Supports both display managers:
#   plasmalogin  Plasma 6.7+ / Bazzite 44.20260820 and later  -> /etc/plasmalogin.conf.d
#   sddm         older Bazzite images                          -> /etc/sddm.conf.d

set -uo pipefail

DESKTOP_USER="${1:-${SUDO_USER:-${USER:-$(id -nu 1000)}}}"
DESKTOP_HOME="${2:-$(getent passwd "$DESKTOP_USER" | cut -d: -f6)}"
MODE="${3:-enter-gamemode}"

WAYLAND_SESSION_DIR="${WAYLAND_SESSION_DIR:-/usr/share/wayland-sessions}"

# Preference order for the gaming session; first one that exists wins.
# Override with GAMEMODE_SESSION=<file.desktop>.
GAMEMODE_SESSION_CANDIDATES=(
    gamescope-session-ogui-steam.desktop  # Steam Big Picture Plus (OpenGamepadUI)
    gamescope-session-steam-plus.desktop  # same, alternate packaging
    gamescope-session-steam.desktop       # plain Steam Big Picture
    gamescope-session.desktop             # pre-2026 Bazzite
)

# Run privileged bits directly when already root (systemd service), else via sudo.
if [[ $EUID -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi

detect_dm() {
    # Key on the BINARY, not the config directory. /etc/sddm.conf.d/ survives the
    # plasmalogin migration as a stale leftover, so testing for the directory would
    # pick sddm on a plasmalogin system and write the config where nothing reads it.
    if [[ -x /usr/bin/plasmalogin ]]; then
        DM_NAME="plasmalogin"
        DM_CONF_DIR="/etc/plasmalogin.conf.d"
    elif [[ -x /usr/bin/sddm ]]; then
        DM_NAME="sddm"
        DM_CONF_DIR="/etc/sddm.conf.d"
    else
        echo "❌ No supported display manager found (looked for plasmalogin and sddm)." >&2
        return 1
    fi
    AUTOLOGIN_CONF="$DM_CONF_DIR/zz-bazzite-desktop-login-autologin.conf"
    return 0
}

resolve_gamemode_session() {
    local candidate
    if [[ -n "${GAMEMODE_SESSION:-}" ]]; then
        if [[ -f "$WAYLAND_SESSION_DIR/$GAMEMODE_SESSION" ]]; then
            printf '%s' "$GAMEMODE_SESSION"
            return 0
        fi
        echo "❌ GAMEMODE_SESSION='$GAMEMODE_SESSION' not found in $WAYLAND_SESSION_DIR" >&2
        return 1
    fi
    for candidate in "${GAMEMODE_SESSION_CANDIDATES[@]}"; do
        if [[ -f "$WAYLAND_SESSION_DIR/$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    # Never write a dangling Session=: the display manager silently falls back to the
    # greeter, which looks exactly like "Enter Gaming Mode did nothing".
    echo "❌ No gamescope session file found in $WAYLAND_SESSION_DIR." >&2
    echo "   Tried: ${GAMEMODE_SESSION_CANDIDATES[*]}" >&2
    return 1
}

write_conf() {
    $SUDO install -d -m 0755 "$DM_CONF_DIR" || return 1
    printf '%s' "$1" | $SUDO tee "$AUTOLOGIN_CONF" >/dev/null || return 1
    $SUDO chmod 0644 "$AUTOLOGIN_CONF" || return 1
}

disarm() {
    write_conf "# Managed by Bazzite-Desktop-Login. Autologin disarmed: show the login prompt.
[Autologin]
User=
" || { echo "❌ Failed to write $AUTOLOGIN_CONF" >&2; return 1; }
    echo "✅ Autologin disarmed ($DM_NAME): $AUTOLOGIN_CONF"
}

arm() {
    local session
    session="$(resolve_gamemode_session)" || return 1

    # Steam must actually be installed, or autologin lands in a session that cannot start.
    if [[ ! -f "$DESKTOP_HOME/.local/share/Steam/ubuntu12_32/steamui.so" ]]; then
        echo "❌ Steam does not look installed under $DESKTOP_HOME - refusing to arm autologin." >&2
        return 1
    fi

    # Note on Relogin: both plasmalogin and SDDM default to Relogin=false, and setting it
    # true does NOT help here. Tested on plasmalogin 6.7: arming with Relogin=true still
    # produced the greeter on logout, because the display manager reads its configuration
    # only when the daemon starts. enter-gamemode.sh therefore restarts the display
    # manager after the session ends, which makes autologin fire the same way it does at
    # boot. Relogin is deliberately left out - it is unnecessary with that approach and
    # would risk being logged straight back into game mode on exit.
    #
    # RememberLastSession=false keeps the greeter from treating game mode as the new
    # default once we come back. It reverts when the file is disarmed.
    write_conf "# Managed by Bazzite-Desktop-Login. TEMPORARY one-shot autologin into game mode.
# Cleared automatically once gamescope starts - see bazzite-clear-autologin.sh.
# Applied by restarting the display manager: it only reads config at startup.
[Users]
RememberLastSession=false
[Autologin]
User=$DESKTOP_USER
Session=$session
" || { echo "❌ Failed to write $AUTOLOGIN_CONF" >&2; return 1; }
    echo "✅ Autologin armed ($DM_NAME) for $DESKTOP_USER -> $session"
}

detect_dm || exit 1

case "$MODE" in
    install|clear)   disarm ;;
    enter-gamemode)  arm ;;
    *)
        echo "❌ Unknown mode '$MODE' (expected: install, enter-gamemode, clear)" >&2
        exit 1
        ;;
esac
