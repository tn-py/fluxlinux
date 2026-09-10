#!/bin/sh
# setup_customization_omarchy.sh
# Omarchy-style branding for the i3 guest: Tokyo Night palette across alacritty,
# polybar, rofi, dunst and i3, plus the zsh + starship prompt Omarchy ships.
#
# Upstream Omarchy themes Wayland components (waybar, walker, mako, hyprlock).
# Those have no aarch64 X11 counterpart, so the palette is re-expressed for the
# X11 stack the family script installed. Colors are Omarchy's tokyo-night
# defaults so the guest reads as Omarchy even though the components differ.

CUSTOM_USER="flux"
CUSTOM_GROUP="flux"
USER_HOME="/home/$CUSTOM_USER"

echo "FluxLinux: Starting Omarchy-style customization..."

if [ "$(id -u)" -ne 0 ]; then
    echo "FluxLinux: ERROR: must run as root inside the guest (got uid=$(id -u))."
    exit 1
fi

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin${PATH:+:$PATH}"
unset LD_LIBRARY_PATH
unset LD_PRELOAD
mkdir -p /tmp /var/tmp
chmod 1777 /tmp /var/tmp 2>/dev/null || true
unset PROOT_TMP_DIR
export TMPDIR=/tmp

_flux_chown_r() { chown -R "$@" 2>/dev/null || true; }

# Bounded runner — a hung clone must never strand the install progress bar.
_flux_run() {
    _secs="$1"
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$_secs" "$@"
    else
        "$@"
    fi
}

_flux_git_clone() {
    _flux_run "$3" git clone --depth 1 --single-branch "$1" "$2"
}

# ── Palette ───────────────────────────────────────────────────────────────
# Omarchy's default theme is tokyo-night. FLUX_THEME=light swaps to a light
# variant so the app-level theme toggle still means something here.
if [ "${FLUX_THEME:-dark}" = "light" ]; then
    OMA_BG="#e6e7ed"; OMA_FG="#343b58"; OMA_ACCENT="#2e7de9"
    OMA_URGENT="#f52a65"; OMA_DIM="#a1a6c5"; OMA_ALT="#d6d8e0"
else
    OMA_BG="#1a1b26"; OMA_FG="#c0caf5"; OMA_ACCENT="#7aa2f7"
    OMA_URGENT="#f7768e"; OMA_DIM="#414868"; OMA_ALT="#24283b"
fi
echo "FluxLinux: Omarchy palette = ${FLUX_THEME:-dark} (bg $OMA_BG / accent $OMA_ACCENT)"

# JetBrains Mono Nerd Font is Omarchy's default; fall back to whatever the
# family script's ttf-dejavu left behind rather than naming a missing font.
OMA_FONT="JetBrainsMono Nerd Font"
if ! fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
    echo "FluxLinux: JetBrainsMono Nerd Font absent — falling back to DejaVu Sans Mono"
    OMA_FONT="DejaVu Sans Mono"
fi

mkdir -p "$USER_HOME/.config/alacritty" \
         "$USER_HOME/.config/polybar" \
         "$USER_HOME/.config/rofi" \
         "$USER_HOME/.config/dunst" \
         "$USER_HOME/.config/i3" \
         "$USER_HOME/.config/flux"

# ── alacritty ─────────────────────────────────────────────────────────────
echo "FluxLinux: Writing alacritty config"
cat > "$USER_HOME/.config/alacritty/alacritty.toml" <<ALACRITTY_EOF
[window]
padding = { x = 8, y = 8 }
opacity = 1.0
dynamic_title = true

[font]
size = 11.0
normal = { family = "$OMA_FONT", style = "Regular" }
bold = { family = "$OMA_FONT", style = "Bold" }

[colors.primary]
background = "$OMA_BG"
foreground = "$OMA_FG"

[colors.cursor]
cursor = "$OMA_ACCENT"
text = "$OMA_BG"

