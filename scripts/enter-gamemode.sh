#!/usr/bin/bash

IMAGE_INFO="/usr/share/ublue-os/image-info.json"
BASE_IMAGE_NAME=$(jq -r '."base-image-name"' < $IMAGE_INFO)

DESKTOP_USER=$(id -nu 1000)
DESKTOP_HOME=$(getent passwd "$DESKTOP_USER" | cut -d: -f6)

# Ensure Bazzite Desktop Login SDDM config exists and enable gamescope autologin
"$(dirname "$0")/ensure-bazzite-desktop-login.sh" "$DESKTOP_USER" "$DESKTOP_HOME" "enter-gamemode"

if [[ $BASE_IMAGE_NAME = "kinoite" ]]; then
  sudo -Eu "$DESKTOP_USER" qdbus org.kde.Shutdown /Shutdown org.kde.Shutdown.logout
elif [[ $BASE_IMAGE_NAME = "silverblue" ]]; then
  sudo -Eu "$DESKTOP_USER" gnome-session-quit --logout --no-prompt
fi
