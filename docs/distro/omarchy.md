# Omarchy-style guest in FluxLinux

| | |
|---|---|
| Cards | `omarchy` (proot) · `omarchy_chroot` (`/data/local/tmp/chrootOmarchy`) |
| Rootfs | `archlinux_arm_rootfs.tar.xz` — the **same** archive the `archlinux` cards use |
| Package manager | `pacman` |
| Desktop | **i3** + polybar + rofi + dunst + picom, Tokyo Night |
| Session marker | `/etc/fluxlinux/session` = `i3` |
| User | `flux` / `flux` (renamed from `alarm` uid 1000) |
| Repos | ALARM `http://mirror.archlinuxarm.org/$arch/$repo` |

## What this is, and what it is not

This is **not** upstream [Omarchy](https://omarchy.org). It is an Omarchy-*style*
guest: the same Arch Linux ARM base the `archlinux` cards use, dressed in
Omarchy's palette and shipping the parts of Omarchy's toolchain that have
aarch64 builds. The name on the card says "Omarchy-style (Arch)" for that
reason.

Upstream cannot be installed here, and not for want of effort. Its own
`install/preflight/guard.sh` aborts on four independent grounds that all hold
for a FluxLinux guest:

| Upstream guard | Why it fails here |
|---|---|
| `uname -m` must be `x86_64` | FluxLinux guests are aarch64 |
| `limine` bootloader present | A proot/chroot guest has no bootloader |
| root filesystem must be `btrfs` | The rootfs is a tarball on Android bind mounts |
| Secure Boot state via `bootctl` | No `systemd`, no EFI |

Past the guards, `install/login/all.sh` installs SDDM, Plymouth, hibernation and
limine-snapper hooks — all `systemctl enable` against an init that does not run
in a container — and `boot.sh` rewrites `/etc/pacman.d/mirrorlist` to
`https://stable-mirror.omarchy.org/$repo/os/$arch`, which serves x86_64 only.
Pointing an ALARM guest at it breaks every later `pacman` call.

### The Hyprland problem

The deeper blocker is the compositor. Omarchy's desktop is Hyprland, a **Wayland**
compositor. FluxLinux guests draw on the Lorie X server shipped inside the app
(`termux-x11`), which speaks X11. Hyprland's backend library,
[aquamarine](https://wiki.hypr.land/Hypr-Ecosystem/aquamarine/), offers a DRM/KMS
backend, a nested **Wayland** backend, and a headless backend — and no X11
backend. There is nothing for Hyprland to attach to:

- **DRM/KMS** — a proot guest has no DRM master on Android.
- **Nested Wayland** — there is no host Wayland compositor to nest inside.
- **Headless** — runs, but renders to nothing; putting it on screen needs
  `wayvnc` plus a VNC client composited back into the X display. That is a
  second display path, and double compositing on a phone.

So i3 stands in for Hyprland, and polybar, rofi and dunst stand in for waybar,
walker and mako. The headless + VNC route is a real option for a later change,
but it is a display-stack project, not a distro entry.

## What actually ships

**Desktop (core — install fails if any is missing):** `i3-wm`, `i3lock`, `rofi`,
`dunst`, `picom`, `feh`, `alacritty`, `xorg-xrandr`, `xorg-xsetroot`,
`xorg-xprop`, `xorg-xset`, `mesa`, `mesa-utils`, `dbus`.

**Omarchy toolchain (best effort — a missing aarch64 build is skipped with a
warning, never fatal):** `polybar`, `neovim`, `tmux`, `lazygit`, `github-cli`,
`btop`, `fastfetch`, `eza`, `bat`, `fd`, `ripgrep`, `fzf`, `zoxide`, `starship`,
`imagemagick`, `imv`, `xclip`, `xdotool`, `ttf-jetbrains-mono-nerd`,
`papirus-icon-theme`, `kvantum`.

**Deliberately absent:** `hyprland`, `waybar`, `hyprlock`, `hypridle`, `uwsm`,
`walker`, `sddm`, `plymouth` — Wayland-only, systemd-only, or with no ALARM
aarch64 build. `OmarchyScriptContractTest` fails the build if one is added.

## The session marker

Every guest before this one ran XFCE, so the start scripts hardcoded
`startxfce4`. Omarchy made the desktop a real axis, handled the same way GPU
mode already is — a file in the rootfs:

```
/etc/fluxlinux/session   →   "xfce" (default) | "i3"
```

`setup_omarchy_family.sh` writes `i3` via `_flux_write_session`. Both
`start_gui.sh` (proot) and `start_guest_gui.sh` (chroot) read it and exec either
`startxfce4` or `flux-i3-session`. **An absent file means `xfce`**, so guests
installed before this change keep launching exactly as they did.

On the app side, `GuestSessionCatalog` is the Kotlin half of the same SSOT: it
decides which session a card installs and which binaries prove it installed, so
onboarding can no longer report success for a guest with nothing to launch.

`flux-i3-session` is a wrapper, not a package: i3 alone brings up no bar, no
notifications and no wallpaper. It sets the wallpaper (or a solid fill), starts
`dunst`, starts `polybar` **only** when a config exists, starts `picom` **only**
under Turnip — compositing costs more than it gives on llvmpipe/virgl — and then
`exec i3`. Every helper is optional; a missing bar never costs the user their WM.

## Keybindings

Written by the family setup script to `~/.config/i3/config`, which also stops
bare i3 from launching `i3-config-wizard` — it blocks on a keypress and reads as
a hang on a phone. Customization rewrites only the palette lines, so re-running
it never costs you your bindings.

| Key | Action |
|---|---|
| `Super`/`Alt` + `Return` | alacritty |
| `Super`/`Alt` + `Q` | close window |
| `Super`/`Alt` + `D` | rofi launcher |
| `Super` + `H`/`J`/`K`/`L` | focus |
| `Super` + `Shift` + `H`/`J`/`K`/`L` | move |
| `Super` + `F` | fullscreen |
| `Super` + `1`…`5` | workspace |
| `Super` + `R` | resize mode |
| `Super` + `Shift` + `R` / `E` | restart / exit |

Alt duplicates the common bindings because many Android keyboards have no Super.

## Rootfs

`omarchy` deliberately shares `ARCH_ROOTFS_*` with `archlinux`: one release
asset, one SHA to keep in step, no Step 5.5 upload
([docs/adding_new_distro.md](../adding_new_distro.md)). Only the family and
customization scripts differ. The proot container (`omarchy`) and chroot path
(`/data/local/tmp/chrootOmarchy`) are distinct, so installing one never touches
the other — you can run both cards side by side.

If the two ever need different bytes, a **new** archive must be uploaded under a
new filename and pinned separately; never repoint one SHA at changed bytes.