[colors.normal]
black   = "#15161e"
red     = "$OMA_URGENT"
green   = "#9ece6a"
yellow  = "#e0af68"
blue    = "$OMA_ACCENT"
magenta = "#bb9af7"
cyan    = "#7dcfff"
white   = "#a9b1d6"

[colors.bright]
black   = "$OMA_DIM"
red     = "#ff899d"
green   = "#9fe044"
yellow  = "#faba4a"
blue    = "#8db0ff"
magenta = "#c7a9ff"
cyan    = "#a4daff"
white   = "#c0caf5"
ALACRITTY_EOF

# ── polybar ───────────────────────────────────────────────────────────────
# Bar name must stay "flux": flux-i3-session runs `polybar --reload flux`.
echo "FluxLinux: Writing polybar config"
cat > "$USER_HOME/.config/polybar/config.ini" <<POLYBAR_EOF
[colors]
background = $OMA_BG
foreground = $OMA_FG
accent = $OMA_ACCENT
urgent = $OMA_URGENT
dim = $OMA_DIM

[bar/flux]
width = 100%
height = 26pt
radius = 0
background = \${colors.background}
foreground = \${colors.foreground}
line-size = 2pt
padding-left = 1
padding-right = 1
module-margin = 1
font-0 = $OMA_FONT:size=10;2
modules-left = i3
modules-right = cpu memory date
cursor-click = pointer
# No tray: termux-x11 has no system tray host, and a tray module that finds
# no host logs an error loop on every bar reload.
tray-position = none
enable-ipc = true

[module/i3]
type = internal/i3
pin-workspaces = false
show-urgent = true
strip-wsnumbers = true
format = <label-state><label-mode>
label-focused = %name%
label-focused-background = \${colors.accent}
label-focused-foreground = \${colors.background}
label-focused-padding = 1
label-unfocused = %name%
label-unfocused-padding = 1
label-urgent = %name%
label-urgent-background = \${colors.urgent}
label-urgent-foreground = \${colors.background}
label-urgent-padding = 1

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = "CPU "
format-prefix-foreground = \${colors.dim}
label = %percentage:2%%

[module/memory]
type = internal/memory
interval = 2
format-prefix = "RAM "
format-prefix-foreground = \${colors.dim}
label = %percentage_used:2%%

[module/date]
type = internal/date
interval = 30
date = %Y-%m-%d %H:%M
label = %date%
label-foreground = \${colors.accent}

[settings]
screenchange-reload = true
POLYBAR_EOF

# ── rofi ──────────────────────────────────────────────────────────────────
echo "FluxLinux: Writing rofi theme"
cat > "$USER_HOME/.config/rofi/config.rasi" <<ROFI_EOF
configuration {
    modi: "drun,run,window";
    show-icons: true;
    font: "$OMA_FONT 11";
    drun-display-format: "{name}";
}
* {
    bg:     $OMA_BG;
    bg-alt: $OMA_ALT;
    fg:     $OMA_FG;
    accent: $OMA_ACCENT;
    background-color: transparent;
    text-color: @fg;
}
window { background-color: @bg; border: 2px; border-color: @accent; border-radius: 8px; width: 46%; }
mainbox { children: [ inputbar, listview ]; padding: 10px; }
inputbar { children: [ prompt, entry ]; background-color: @bg-alt; padding: 8px; border-radius: 6px; }
prompt { text-color: @accent; padding: 0 8px 0 0; }
listview { lines: 8; padding: 8px 0 0 0; }
element { padding: 7px; border-radius: 6px; }
element selected { background-color: @accent; text-color: @bg; }
ROFI_EOF

# ── dunst ─────────────────────────────────────────────────────────────────
echo "FluxLinux: Writing dunst config"
cat > "$USER_HOME/.config/dunst/dunstrc" <<DUNST_EOF
[global]
    monitor = 0
    follow = none
    width = 320
    origin = top-right
    offset = 8x34
    padding = 10
    horizontal_padding = 10
    frame_width = 2
    frame_color = "$OMA_ACCENT"
    corner_radius = 8
    font = $OMA_FONT 10
    format = "<b>%s</b>\n%b"
    markup = full

