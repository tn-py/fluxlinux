#!/bin/sh

# Helpers live in flux_guest_common.sh (prepended by flux_install /
# familySetupPayload). Source it only when this file is run standalone.
if ! command -v _flux_setup_pulse >/dev/null 2>&1; then
    _here=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
    for _common in \
        "${_here}/flux_guest_common.sh" \
        "${HOME:-}/flux_guest_common.sh" \
        /tmp/flux_guest_common.sh
    do
        if [ -f "$_common" ]; then
            # shellcheck source=/dev/null
            . "$_common"
            break
        fi
    done
fi

# setup_omarchy_family.sh — Omarchy-style guest on Arch Linux ARM.
#
# WHAT THIS IS NOT: upstream Omarchy (omarchy.org). Upstream is x86_64-only and
# its installer hard-requires limine, a btrfs root, systemd and SDDM — its own
# install/preflight/guard.sh aborts on aarch64 — and its desktop is Hyprland, a
# Wayland compositor. FluxLinux guests draw on the Lorie X server via
# termux-x11, and Hyprland's backend library (aquamarine) has DRM, nested
# Wayland and headless backends but no X11 one, so Hyprland cannot attach to
# our display at all.
#
# WHAT THIS IS: Omarchy's portable half on the display server we actually have.
# Same Arch Linux ARM base as the archlinux card, same pacman bootstrap, but i3
# stands in for Hyprland and polybar/rofi/dunst for waybar/walker/mako. The CLI
# and TUI stack (neovim, lazygit, btop, eza, bat, fd, ripgrep, fzf, zoxide,
# starship, fastfetch) is the same software Omarchy ships, because all of it is
# packaged for aarch64.
#
# Never rewrite mirrors to Manjaro arm-stable, x86_64 Arch, or Omarchy's own
# mirror (stable-mirror.omarchy.org is x86_64-only and would break every
# subsequent pacman call). Keep ALARM: Server = http://mirror.archlinuxarm.org/
# $arch/$repo. User alarm occupies uid 1000 — rename to flux.

DISTRO_NAME="${1:-omarchy}"
echo "FluxLinux: Configuring ${DISTRO_NAME} (Omarchy-style / Arch family)..."

if [ "$(id -u)" -ne 0 ]; then
    echo "FluxLinux: ERROR: must run as root inside the guest (got uid=$(id -u))."
    exit 1
fi

export SYSTEMD_OFFLINE=1
unset LC_ALL
export LANG=C

_flux_ensure_tmp
_flux_ensure_dns

if ! command -v pacman >/dev/null 2>&1; then
    echo "FluxLinux: ERROR: pacman not found"
    exit 1
fi

# POSIX rewrites — slim ALARM may not have GNU sed.
_flux_comment_matching() {
    _cf="$1"
    _px="$2"
    [ -f "$_cf" ] || return 0
    _tmp="${_cf}.fluxnew.$$"
    while IFS= read -r _ln || [ -n "$_ln" ]; do
        case "$_ln" in
            "${_px}"*) printf '#%s\n' "$_ln" ;;
            *) printf '%s\n' "$_ln" ;;
        esac
    done < "$_cf" > "$_tmp" && mv -f "$_tmp" "$_cf"
}

_flux_replace_matching() {
    _cf="$1"
    _px="$2"
    _nw="$3"
    [ -f "$_cf" ] || return 0
    _tmp="${_cf}.fluxnew.$$"
    _hit=0
    while IFS= read -r _ln || [ -n "$_ln" ]; do
        case "$_ln" in
            "${_px}"*)
                printf '%s\n' "$_nw"
                _hit=1
                ;;
            *) printf '%s\n' "$_ln" ;;
        esac
    done < "$_cf" > "$_tmp"
    [ "$_hit" = 1 ] || printf '%s\n' "$_nw" >> "$_tmp"
    mv -f "$_tmp" "$_cf"
}

