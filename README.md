# Bazzite Desktop Login (Steam Deck)

A small utility for **Bazzite (Steam Deck, KDE/Plasma)** that keeps the system booting to the normal **desktop login (password prompt)** while still providing a simple way to switch into **Gaming Mode (Gamescope)** from the desktop.

---

## What This Project Does

When installed, this project:

* Installs a **systemd oneshot service**: `enter-gamemode.service`
* Installs a launcher: **Enter Gaming Mode** (Category: `System`)
* Creates a desktop shortcut: `~/Desktop/Enter.desktop`
* Temporarily enables SDDM autologin only when switching to Gaming Mode
* Logs out of Plasma to allow Gamescope to start
* Hides the default `Return.desktop` icon by renaming it to `.Return.desktop`
* Adds a sudoers rule so the service can start without prompting for a password

It does **not** permanently modify Steam’s own configuration.

---

## Supported Systems

* **Bazzite (Steam Deck) KDE/Plasma**

  * Base image name must be `kinoite`
  * The installer verifies this automatically

The GNOME variant (`silverblue`) is not supported.

---

## Installation

Clone the repository:

```bash
git clone https://github.com/steveonjava/Bazzite-Desktop-Login.git
cd Bazzite-Desktop-Login
```

Make the installer executable and run it:

```bash
chmod +x install-desktop-login.sh
./install-desktop-login.sh
```

The installer:

* Copies the service script to `/usr/local/bin`
* Installs the systemd unit
* Installs the application launcher
* Creates the Desktop shortcut
* Hides `Return.desktop`
* Configures sudoers
* Reloads systemd

After installation:

* Launch **Enter Gaming Mode** from the application launcher (Category: **System**)
* Or click `Enter.desktop` on your Desktop

---

## Usage

### Enter Gaming Mode

Use either:

* Desktop shortcut: `Enter.desktop`
* Application launcher: **Enter Gaming Mode**

This:

1. Updates SDDM configuration as needed
2. Enables temporary autologin for Gaming Mode
3. Logs out of Plasma
4. Boots into Gamescope

### Return to Desktop

Exit Gaming Mode normally.

You will return to the standard Plasma login screen with password prompt.

---

## Uninstall

From the project directory:

```bash
chmod +x uninstall-desktop-login.sh
./uninstall-desktop-login.sh
```

The uninstaller removes:

* `/usr/local/bin/enter-gamemode.sh`
* `/etc/systemd/system/enter-gamemode.service`
* `/etc/sudoers.d/enter-gamemode`
* `/usr/local/share/wayland-sessions/00-plasma.desktop`
* Installed application launcher (`enter-gamemode.desktop`)
* Desktop shortcut `~/Desktop/Enter.desktop`
* Restores `~/Desktop/Return.desktop` from `.Return.desktop`
* Reloads systemd

It intentionally does **not** remove `zz-steamos-autologin.conf`, as that file is also managed by Steam/SteamOS components.

---

## Files Installed

### System

* `/usr/local/bin/enter-gamemode.sh`
* `/etc/systemd/system/enter-gamemode.service`
* `/etc/sudoers.d/enter-gamemode`
* `/usr/local/share/wayland-sessions/00-plasma.desktop`

### Application Launcher

* `/usr/share/applications/enter-gamemode.desktop`

  * Falls back to `~/.local/share/applications/` if needed

### Desktop

* `~/Desktop/Enter.desktop`
* `~/Desktop/Return.desktop` → renamed to `~/.Return.desktop`

### SDDM Configuration (used by the service)

* `/etc/sddm.conf.d/yy-default-session-override.conf`
* `/etc/sddm.conf.d/zz-steamos-autologin.conf` (updated when required)

---

## How It Works (High-Level)

* Uses a systemd oneshot service to coordinate the transition
* Temporarily configures SDDM autologin for Gamescope
* Logs out the current Plasma session
* Ensures Plasma remains the default login session
* Uses a sudoers drop-in to avoid password prompts when launching

No files in `/usr/share` are modified directly.

---

## License

Apache License 2.0
