#!/usr/bin/bash

IMAGE_INFO="/usr/share/ublue-os/image-info.json"
BASE_IMAGE_NAME=$(jq -r '."base-image-name"' < $IMAGE_INFO)

USER=$(id -nu 1000)
HOME=$(getent passwd $USER | cut -d: -f6)

# SteamOS autologin SDDM config
AUTOLOGIN_CONF='/etc/sddm.conf.d/zz-steamos-autologin.conf'
DEFAULT_SESSION_OVERRIDE_CONF='/etc/sddm.conf.d/yy-default-session-override.conf'

# Ensure default-session override exists (disables autologin by default)
if [[ ! -f "$DEFAULT_SESSION_OVERRIDE_CONF" ]]; then
  {
    echo "[Autologin]"
    echo "User="
  } > "$DEFAULT_SESSION_OVERRIDE_CONF"
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

if [[ $BASE_IMAGE_NAME = "kinoite" ]]; then
  sudo -Eu $USER qdbus org.kde.Shutdown /Shutdown org.kde.Shutdown.logout
elif [[ $BASE_IMAGE_NAME = "silverblue" ]]; then
  sudo -Eu $USER gnome-session-quit --logout --no-prompt
fi
