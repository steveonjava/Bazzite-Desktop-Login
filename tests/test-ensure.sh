#!/bin/bash
# Unit tests for scripts/ensure-bazzite-desktop-login.sh.
#
# Runs without root and never writes to /etc: the dispatch tail is stripped so the file
# can be sourced, and write_conf() is overridden to redirect output to a temp file.
#
# Usage:  ./tests/test-ensure.sh
#
# Note: detect_dm() assertions reflect the machine you run on. On a plasmalogin system
# it expects plasmalogin; on an SDDM system, sddm.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/scripts/ensure-bazzite-desktop-login.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

sed '/^detect_dm || exit 1/,$d' "$SRC" > "$TMP/lib.sh"
# shellcheck source=/dev/null
source "$TMP/lib.sh"

fail=0
check()    { if [[ "$2" == "$3" ]]; then printf '  PASS  %-50s %s\n' "$1" "$3"
             else printf '  FAIL  %-50s expected=%s got=%s\n' "$1" "$2" "$3"; fail=1; fi; }
contains() { if grep -qxF "$2" "$3"; then printf '  PASS  %-50s\n' "$1"
             else printf '  FAIL  %-50s missing: %s\n' "$1" "$2"; fail=1; fi; }
absent()   { if grep -qxF "$2" "$3"; then printf '  FAIL  %-50s unexpected: %s\n' "$1" "$2"; fail=1
             else printf '  PASS  %-50s\n' "$1"; fi; }

echo "=== detect_dm() ==="
if detect_dm; then
    if [[ -x /usr/bin/plasmalogin ]]; then
        check "DM_NAME"     "plasmalogin"             "$DM_NAME"
        check "DM_CONF_DIR" "/etc/plasmalogin.conf.d" "$DM_CONF_DIR"
    else
        check "DM_NAME"     "sddm"                    "$DM_NAME"
        check "DM_CONF_DIR" "/etc/sddm.conf.d"        "$DM_CONF_DIR"
    fi
else
    echo "  SKIP  no display manager on this host"
fi

echo
echo "=== resolve_gamemode_session() ==="
resolved="$(resolve_gamemode_session 2>/dev/null)"
if [[ -n "$resolved" ]]; then
    echo "  INFO  resolved to: $resolved"
    if [[ -f "/usr/share/wayland-sessions/gamescope-session-ogui-steam.desktop" ]]; then
        check "prefers the ogui variant when present" "gamescope-session-ogui-steam.desktop" "$resolved"
    fi
else
    echo "  SKIP  no gamescope session files on this host"
fi

echo
echo "=== negative tests: must fail rather than emit a dangling Session= ==="
if GAMEMODE_SESSION=definitely-not-here.desktop resolve_gamemode_session >/dev/null 2>&1
    then echo "  FAIL  nonexistent GAMEMODE_SESSION was accepted"; fail=1
    else echo "  PASS  nonexistent GAMEMODE_SESSION rejected"; fi
mkdir -p "$TMP/empty"
if ( export WAYLAND_SESSION_DIR="$TMP/empty"; resolve_gamemode_session >/dev/null 2>&1 )
    then echo "  FAIL  empty session dir was accepted"; fail=1
    else echo "  PASS  empty session dir rejected"; fi

# Exercise the real writers with output redirected away from /etc.
OUT="$TMP/generated.conf"
# shellcheck disable=SC2329 # Called indirectly by the sourced arm/disarm functions.
write_conf() { printf '%s' "$1" > "$OUT"; }
# shellcheck disable=SC2034 # Read indirectly by the sourced arm function.
DESKTOP_USER="testuser"
DESKTOP_HOME="$TMP/home"
mkdir -p "$DESKTOP_HOME/.local/share/Steam/ubuntu12_32"
touch "$DESKTOP_HOME/.local/share/Steam/ubuntu12_32/steamui.so"

if [[ -n "$resolved" ]]; then
    echo
    echo "=== arm() ==="
    if arm >/dev/null 2>&1; then
        contains "User set"                  "User=testuser"             "$OUT"
        contains "Session set"               "Session=$resolved"         "$OUT"
        contains "RememberLastSession=false" "RememberLastSession=false" "$OUT"
        # Relogin does not work on plasmalogin 6.7 (config is only read at daemon
        # start) and would risk relogging into game mode on exit. enter-gamemode.sh
        # restarts the display manager instead. Guard against it creeping back.
        absent   "Relogin deliberately absent" "Relogin=true"            "$OUT"
    else
        echo "  FAIL  arm() returned non-zero"; fail=1
    fi

    echo
    echo "=== disarm() ==="
    if disarm >/dev/null 2>&1; then
        absent   "Session removed" "Session=$resolved" "$OUT"
        contains "User emptied"    "User="             "$OUT"
    else
        echo "  FAIL  disarm() returned non-zero"; fail=1
    fi
fi

echo
echo "=== arm() refuses when Steam is not installed ==="
DESKTOP_HOME="$TMP/nosteam"; mkdir -p "$DESKTOP_HOME"
if arm >/dev/null 2>&1
    then echo "  FAIL  armed despite no Steam install"; fail=1
    else echo "  PASS  refused to arm without Steam"; fi

echo
if [[ $fail -eq 0 ]]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; fi
exit $fail
