#!/bin/bash
# Script to ensure /etc/sddm.conf.d/yy-bazzite-desktop-login.conf exists and disables autologin by default

BAZZITE_DESKTOP_LOGIN_CONF='/etc/sddm.conf.d/yy-bazzite-desktop-login.conf'

if [[ ! -f "$BAZZITE_DESKTOP_LOGIN_CONF" ]]; then
  {
    echo "[Autologin]"
    echo "User="
  } | sudo tee "$BAZZITE_DESKTOP_LOGIN_CONF" > /dev/null
fi

# Configure autologin if Steam has been updated
if [[ -f $HOME/.local/share/Steam/ubuntu12_32/steamui.so ]]; then
  {
    echo "[Users]"
    echo "RememberLastSession=false" # Don't remember gamescope as the last session (this effectively clears Session, so we also need to reorder this list to make plasma.desktop first)
    echo "[Autologin]"
    echo "User=$USER" # Re-enable autologin
    echo "Session=gamescope-session.desktop"
  } > "$AUTOLOGIN_CONF"
fi