[urgency_low]
    background = "$OMA_BG"
    foreground = "$OMA_DIM"
    timeout = 5

[urgency_normal]
    background = "$OMA_BG"
    foreground = "$OMA_FG"
    timeout = 8

[urgency_critical]
    background = "$OMA_URGENT"
    foreground = "$OMA_BG"
    frame_color = "$OMA_URGENT"
    timeout = 0
DUNST_EOF

# ── i3 palette overlay ────────────────────────────────────────────────────
# The family script wrote the keybindings; only the color block is themed here,
# so re-running customization can never cost the user their bindings.
if [ -f "$USER_HOME/.config/i3/config" ]; then
    echo "FluxLinux: Applying Omarchy palette to i3 config"
    _i3_tmp="$USER_HOME/.config/i3/config.fluxnew.$$"
    while IFS= read -r _ln || [ -n "$_ln" ]; do
        case "$_ln" in
            "set \$bg "*)       printf 'set $bg      %s\n' "$OMA_BG" ;;
            "set \$fg "*)       printf 'set $fg      %s\n' "$OMA_FG" ;;
            "set \$accent "*)   printf 'set $accent  %s\n' "$OMA_ACCENT" ;;
            "set \$urgent "*)   printf 'set $urgent  %s\n' "$OMA_URGENT" ;;
            "set \$inactive "*) printf 'set $inactive %s\n' "$OMA_DIM" ;;
            "font pango:"*)     printf 'font pango:%s 10\n' "$OMA_FONT" ;;
            *) printf '%s\n' "$_ln" ;;
        esac
    done < "$USER_HOME/.config/i3/config" > "$_i3_tmp" \
        && mv -f "$_i3_tmp" "$USER_HOME/.config/i3/config"
else
    echo "FluxLinux: WARNING: i3 config missing — re-run the family setup"
fi

# ── Wallpaper ─────────────────────────────────────────────────────────────
# flux-i3-session prefers this file and falls back to a solid xsetroot fill.
# A flat PPM converted by ImageMagick keeps this dependency-free; if
# ImageMagick is absent the session simply uses the xsetroot fallback.
if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
    echo "FluxLinux: Generating wallpaper"
    _conv=convert
    command -v magick >/dev/null 2>&1 && _conv=magick
    "$_conv" -size 1920x1080 "gradient:${OMA_BG}-${OMA_ALT}" \
        "$USER_HOME/.config/flux/wallpaper.png" 2>/dev/null \
        || echo "FluxLinux: WARNING: wallpaper generation failed — solid fill will be used"
else
    echo "FluxLinux: ImageMagick absent — session will use a solid background"
fi

# ── zsh + starship ────────────────────────────────────────────────────────
# Omarchy's prompt is starship on bash/zsh. Oh My Zsh is optional here: the
# .zshrc below works with or without it.
if [ "${FLUX_SKIP_OMZ:-0}" = "1" ]; then
    echo "FluxLinux: Oh My Zsh skip (FLUX_SKIP_OMZ=1)"
