#!/bin/bash
# Disarm the temporary game-mode autologin.
#
# Deliberately takes NO arguments, so the sudoers rule can match it exactly without
# wildcards. Invoked from the gamescope session's ExecStartPost drop-in, i.e. the
# moment game mode is actually running. That is what makes the autologin one-shot:
# rebooting or crashing out of game mode still lands on the login screen.
set -uo pipefail
exec /usr/local/bin/ensure-bazzite-desktop-login.sh "" "" clear
