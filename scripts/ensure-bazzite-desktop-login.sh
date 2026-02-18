#!/bin/bash
# Script to ensure /etc/sddm.conf.d/yy-bazzite-desktop-login.conf exists and disables autologin by default

BAZZITE_DESKTOP_LOGIN_CONF='/etc/sddm.conf.d/yy-bazzite-desktop-login.conf'

if [[ ! -f "$BAZZITE_DESKTOP_LOGIN_CONF" ]]; then
  {
    echo "[Autologin]"
    echo "User="
  } | sudo tee "$BAZZITE_DESKTOP_LOGIN_CONF" > /dev/null
fi