_flux_delete_matching() {
    _cf="$1"
    _px="$2"
    [ -f "$_cf" ] || return 0
    _tmp="${_cf}.fluxnew.$$"
    while IFS= read -r _ln || [ -n "$_ln" ]; do
        case "$_ln" in
            "${_px}"*) ;;
            *) printf '%s\n' "$_ln" ;;
        esac
    done < "$_cf" > "$_tmp" && mv -f "$_tmp" "$_cf"
}

# CheckSpace + Android bind mounts lie about free space (Manjaro lesson).
if grep -q '^CheckSpace' /etc/pacman.conf 2>/dev/null; then
    _flux_comment_matching /etc/pacman.conf CheckSpace
    _flux_log "CheckSpace disabled (Android bind mounts lie about free space)"
fi
mkdir -p /var/cache/pacman/pkg /var/lib/pacman

# Pacman 7 on Android/proot: Landlock is missing and DownloadUser=alpm cannot
# switch sandbox user → "failed to synchronize all databases".
if ! grep -q '^DisableSandbox' /etc/pacman.conf 2>/dev/null; then
    echo 'DisableSandbox' >> /etc/pacman.conf
    _flux_log "DisableSandbox enabled (Android kernel has no Landlock / alpm)"
fi
_flux_comment_matching /etc/pacman.conf DownloadUser

# Keep the ALARM mirrorlist. Omarchy's mirror serves x86_64 only.
if [ ! -s /etc/pacman.d/mirrorlist ] || ! grep -q 'archlinuxarm' /etc/pacman.d/mirrorlist 2>/dev/null; then
    printf 'Server = http://mirror.archlinuxarm.org/$arch/$repo\n' > /etc/pacman.d/mirrorlist
fi

# pacman-key is the #1 landmine: /etc/pacman.d/gnupg is empty after slim.
_flux_log "pacman-key --init (needs entropy — this can take a while)..."
mkdir -p /etc/pacman.d/gnupg
pacman-key --init || {
    _flux_log "pacman-key --init failed once — retrying"
    if command -v rngd >/dev/null 2>&1; then
        rngd -r /dev/urandom 2>/dev/null &
        sleep 2
    fi
    pacman-key --init || true
}
_keyring_ok=0
if pacman-key --populate archlinuxarm 2>/dev/null; then
    _keyring_ok=1
fi
pacman-key --populate archlinux 2>/dev/null || true

if [ "$_keyring_ok" = 0 ]; then
    # Temporary SigLevel=Never, refresh keyring packages, restore Required
    # DatabaseOptional. NEVER leave SigLevel=Never permanent.
    _flux_log "keyring populate failed — temporary SigLevel=Never keyring refresh"
    _had_sig=""
    if grep -q '^SigLevel' /etc/pacman.conf 2>/dev/null; then
        _had_sig="$(grep '^SigLevel' /etc/pacman.conf | head -1)"
    fi
    _flux_replace_matching /etc/pacman.conf SigLevel 'SigLevel = Never'
    pacman -Sy --noconfirm archlinuxarm-keyring 2>/dev/null || true
    pacman -S --noconfirm --needed archlinux-keyring 2>/dev/null || true
    if [ -n "$_had_sig" ]; then
        _flux_replace_matching /etc/pacman.conf 'SigLevel = Never' "$_had_sig"
    else
        _flux_delete_matching /etc/pacman.conf 'SigLevel = Never'
        echo 'SigLevel = Required DatabaseOptional' >> /etc/pacman.conf
    fi
    pacman-key --populate archlinuxarm 2>/dev/null || true
    pacman-key --populate archlinux 2>/dev/null || true
fi

_flux_ensure_groups

_flux_log "pacman -Sy..."
if ! pacman -Sy --noconfirm; then
    echo "FluxLinux: pacman -Sy failed (repos/network)"
    exit 1
fi

