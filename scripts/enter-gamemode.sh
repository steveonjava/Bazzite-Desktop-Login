#!/usr/bin/bash

IMAGE_INFO="/usr/share/ublue-os/image-info.json"
BASE_IMAGE_NAME=$(jq -r '."base-image-name"' < $IMAGE_INFO)

USER=$(id -nu 1000)
HOME=$(getent passwd $USER | cut -d: -f6)

# Ensure Bazzite Desktop Login SDDM config exists (disables autologin by default)
"$(dirname "$0")/ensure-bazzite-desktop-login.sh"

if [[ $BASE_IMAGE_NAME = "kinoite" ]]; then
  sudo -Eu $USER qdbus org.kde.Shutdown /Shutdown org.kde.Shutdown.logout
elif [[ $BASE_IMAGE_NAME = "silverblue" ]]; then
  sudo -Eu $USER gnome-session-quit --logout --no-prompt
fi