elif [ -f "$USER_HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then
    echo "FluxLinux: Oh My Zsh already present — skip"
elif command -v git >/dev/null 2>&1; then
    echo "FluxLinux: Installing Oh My Zsh (120s budget)…"
    rm -rf "$USER_HOME/.oh-my-zsh" 2>/dev/null || true
    _flux_git_clone "https://github.com/ohmyzsh/ohmyzsh.git" "$USER_HOME/.oh-my-zsh" 120 \
        || echo "FluxLinux: WARNING: Oh My Zsh clone failed — continuing without it"
    [ -f "$USER_HOME/.oh-my-zsh/oh-my-zsh.sh" ] || rm -rf "$USER_HOME/.oh-my-zsh" 2>/dev/null || true
else
    echo "FluxLinux: git unavailable — Oh My Zsh skipped"
fi

if command -v starship >/dev/null 2>&1; then
    echo "FluxLinux: Writing starship config"
    cat > "$USER_HOME/.config/starship.toml" <<STARSHIP_EOF
add_newline = false
format = "\$directory\$git_branch\$git_status\$character"

[directory]
style = "bold $OMA_ACCENT"
truncation_length = 3

[character]
success_symbol = "[❯](bold $OMA_ACCENT)"
error_symbol = "[❯](bold $OMA_URGENT)"

[git_branch]
style = "bold #bb9af7"
STARSHIP_EOF
fi

echo "FluxLinux: Writing .zshrc"
cat > "$USER_HOME/.zshrc" <<'ZSHRC_EOF'
# FluxLinux — Omarchy-style guest
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin"
export EDITOR=nvim
export TERM=${TERM:-xterm-256color}

if [ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then
    export ZSH="$HOME/.oh-my-zsh"
    ZSH_THEME=""
    plugins=(git)
    . "$ZSH/oh-my-zsh.sh"
fi

# Omarchy's aliases, on the tools that have aarch64 builds.
command -v eza >/dev/null 2>&1 && {
    alias ls='eza -lh --group-directories-first --icons=auto'
    alias ll='eza -lah --group-directories-first --icons=auto'
    alias lt='eza --tree --level=2 --long --icons=auto'
}
command -v bat >/dev/null 2>&1 && alias cat='bat --paging=never'
command -v fd  >/dev/null 2>&1 && alias find='fd'
command -v rg  >/dev/null 2>&1 && alias grep='rg'
command -v nvim >/dev/null 2>&1 && alias vim='nvim'
command -v lazygit >/dev/null 2>&1 && alias lg='lazygit'
alias ..='cd ..'
alias ...='cd ../..'

command -v zoxide   >/dev/null 2>&1 && eval "$(zoxide init zsh)"
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"
command -v fastfetch >/dev/null 2>&1 && fastfetch
ZSHRC_EOF

if command -v zsh >/dev/null 2>&1 && id "$CUSTOM_USER" >/dev/null 2>&1; then
    _zsh_path=$(command -v zsh)
    grep -qxF "$_zsh_path" /etc/shells 2>/dev/null || echo "$_zsh_path" >> /etc/shells
    chsh -s "$_zsh_path" "$CUSTOM_USER" 2>/dev/null \
        || usermod -s "$_zsh_path" "$CUSTOM_USER" 2>/dev/null || true
fi

# ── pokemon-colorscripts: optional, same 60s budget as the XFCE guests ────
if [ "${FLUX_SKIP_POKEMON:-0}" = "1" ]; then
    echo "FluxLinux: pokemon-colorscripts skip (FLUX_SKIP_POKEMON=1)"
elif command -v pokemon-colorscripts >/dev/null 2>&1; then
    echo "FluxLinux: pokemon-colorscripts already present — skip"
elif ! command -v git >/dev/null 2>&1; then
    echo "FluxLinux: pokemon-colorscripts skip (git missing)"
else
    echo "FluxLinux: Installing pokemon-colorscripts (optional, 60s budget)…"
    POKEMON_TEMP="/tmp/pokemon-colorscripts.$$"
    rm -rf "$POKEMON_TEMP" 2>/dev/null || true
    if _flux_git_clone "https://gitlab.com/phoneybadger/pokemon-colorscripts.git" "$POKEMON_TEMP" 60 \
        && [ -f "$POKEMON_TEMP/install.sh" ]; then
        (cd "$POKEMON_TEMP" && _flux_run 30 sh ./install.sh) \
            || echo "FluxLinux: WARNING: pokemon-colorscripts install.sh failed"
    else
        echo "FluxLinux: WARNING: pokemon-colorscripts skipped (clone timeout/fail)"
    fi
    rm -rf "$POKEMON_TEMP" 2>/dev/null || true
fi

# Ownership last: everything above ran as root inside the guest.
_flux_chown_r "$CUSTOM_USER:$CUSTOM_GROUP" "$USER_HOME"
chmod -R u+rwX "$USER_HOME/.config" 2>/dev/null || true

echo "FluxLinux: Omarchy-style customization complete!"
exit 0