# ── Core: without these there is no session. Failure aborts the install. ──
_flux_log "Installing i3 desktop core..."
if ! pacman -S --noconfirm --needed \
    sudo git zsh python sed gzip xz \
    i3-wm i3lock \
    xorg-xrandr xorg-xsetroot xorg-xprop xorg-xset \
    rofi dunst picom feh \
    alacritty \
    ttf-dejavu adwaita-icon-theme \
    mesa mesa-utils \
    dbus; then
    echo "FluxLinux: i3 desktop core install failed"
    exit 1
fi

# ── Omarchy flavour: nice to have, never fatal. A single missing aarch64
# build must not cost the user the whole guest, so these install one at a
# time and only warn. Same software Omarchy ships, minus everything Wayland.
_flux_omarchy_optional() {
    for _pkg in "$@"; do
        if pacman -S --noconfirm --needed "$_pkg" >/dev/null 2>&1; then
            _flux_log "  [+] $_pkg"
        else
            _flux_log "  [!] $_pkg unavailable on aarch64 — skipped"
        fi
    done
}

_flux_log "Installing Omarchy CLI/TUI stack (best effort)..."
_flux_omarchy_optional \
    polybar \
    neovim tmux lazygit github-cli \
    btop fastfetch \
    eza bat fd ripgrep fzf zoxide starship \
    jq less unzip wget man-db \
    imagemagick imv \
    xclip xdotool \
    ttf-jetbrains-mono-nerd papirus-icon-theme \
    kvantum

_flux_ensure_dbus

# User alarm occupies uid 1000. Prefer rename so home/files stay.
if id alarm >/dev/null 2>&1 && ! id flux >/dev/null 2>&1; then
    _flux_log "Renaming alarm → flux (uid 1000)"
    usermod -l flux -d /home/flux -m alarm 2>/dev/null \
        || { userdel -r alarm 2>/dev/null || true; }
fi
# Chroot can leave both (usermod -l no-op + useradd flux=1001). One uid 1000.
if id alarm >/dev/null 2>&1 && id flux >/dev/null 2>&1; then
    _flux_log "Removing leftover alarm (flux already exists)"
    userdel -r alarm 2>/dev/null || userdel alarm 2>/dev/null || true
fi
if id flux >/dev/null 2>&1 && ! id -u 1000 >/dev/null 2>&1; then
    usermod -u 1000 -d /home/flux flux 2>/dev/null || true
fi

_flux_require_i3
_flux_ensure_user
echo "flux:flux" | chpasswd 2>/dev/null || true
if command -v usermod >/dev/null 2>&1; then
    usermod -aG wheel,audio,video,input,users flux 2>/dev/null || true
fi
_flux_ensure_sudo
_flux_ensure_home

# ── Session launcher. start_gui.sh / start_guest_gui.sh exec this name; i3
# has no equivalent of startxfce4 that would bring up a bar or notifications.
_flux_log "Installing flux-i3-session launcher"
mkdir -p /usr/local/bin
cat > /usr/local/bin/flux-i3-session <<'SESSION_EOF'
#!/bin/sh
# FluxLinux: bring up the i3 session pieces, then hand the terminal to i3.
# Every helper is optional — a missing bar must never cost the user their WM.
export XDG_CURRENT_DESKTOP=i3
export XDG_SESSION_TYPE=x11

# Wallpaper before the bar so there is no white flash.
if command -v feh >/dev/null 2>&1 && [ -r "$HOME/.config/flux/wallpaper.png" ]; then
    feh --no-fehbg --bg-fill "$HOME/.config/flux/wallpaper.png" 2>/dev/null || true
elif command -v xsetroot >/dev/null 2>&1; then
    xsetroot -solid '#1a1b26' 2>/dev/null || true
fi

