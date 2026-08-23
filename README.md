# Bazzite Desktop Login

A small utility for **Bazzite (KDE/Plasma)** that keeps the system booting to the normal **desktop login (password prompt)** while still providing a simple way to switch into **Gaming Mode (Gamescope)** from the desktop.

Works with both display managers Bazzite has shipped:

| Display manager | Bazzite images | Config directory |
| --- | --- | --- |
| `plasmalogin` (Plasma Login Manager 6.7+) | `44.20260820` and later | `/etc/plasmalogin.conf.d/` |
| `sddm` | earlier images | `/etc/sddm.conf.d/` |

The display manager is detected at runtime by probing for the **binary** (`/usr/bin/plasmalogin`, then `/usr/bin/sddm`). It deliberately does *not* test for the config directory: `/etc/sddm.conf.d/` survives the migration to plasmalogin as a stale leftover, so testing for it would write the autologin config somewhere nothing reads.

---

## What This Project Does

When installed, this project:

* Installs a **systemd oneshot service**: `enter-gamemode.service`
* Installs a launcher: **Enter Gaming Mode** (Category: `System`) to `~/.local/share/applications/`
* Installs `/usr/local/bin/ensure-bazzite-desktop-login.sh` and `/usr/local/bin/bazzite-clear-autologin.sh`
* Creates a desktop shortcut: `~/Desktop/Enter.desktop`
* Disarms autologin so the first reboot shows the Plasma login prompt
* Temporarily arms a **one-shot** autologin only when switching to Gaming Mode
* Logs out of Plasma to allow Gamescope to start
* Hides the default `Return.desktop` icon by renaming it to `~/Desktop/.Return.desktop`
* Adds a sudoers rule so the service can start without prompting for a password

It does **not** permanently modify Steam’s own configuration, and it never touches `zz-steamos-autologin.conf` or `zz-bazzite-autologin.conf` — those belong to Steam and Bazzite. This project owns exactly one drop-in, named `zz-bazzite-desktop-login-autologin.conf`.

---

## One-Shot Autologin, and why `Relogin=true` matters

Both plasmalogin and SDDM default to `Relogin=false`, which means **autologin fires only when the display manager first starts — at boot — and never when a session exits.** Logging out of Plasma therefore just lands on the greeter. So the armed config sets:

```ini
[Autologin]
Relogin=true
```

On its own that would loop: leave Gaming Mode and you get logged straight back into it.

What makes it safe is that the autologin is **disarmed as soon as Gaming Mode actually starts**, not when you return to the desktop. Disarming rewrites the whole drop-in, which removes `Relogin` along with `User` and `Session`. The interlock is: **`Relogin=true` only ever exists while the one-shot autologin is armed.**

Disarming is driven by a systemd user drop-in on the gamescope session *template*:

```
/etc/systemd/user/gamescope-session-plus@.service.d/10-clear-autologin.conf
```

```ini
[Service]
ExecStartPost=/usr/bin/sudo -n /usr/local/bin/bazzite-clear-autologin.sh
ExecStopPost=/usr/bin/sudo -n /usr/local/bin/bazzite-clear-autologin.sh
```

Two hooks on purpose: `ExecStartPost` is the normal path, `ExecStopPost` is the backstop that runs before the session ends if the first one somehow failed. Disarming is idempotent, so running it twice is harmless. Because both hook the template (`@.service`) rather than one instance, they apply to every client — `@ogui-steam`, `@steam`, and any future variant.

The practical effect: if you reboot, crash, or power off from Gaming Mode, the next boot still shows the login prompt. Autologin cannot get stuck on, which is the entire point of the project.

---

## Which Gaming Session Is Used

Session filenames have changed between Bazzite releases, so the project resolves them at runtime and uses the first that exists in `/usr/share/wayland-sessions/`:

1. `gamescope-session-ogui-steam.desktop` — Steam Big Picture Plus (OpenGamepadUI)
2. `gamescope-session-steam-plus.desktop`
3. `gamescope-session-steam.desktop` — plain Steam Big Picture
4. `gamescope-session.desktop` — pre-2026 Bazzite

Override with the `GAMEMODE_SESSION` environment variable:

```bash
sudo GAMEMODE_SESSION=gamescope-session-steam.desktop \
  /usr/local/bin/ensure-bazzite-desktop-login.sh "$USER" "$HOME" enter-gamemode
```

If nothing resolves, the script **fails loudly and refuses to log you out**. Writing a `Session=` that points at a missing file makes the display manager fall back to the greeter silently, which is indistinguishable from "Enter Gaming Mode did nothing" — the exact bug that motivated this rewrite.

