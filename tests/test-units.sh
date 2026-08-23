#!/bin/bash
# Static tests for the systemd integration installed by this project.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DROPIN="$REPO_ROOT/scripts/gamescope-clear-autologin.conf"

fail=0

check() {
    if [[ "$2" == "$3" ]]; then
        printf '  PASS  %-58s %s\n' "$1" "$3"
    else
        printf '  FAIL  %-58s expected=%s got=%s\n' "$1" "$2" "$3"
        fail=1
    fi
}

echo "=== Gamescope lifecycle hooks ==="
mapfile -t start_posts < <(sed -n 's/^ExecStartPost=//p' "$DROPIN")
mapfile -t stop_posts < <(sed -n 's/^ExecStopPost=//p' "$DROPIN")

check "one startup hook" "1" "${#start_posts[@]}"
check "startup disarms autologin" \
    "/usr/bin/sudo -n /usr/local/bin/bazzite-clear-autologin.sh" \
    "${start_posts[0]:-missing}"
check "two teardown hooks" "2" "${#stop_posts[@]}"
check "portal cleanup runs first and is best-effort" \
    "-/usr/bin/systemctl --user stop xdg-desktop-portal.service" \
    "${stop_posts[0]:-missing}"
check "autologin cleanup remains failure-reporting" \
    "/usr/bin/sudo -n /usr/local/bin/bazzite-clear-autologin.sh" \
    "${stop_posts[1]:-missing}"

echo
echo "=== systemd unit validation ==="
if command -v systemd-analyze >/dev/null 2>&1 \
        && [[ -f /usr/lib/systemd/user/gamescope-session-plus@.service ]]; then
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    mkdir -p "$TMP/gamescope-session-plus@.service.d"
    cp "$DROPIN" "$TMP/gamescope-session-plus@.service.d/10-clear-autologin.conf"
    if SYSTEMD_UNIT_PATH="$TMP:/usr/lib/systemd/user" \
            systemd-analyze --user verify gamescope-session-plus@ogui-steam.service \
            >"$TMP/verify.log" 2>&1; then
        echo "  PASS  drop-in accepted by systemd-analyze"
    else
        echo "  FAIL  systemd-analyze rejected the drop-in"
        sed -n '1,120p' "$TMP/verify.log"
        fail=1
    fi
else
    echo "  SKIP  systemd-analyze or Gamescope base unit not available"
fi

echo
if [[ $fail -eq 0 ]]; then
    echo "ALL TESTS PASSED"
else
    echo "SOME TESTS FAILED"
fi
exit "$fail"