# picom costs more than it gives under llvmpipe/virgl. Only compose when the
# guest was set up for Turnip (real Adreno via Zink).
_gpu=virgl
[ -r /etc/fluxlinux/gpu_mode ] && _gpu=$(tr -d '[:space:]' </etc/fluxlinux/gpu_mode)
if [ "$_gpu" = turnip ] && command -v picom >/dev/null 2>&1; then
    picom --daemon 2>/dev/null || true
fi

command -v dunst >/dev/null 2>&1 && dunst >/dev/null 2>&1 &

if command -v polybar >/dev/null 2>&1 && [ -r "$HOME/.config/polybar/config.ini" ]; then
    polybar --reload flux >/dev/null 2>&1 &
fi

exec i3
SESSION_EOF
chmod 755 /usr/local/bin/flux-i3-session

# ── Baseline i3 config. Without a config i3 launches i3-config-wizard, which
# waits on a keypress and looks like a hang on a phone. The customization
# script layers the Omarchy palette on top of this; this file alone is enough
# for a usable session if customization is skipped or fails.
_flux_log "Writing baseline i3 config"
mkdir -p /home/flux/.config/i3
cat > /home/flux/.config/i3/config <<'I3_EOF'
# FluxLinux baseline i3 config (Omarchy-style guest).
# Mod4 is Super. On a phone keyboard Super is often unavailable, so every
# binding below is also reachable with Mod1 (Alt) where it does not collide.
set $mod Mod4
set $alt Mod1

font pango:JetBrainsMono Nerd Font 10

# Tokyo Night (Omarchy's default palette)
set $bg      #1a1b26
set $fg      #c0caf5
set $accent  #7aa2f7
set $urgent  #f7768e
set $inactive #414868

#                       border   background text     indicator child_border
client.focused          $accent  $accent    $bg      $accent   $accent
client.focused_inactive $inactive $inactive $fg      $inactive $inactive
client.unfocused        $bg      $bg        $fg      $bg       $inactive
client.urgent           $urgent  $urgent    $bg      $urgent   $urgent

default_border pixel 2
gaps inner 6
gaps outer 2

bindsym $mod+Return exec alacritty
bindsym $alt+Return exec alacritty
bindsym $mod+q kill
bindsym $alt+q kill
bindsym $mod+d exec --no-startup-id rofi -show drun
bindsym $alt+d exec --no-startup-id rofi -show drun

bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right

bindsym $mod+Shift+h move left
bindsym $mod+Shift+j move down
bindsym $mod+Shift+k move up
bindsym $mod+Shift+l move right

bindsym $mod+f fullscreen toggle
bindsym $mod+v split v
bindsym $mod+b split h
bindsym $mod+space floating toggle

bindsym $mod+1 workspace number 1
bindsym $mod+2 workspace number 2
bindsym $mod+3 workspace number 3
bindsym $mod+4 workspace number 4
bindsym $mod+5 workspace number 5
bindsym $mod+Shift+1 move container to workspace number 1
bindsym $mod+Shift+2 move container to workspace number 2
bindsym $mod+Shift+3 move container to workspace number 3
bindsym $mod+Shift+4 move container to workspace number 4
bindsym $mod+Shift+5 move container to workspace number 5

bindsym $mod+Shift+r restart
bindsym $mod+Shift+e exit

mode "resize" {
    bindsym h resize shrink width 10 px or 10 ppt
    bindsym j resize grow height 10 px or 10 ppt
    bindsym k resize shrink height 10 px or 10 ppt
    bindsym l resize grow width 10 px or 10 ppt
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym $mod+r mode "resize"

# No bar block: flux-i3-session starts polybar. i3bar would double up.
I3_EOF

chown -R flux:flux /home/flux/.config 2>/dev/null || true

_flux_setup_pulse
_flux_ensure_en_us_locale || exit 1
_flux_write_gpu_mode virgl
_flux_write_session i3
_flux_fix_pm_writable

echo "FluxLinux: ${DISTRO_NAME} Omarchy-style setup complete!"
exit 0