---

## Supported Systems

* **Bazzite** KDE/Plasma

  * Base image name must be `kinoite`
  * The installer verifies this automatically

The GNOME variant (`silverblue`) is not supported.

---

## Installation

```bash
git clone https://github.com/steveonjava/Bazzite-Desktop-Login.git
cd Bazzite-Desktop-Login
chmod +x install-desktop-login.sh
./install-desktop-login.sh
```

After installation:

* Reboot to confirm the normal Plasma login prompt is shown first
* Launch **Enter Gaming Mode** from the application launcher (Category: **System**), or click `Enter.desktop` on your Desktop

---

## Usage

### Enter Gaming Mode

Use the desktop shortcut `Enter.desktop` or the **Enter Gaming Mode** launcher. This:

1. Resolves the gamescope session file
2. Arms a one-shot autologin in the detected display manager's config directory
3. Logs out of Plasma
4. Boots into Gamescope — and disarms the autologin again as soon as it starts

### Return to Desktop

Exit Gaming Mode normally. You return to the standard Plasma login screen with a password prompt.

---

## Uninstall

```bash
chmod +x uninstall-desktop-login.sh
./uninstall-desktop-login.sh
```

The uninstaller removes everything it installed, including the one-shot drop-in and our autologin drop-in from **both** config directories, so no stale autologin survives.

It intentionally does **not** remove `zz-steamos-autologin.conf` or `zz-bazzite-autologin.conf`, which are managed by Steam and Bazzite.

---

## Files Installed

### System

* `/usr/local/bin/ensure-bazzite-desktop-login.sh`
* `/usr/local/bin/bazzite-clear-autologin.sh`
* `/usr/local/bin/enter-gamemode.sh`
* `/etc/systemd/system/enter-gamemode.service`
* `/etc/systemd/user/gamescope-session-plus@.service.d/10-clear-autologin.conf`
* `/etc/sudoers.d/enter-gamemode`
* `/usr/local/share/wayland-sessions/00-plasma.desktop` *(SDDM only — an SDDM sort-order hack, not installed on plasmalogin)*

### Display Manager Configuration

* `/etc/plasmalogin.conf.d/zz-bazzite-desktop-login-autologin.conf`, or
* `/etc/sddm.conf.d/zz-bazzite-desktop-login-autologin.conf`

### Application Launcher

* `~/.local/share/applications/enter-gamemode.desktop`

### Desktop

* `~/Desktop/Enter.desktop`
* `~/Desktop/Return.desktop` → renamed to `~/Desktop/.Return.desktop`

---

## Troubleshooting

**Enter Gaming Mode drops me at the login screen.** Check that the autologin drop-in was armed:

```bash
cat /etc/plasmalogin.conf.d/zz-bazzite-desktop-login-autologin.conf
```

If `User=` is empty, arming failed — run the ensure script by hand to see the error. If it names a `Session=` that does not exist in `/usr/share/wayland-sessions/`, the display manager will silently fall back to the greeter.

**Enter Gaming Mode logs me out but returns to the greeter.** The armed drop-in is missing `Relogin=true`, or the display manager is not reading the directory the drop-in was written to. Confirm which directory applies with `ls /usr/bin/plasmalogin /usr/bin/sddm`, and check the armed file contains `Relogin=true` under `[Autologin]`.

**I keep getting logged straight back into Gaming Mode.** The one-shot disarm is not running, so `Relogin=true` is stuck on. Check that the sudoers rule works:

```bash
sudo -n /usr/local/bin/bazzite-clear-autologin.sh   # must print "Autologin disarmed" and exit 0
systemctl --user cat gamescope-session-plus@ogui-steam.service | grep clear-autologin
```

**I am stuck in a login loop.** SSH in and remove the drop-in:

```bash
sudo rm /etc/plasmalogin.conf.d/zz-bazzite-desktop-login-autologin.conf
sudo systemctl restart plasmalogin
```

**The greeter defaults to Big Picture instead of Plasma.** Add `RememberLastSession=false` under a `[Users]` section in the disarmed drop-in. It is set only while autologin is armed by default, so the greeter otherwise remembers the last session you used.

---

## Tests

```bash
./tests/test-ensure.sh
```

Runs without root and never writes to `/etc` — it sources the helper with the dispatch stripped and redirects the config writer to a temp file. Covers display-manager detection, session resolution and its failure cases, and the arm/disarm interlock that keeps `Relogin=true` from surviving past game-mode startup.

---

## License

Apache License 2.0
