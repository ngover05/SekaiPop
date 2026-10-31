#!/usr/bin/env bash
# install-deps-debian.sh: installs everything SekaiPop needs on Debian / Ubuntu / Linux Mint
# (anything with apt), the same job install-deps.sh does on Arch. install-deps.sh hands over to
# it by itself when there is no pacman, so ./install.sh and get.sh work the same everywhere.
#
# These distros don't package Hyprland 0.55+, Quickshell or a new enough Qt, so those come from
# Nix (nixpkgs), next to apt, never instead of it:
#   1. apt           services, PipeWire, NetworkManager, polkitd, portals, fonts, small tools
#   2. Nix           Hyprland, Quickshell, Qt 6, the Wayland tools (nix/flake.nix)
#   3. Nix glue      /run/opengl-driver (Mesa for Nix programs), the setuid helpers Nix's PAM and
#                    polkit look for, the Hyprland portal, Nix's fonts for the distro's apps
#   4. setup         services, groups, user folders, Google Sans Flex font
#   5. session       a "Hyprland (SekaiPop)" entry in the login screen (+ the merge-mode glue)
# Your current desktop (Cinnamon, GNOME, KDE...) stays as it is: pick it again at the login screen.
# It does not touch GPU drivers. NVIDIA's driver is not available to Nix programs this way.
#
# Usage:  ./install-deps-debian.sh [options]   (the same options as install-deps.sh)
#   --dry-run             show what would happen, change nothing
#   --yes                 no questions, pass -y to apt and --yes to the Nix installer
#   --core-only           only what the shell cannot start without
#   --with-optional       also songrec, mpvpaper, aubio, nwg-displays, node for Discord voice...
#   --no-desktop-layer    skip portals, file manager, fonts, keyring, icon theme (you already have a desktop)
#   --gpu amd|intel|nvidia|skip   only used to warn about NVIDIA (Mesa covers AMD and Intel)
#   --ddc                 set up i2c access for external-monitor brightness (ddcutil)
#   --file-manager dolphin|thunar|none   which file manager to add (default: the one you have, else thunar)
#   --no-update           don't upgrade the system or move the Nix packages to newer nixpkgs
#   --no-aur  --no-services  --no-fonts  --no-session      (--no-aur does nothing here)
#   -h, --help
#
# Run as your normal user (it uses sudo where needed). Run ./check-deps.sh afterwards.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)

DRY=0; YES=0; CORE_ONLY=0; WITH_OPT=0; DESKTOP=1; GPU=auto; DDC=0; FM=auto
UPDATE=1; SERVICES=1; FONTS=1; SESSION=1
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY=1 ;;
        --yes|-y) YES=1 ;;
        --core-only) CORE_ONLY=1 ;;
        --with-optional) WITH_OPT=1 ;;
        --no-desktop-layer) DESKTOP=0 ;;
        --gpu) shift; GPU=${1:-}; case "$GPU" in amd|intel|nvidia|skip) ;; *) echo "--gpu needs amd|intel|nvidia|skip" >&2; exit 2 ;; esac ;;
        --ddc) DDC=1 ;;
        --file-manager) shift; FM=${1:-}; case "$FM" in dolphin|thunar|none) ;; *) echo "--file-manager needs dolphin|thunar|none" >&2; exit 2 ;; esac ;;
        --no-update) UPDATE=0 ;;
        --no-aur) ;;
        --no-services) SERVICES=0 ;;
        --no-fonts) FONTS=0 ;;
        --no-session) SESSION=0 ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

# ---- look: the same style in install.sh, install-deps.sh, check-deps.sh and get.sh -------------
# Colours only on a terminal (NO_COLOR turns them off). On the bare Linux console (TERM=linux) or a
# non-UTF-8 locale the symbols fall back to plain ASCII, because a TTY font often can't draw them.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    B=$'\e[1m'; D=$'\e[2m'; Z=$'\e[0m'
    C=$'\e[38;5;80m'; PK=$'\e[38;5;211m'; Y=$'\e[38;5;221m'; R=$'\e[38;5;203m'; GR=$'\e[38;5;114m'
else B=; D=; Z=; C=; PK=; Y=; R=; GR=; fi
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) UI_UTF=1 ;; *) UI_UTF=0 ;; esac
[ "${TERM:-}" = linux ] && UI_UTF=0
if [ "$UI_UTF" = 1 ]; then
    G_OK='✔'; G_BAD='✘'; G_DOT='•'; G_ARR='›'; G_HR='─'; G_TL='╭'; G_TR='╮'; G_BL='╰'; G_BR='╯'; G_V='│'; G_NOTE='♪'
else
    G_OK='+'; G_BAD='x'; G_DOT='-'; G_ARR='>'; G_HR='-'; G_TL='+'; G_TR='+'; G_BL='+'; G_BR='+'; G_V='|'; G_NOTE='*'
fi
UI_W=$(tput cols 2>/dev/null || echo 72); case "$UI_W" in ''|*[!0-9]*) UI_W=72 ;; esac
[ "$UI_W" -gt 76 ] && UI_W=76; [ "$UI_W" -lt 56 ] && UI_W=56
UI_BW=50
rep() { local i s=""; for ((i = 0; i < $2; i++)); do s+=$1; done; printf '%s' "$s"; }
step() { local n=$((UI_W - ${#1} - 5)); [ "$n" -lt 3 ] && n=3
    printf '\n%s%s%s %s%s%s %s%s%s\n' "$C" "$G_HR$G_HR" "$Z" "$B" "$1" "$Z" "$D" "$(rep "$G_HR" "$n")" "$Z"; }
info() { printf '  %s%s%s %s\n' "$D" "$G_DOT" "$Z" "$1"; }
ok()   { printf '  %s%s%s %s\n' "$GR" "$G_OK" "$Z" "$1"; }
warn() { printf '  %s!%s %s%s%s\n' "$Y" "$Z" "$Y" "$1" "$Z"; }
FAILED=()
fail() { printf '  %s%s%s %s%s%s\n' "$R" "$G_BAD" "$Z" "$R" "$1" "$Z"; FAILED+=("$1"); }
boxrow() { local t=$1 col=${2:-} plain=${1//"$G_NOTE"/x} pad; pad=$((UI_BW - ${#plain})); [ "$pad" -lt 0 ] && pad=0
    printf '  %s%s%s%s%s%s%*s%s%s%s\n' "$PK" "$G_V" "$Z" "$col" "$t" "$Z" "$pad" "" "$PK" "$G_V" "$Z"; }
banner() { # banner <title> <subtitle>
    printf '\n  %s%s%s%s\n' "$PK" "$G_TL" "$(rep "$G_HR" "$UI_BW")" "$G_TR$Z"
    boxrow "  $G_NOTE  $1" "$B"
    boxrow "     $2" "$D"
    printf '  %s%s%s%s\n' "$PK" "$G_BL" "$(rep "$G_HR" "$UI_BW")" "$G_BR$Z"
}
result() { # result ok|bad <text>
    local col=$GR sym=$G_OK; [ "$1" = bad ] && { col=$R; sym=$G_BAD; }
    printf '\n  %s%s %s%s\n' "$col$B" "$sym" "$2" "$Z"
}
nx() { printf '  %s%s%s %s\n' "$PK" "$G_ARR" "$Z" "$1"; }

# when install.sh runs this, its steps are shown one level down so the numbering doesn't clash
if [ "${SEKAIPOP_FULL_INSTALL:-0}" = 1 ]; then
    step() { printf '\n  %s%s%s %s%s%s\n' "$C" "$G_ARR" "$Z" "$B" "$1" "$Z"; }
fi

# run <command...>: execute, or just print in --dry-run
run() {
    if [ "$DRY" = 1 ]; then printf '  %s%s%s %swould run%s' "$PK" "$G_ARR" "$Z" "$D" "$Z"; printf ' %q' "$@"; printf '\n'; return 0; fi
    "$@"
}
run_sh() { # run a shell snippet (needed for pipes / redirects)
    if [ "$DRY" = 1 ]; then printf '  %s%s%s %swould run%s %s\n' "$PK" "$G_ARR" "$Z" "$D" "$Z" "$1"; return 0; fi
    bash -c "$1"
}
ask() { # ask <question>: default yes in --yes and --dry-run
    [ "$YES" = 1 ] || [ "$DRY" = 1 ] && return 0
    local a; read -r -p "  ${PK}?${Z} $1 ${D}[Y/n]${Z} " a; case "$a" in n|N|no|No) return 1 ;; *) return 0 ;; esac
}
have() { command -v "$1" >/dev/null 2>&1; }
done_ok() { [ "$DRY" = 1 ] || ok "$1"; }   # ok, but not for what a dry run only printed

# ---------------------------------------------------------------- preconditions
[ "${SEKAIPOP_FULL_INSTALL:-0}" = 1 ] || banner "SekaiPop dependencies" "apt + Nix: packages, fonts, services"
step "Checking the system"
[ "$(id -u)" = 0 ] && { echo "Run this as your normal user, not root (it calls sudo itself)." >&2; exit 1; }
have apt-get   || { echo "apt-get not found: this installer is for Debian-based systems (install-deps.sh is the Arch one)." >&2; exit 1; }
have sudo      || { echo "sudo not found: install it first (apt install sudo) and add yourself to the sudo group." >&2; exit 1; }
have systemctl || { echo "systemd not found: the Nix setup here needs systemd (tmpfiles, logind)." >&2; exit 1; }
case "$(uname -m)" in x86_64|aarch64) ;; *) echo "Nix's packages here are for x86_64 and aarch64 only." >&2; exit 1 ;; esac
[ "$DRY" = 1 ] && info "DRY RUN: nothing will be changed."
ok "distro: $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}")"
[ -n "${XDG_CURRENT_DESKTOP:-}" ] && info "your current desktop ($XDG_CURRENT_DESKTOP) is kept: Hyprland is added next to it"

FLAKE_DIR="$HERE/nix"
[ -f "$FLAKE_DIR/flake.nix" ] || { echo "nix/flake.nix is missing next to this script." >&2; exit 1; }
SYS_PROFILE=/nix/var/nix/profiles/sekaipop-system
NIX_SH=/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# ---------------------------------------------------------------- package lists
# apt only gets what belongs to the system (daemons, setuid, PAM, fonts) or is fine at any version.
# Hyprland, Quickshell, Qt and the Wayland tools come from Nix (nix/flake.nix).
APT_CORE=(
  dbus polkitd systemd
  pipewire pipewire-bin wireplumber pipewire-pulse pulseaudio-utils
  network-manager bluez upower power-profiles-daemon
  libnotify-bin jq curl git xz-utils xdg-utils xdg-user-dirs fontconfig
  python3 python3-numpy
)
APT_DESKTOP=(
  xdg-desktop-portal xdg-desktop-portal-gtk
  gvfs adwaita-icon-theme
  fonts-noto-core fonts-noto-cjk fonts-noto-color-emoji
  gnome-keyring libsecret-1-0 pipewire-alsa
)
# Debian/Ubuntu's plasma-nm and kde-cli-tools are still KDE 5 (no kcmshell6), so the Wi-Fi and
# Bluetooth "Advanced" buttons use nm-connection-editor and blueman here.
APT_FEATURES=(
  tesseract-ocr tesseract-ocr-eng ffmpeg
  brightnessctl ddcutil zenity kitty
  network-manager-gnome blueman
  dconf-cli libglib2.0-bin x11-xserver-utils
  gnome-session-canberra sound-theme-freedesktop
)
APT_OPTIONAL=( python3-aubio nodejs )

NIX_TIER=sekaipop-full
[ "$CORE_ONLY" = 1 ] && NIX_TIER=sekaipop-core
[ "$WITH_OPT" = 1 ] && NIX_TIER=sekaipop-everything

WANT=("${APT_CORE[@]}")
if [ "$CORE_ONLY" = 0 ]; then
    [ "$DESKTOP" = 1 ] && WANT+=("${APT_DESKTOP[@]}")
    WANT+=("${APT_FEATURES[@]}")
fi
[ "$WITH_OPT" = 1 ] && WANT+=("${APT_OPTIONAL[@]}")

installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }

IS_KDE=0
installed plasma-integration && IS_KDE=1
[ "${QT_QPA_PLATFORMTHEME:-}" = kde ] && IS_KDE=1

if [ "$CORE_ONLY" = 0 ] && [ "$DESKTOP" = 1 ]; then
    if [ "$FM" = auto ]; then
        if [ "$IS_KDE" = 1 ] || installed dolphin; then FM=dolphin
        elif installed nemo; then FM=nemo
        elif installed nautilus; then FM=nautilus
        else FM=thunar; fi
    fi
    case "$FM" in
        dolphin) WANT+=(dolphin kio-extras ffmpegthumbs) ;;
        thunar)  WANT+=(thunar thunar-volman tumbler) ;;
    esac
    [ "$IS_KDE" = 0 ] && WANT+=(qt6ct)
    info "file manager: $FM   Qt theming: $([ "$IS_KDE" = 1 ] && echo 'KDE (qt6ct skipped)' || echo qt6ct)"
fi

if [ "$GPU" = auto ]; then
    GPU=skip
    for v in /sys/class/drm/card*/device/vendor; do
        [ -r "$v" ] || continue
        case "$(cat "$v")" in
            0x1002) GPU=amd; break ;;
            0x8086) GPU=intel ;;
            0x10de) [ "$GPU" = skip ] && GPU=nvidia ;;
        esac
    done
fi
info "GPU: $GPU   Nix packages: $NIX_TIER"
if [ "$GPU" = nvidia ]; then
    warn "NVIDIA detected: Nix programs get Mesa only, not NVIDIA's driver. Hyprland may not start on"
    warn "an NVIDIA-only machine this way (see nix-community/nixGL for a way around it)."
fi

# ---------------------------------------------------------------- 1. packages (apt)
step "1. Packages from apt"
APTFLAGS=(); [ "$YES" = 1 ] && APTFLAGS+=(-y)
run sudo apt-get update || warn "apt-get update failed: installing from the package lists you already have"
if [ "$UPDATE" = 1 ]; then
    if ask "Upgrade the system first (sudo apt-get upgrade)? Recommended."; then
        run sudo apt-get upgrade "${APTFLAGS[@]}" || fail "apt-get upgrade failed"
    fi
fi

APT=(); ALREADY=(); NOTFOUND=()
for p in "${WANT[@]}"; do
    if installed "$p"; then ALREADY+=("$p")
    elif apt-cache show "$p" >/dev/null 2>&1; then APT+=("$p")
    else NOTFOUND+=("$p"); fi
done
info "${#ALREADY[@]} already installed (kept as they are), ${#APT[@]} to install"
[ "${#APT[@]}" -gt 0 ] && info "apt: ${APT[*]}"
[ "${#NOTFOUND[@]}" -gt 0 ] && warn "not in your apt sources, skipped: ${NOTFOUND[*]}"
if [ "${#APT[@]}" -gt 0 ]; then
    if ! run sudo apt-get install "${APTFLAGS[@]}" "${APT[@]}"; then
        warn "the batch install failed, retrying one package at a time"
        for p in "${APT[@]}"; do
            run sudo apt-get install "${APTFLAGS[@]}" "$p" || fail "apt could not install $p"
        done
    fi
fi
[ "$WITH_OPT" = 1 ] && info "pnpm (Discord voice plugin) is not in apt: once node is in, run  corepack enable pnpm"

# ---------------------------------------------------------------- 2. Nix
step "2. Hyprland, Quickshell and Qt from Nix"
HAVE_NIX=1
if [ ! -x /nix/var/nix/profiles/default/bin/nix ] && ! have nix; then
    HAVE_NIX=0
    info "Nix isn't installed. It goes in /nix with its own daemon and leaves apt's packages alone."
    if ask "Install Nix now (the official multi-user installer from nixos.org)?"; then
        run_sh 'set -e; f=$(mktemp); curl -fsSL https://nixos.org/nix/install -o "$f"; sh "$f" --daemon'"$([ "$YES" = 1 ] && echo ' --yes')"'; rm -f "$f"' \
            && HAVE_NIX=1 || fail "the Nix installer failed"
    else
        fail "no Nix: Hyprland and Quickshell can't be installed on this distro without it"
    fi
fi

# This shell doesn't have Nix on PATH yet if it was only just installed.
[ -r "$NIX_SH" ] && . "$NIX_SH"
case ":$PATH:" in *":$HOME/.nix-profile/bin:"*) ;; *) PATH="$HOME/.nix-profile/bin:$PATH" ;; esac
NIX_BIN=nix; [ -x /nix/var/nix/profiles/default/bin/nix ] && NIX_BIN=/nix/var/nix/profiles/default/bin/nix
nixc() { run "$NIX_BIN" --extra-experimental-features "nix-command flakes" "$@"; }
# path: (not git+file:) so the flake is read as plain files, wherever this checkout came from.
FLAKE="path:$FLAKE_DIR"

if [ "$HAVE_NIX" = 1 ]; then
    if [ "$UPDATE" = 1 ] && [ -f "$FLAKE_DIR/flake.lock" ]; then
        nixc flake update --flake "$FLAKE" || warn "could not update nix/flake.lock: keeping the nixpkgs it names"
    fi

    # One profile entry: the tier you asked for replaces an older one.
    if [ "$DRY" = 0 ]; then
        mapfile -t OLD < <("$NIX_BIN" --extra-experimental-features "nix-command flakes" profile list --json 2>/dev/null \
            | jq -r '.elements | if type == "object" then keys[] else empty end' 2>/dev/null | grep -E '^sekaipop-')
    else
        OLD=()
    fi
    for e in "${OLD[@]}"; do nixc profile remove "$e" >/dev/null || warn "could not remove the old Nix entry $e"; done
    sub=install
    "$NIX_BIN" --extra-experimental-features "nix-command flakes" profile add --help >/dev/null 2>&1 && sub=add
    info "downloading from cache.nixos.org (the first time is a few GB)"
    nixc profile "$sub" "$FLAKE#$NIX_TIER" && done_ok "$NIX_TIER is in ~/.nix-profile" \
        || fail "nix profile $sub $NIX_TIER failed"

    # Root's copy uses the flake.lock written just above, so both come from the same nixpkgs.
    run sudo "$NIX_BIN" --extra-experimental-features "nix-command flakes" build --no-write-lock-file \
        --profile "$SYS_PROFILE" "$FLAKE#system" && done_ok "GPU drivers and portal: $SYS_PROFILE" \
        || fail "could not build $SYS_PROFILE"
fi

# ---------------------------------------------------------------- 3. glue for Nix programs
step "3. Linking Nix programs to this system"
if [ "$HAVE_NIX" = 1 ]; then
    # /run/opengl-driver and /run/wrappers/bin, made again on every boot by systemd-tmpfiles
    chkpwd=""; for f in /usr/sbin/unix_chkpwd /sbin/unix_chkpwd; do [ -x "$f" ] && { chkpwd=$f; break; }; done
    pkhelper=""; for f in /usr/lib/polkit-1/polkit-agent-helper-1 /usr/libexec/polkit-agent-helper-1 /usr/lib/policykit-1/polkit-agent-helper-1; do
        [ -x "$f" ] && { pkhelper=$f; break; }; done
    [ -n "$chkpwd" ] || fail "unix_chkpwd not found: the lockscreen won't be able to check your password"
    [ -n "$pkhelper" ] || fail "polkit-agent-helper-1 not found (is polkitd installed?): the shell's password prompts won't work"
    if [ -e /run/opengl-driver ] && [ "$(readlink /run/opengl-driver)" != "$SYS_PROFILE" ]; then
        warn "/run/opengl-driver already exists and points elsewhere ($(readlink /run/opengl-driver)): left as it is"
    fi
    tmpf=$(mktemp)
    sed -e "s|@UNIX_CHKPWD@|${chkpwd:-/usr/sbin/unix_chkpwd}|" -e "s|@POLKIT_HELPER@|${pkhelper:-/usr/lib/polkit-1/polkit-agent-helper-1}|" \
        "$FLAKE_DIR/sekaipop-nix.tmpfiles.conf" > "$tmpf"
    run sudo install -m 644 "$tmpf" /etc/tmpfiles.d/sekaipop-nix.conf
    rm -f "$tmpf"
    run sudo systemd-tmpfiles --create /etc/tmpfiles.d/sekaipop-nix.conf \
        && done_ok "/run/opengl-driver and /run/wrappers/bin (unix_chkpwd, polkit-agent-helper-1)" \
        || fail "systemd-tmpfiles could not make /run/opengl-driver and /run/wrappers"

    # The Hyprland portal (screen sharing), for the distro's xdg-desktop-portal and D-Bus to find.
    # The links go through the profile, so an update never leaves them pointing at old files.
    link_sys() { # link_sys <file in the profile> <link>
        local src="$SYS_PROFILE/$1" dst=$2
        if [ "$DRY" = 0 ] && [ ! -e "$src" ]; then warn "$src is missing, $dst not linked"; return; fi
        if [ -e "$dst" ] && [ ! -L "$dst" ]; then info "$dst is a real file (from a package?): left as it is"; return; fi
        run sudo mkdir -p "$(dirname "$dst")" && run sudo ln -sfn "$src" "$dst" || fail "could not link $dst"
    }
    link_sys share/xdg-desktop-portal/portals/hyprland.portal /usr/share/xdg-desktop-portal/portals/hyprland.portal
    link_sys share/xdg-desktop-portal/hyprland-portals.conf /usr/share/xdg-desktop-portal/hyprland-portals.conf
    link_sys share/dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service \
        /usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service
    unit=share/systemd/user/xdg-desktop-portal-hyprland.service
    [ -e "$SYS_PROFILE/lib/systemd/user/xdg-desktop-portal-hyprland.service" ] && unit=lib/systemd/user/xdg-desktop-portal-hyprland.service
    link_sys "$unit" /etc/systemd/user/xdg-desktop-portal-hyprland.service
    done_ok "Hyprland portal linked for xdg-desktop-portal"

    # The distro's apps (browsers, Discord...) only see fonts fontconfig is told about.
    fcdir="$HOME/.config/fontconfig/conf.d"; fcf="$fcdir/50-sekaipop-nix-fonts.conf"
    if [ -f "$fcf" ]; then
        info "Nix fonts are already visible to the distro's apps ($fcf)"
    else
        run mkdir -p "$fcdir"
        run_sh "printf '%s\n' '<?xml version=\"1.0\"?>' '<!DOCTYPE fontconfig SYSTEM \"fonts.dtd\">' '<!-- written by SekaiPop install-deps-debian.sh: the fonts Nix installed -->' '<fontconfig><dir>~/.nix-profile/share/fonts</dir></fontconfig>' > '$fcf'" \
            && done_ok "Nix fonts (Material Symbols, JetBrains Mono Nerd) added to fontconfig" || fail "could not write $fcf"
    fi
    have fc-cache && run fc-cache -f >/dev/null
else
    warn "skipped: no Nix"
fi

# ---------------------------------------------------------------- 4. setup
step "4. Setup (fonts, user folders, services, groups)"

if [ "$FONTS" = 1 ]; then
    if have fc-list && fc-list 2>/dev/null | grep -qi "Google Sans Flex"; then
        info "Google Sans Flex already installed"
    else
        info "installing Google Sans Flex (the same source end-4's installer uses)"
        run_sh 'set -e; d=$(mktemp -d); git clone --depth 1 --recurse-submodules https://github.com/end-4/google-sans-flex "$d/gsf"; mkdir -p "$HOME/.local/share/fonts/sekaipop-google-sans-flex"; cp -r "$d/gsf/." "$HOME/.local/share/fonts/sekaipop-google-sans-flex/"; rm -rf "$HOME/.local/share/fonts/sekaipop-google-sans-flex/.git"; fc-cache -f; rm -rf "$d"' \
            || fail "Google Sans Flex install failed (put the .ttf files in ~/.local/share/fonts by hand and run fc-cache -f)"
    fi
fi

have xdg-user-dirs-update && run xdg-user-dirs-update

if have xdg-mime && [ -z "$(xdg-mime query default inode/directory 2>/dev/null)" ]; then
    for fm in dolphin thunar org.gnome.Nautilus nemo pcmanfm; do
        if [ -f "/usr/share/applications/$fm.desktop" ] || [ -f "/usr/share/applications/org.kde.$fm.desktop" ]; then
            f="$fm.desktop"; [ -f "/usr/share/applications/org.kde.$fm.desktop" ] && f="org.kde.$fm.desktop"
            run xdg-mime default "$f" inode/directory; break
        fi
    done
fi

if [ "$SERVICES" = 1 ]; then
    for u in NetworkManager bluetooth upower power-profiles-daemon; do
        run sudo systemctl enable --now "$u" || fail "could not enable $u"
    done
    if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || [ -S "${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]; then
        run systemctl --user enable --now pipewire pipewire-pulse wireplumber || fail "could not enable the PipeWire user services"
    else
        warn "no user D-Bus session here: after you log in, run: systemctl --user enable --now pipewire pipewire-pulse wireplumber"
    fi
fi

run sudo usermod -aG video "$USER" || fail "could not add you to the video group"
if [ "$DDC" = 1 ]; then
    info "i2c access for ddcutil (external monitor brightness)"
    run sudo groupadd -f i2c
    run sudo usermod -aG i2c "$USER"
    run_sh 'echo i2c-dev | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null'
fi

# ---------------------------------------------------------------- 5. login session
step "5. Login session"
# Separate from a distro "hyprland.desktop", so a Hyprland package added later doesn't clash with it.
run sudo install -m 755 "$FLAKE_DIR/sekaipop-hyprland" /usr/local/bin/sekaipop-hyprland \
    && run sudo install -m 644 "$FLAKE_DIR/sekaipop-hyprland.desktop" /usr/share/wayland-sessions/sekaipop-hyprland.desktop \
    && done_ok "login screen entry: Hyprland (SekaiPop)" || fail "could not add the login session"

# ---------------------------------------------------------------- 3. session glue
step "6. Hyprland session glue"
if [ "$SESSION" = 1 ]; then
    HYPR="$HOME/.config/hypr"
    mode=""
    [ -f "$HYPR/hyprland.lua" ] && mode=lua
    [ -z "$mode" ] && [ -f "$HYPR/hyprland.conf" ] && mode=conf
    if [ -z "$mode" ]; then
        warn "no Hyprland config found in $HYPR: start Hyprland once so it creates one, then run this script again with just: ./install-deps.sh --no-update --core-only"
    else
        tmp=$(mktemp)
        autostart=1; grep -rqsE '(qs|quickshell)[[:space:]]+-c[[:space:]]+sekaipop' "$HYPR" 2>/dev/null && autostart=0
        qtline=1;    grep -rqs 'QT_QPA_PLATFORMTHEME' "$HYPR" 2>/dev/null && qtline=0
        have qt6ct || qtline=0
        [ -n "${QT_QPA_PLATFORMTHEME:-}" ] && qtline=0   # something already themes Qt apps (e.g. kde): don't override it
        [ "$IS_KDE" = 1 ] && qtline=0
        if [ "$mode" = lua ]; then
            f="$HYPR/sekaipop_session.lua"
            {
                echo '-- sekaipop_session.lua  (written by install-deps.sh; safe to edit or delete)'
                echo '-- Glue a bare Hyprland session needs so portals (screen sharing) and apps work.'
                echo 'hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")'
                [ "$qtline" = 1 ] && echo 'hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")'
                echo 'hl.on("hyprland.start", function()'
                echo '    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")'
                [ "$autostart" = 1 ] && echo '    hl.exec_cmd("qs -c sekaipop")'
                echo 'end)'
            } > "$tmp"
            reqline='pcall(require, "sekaipop_session")'
        else
            f="$HYPR/sekaipop_session.conf"
            {
                echo '# sekaipop_session.conf  (written by install-deps.sh; safe to edit or delete)'
                echo 'env = ELECTRON_OZONE_PLATFORM_HINT,auto'
                [ "$qtline" = 1 ] && echo 'env = QT_QPA_PLATFORMTHEME,qt6ct'
                echo 'exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP'
                [ "$autostart" = 1 ] && echo 'exec-once = qs -c sekaipop'
            } > "$tmp"
            reqline='source = ~/.config/hypr/sekaipop_session.conf'
        fi
        if [ -e "$f" ]; then
            if cmp -s "$tmp" "$f"; then
                info "$f is already up to date"
            else
                warn "$f already exists, left as it is (new version saved to $f.new)"
                run cp "$tmp" "$f.new"
            fi
            # an earlier run may have forced qt6ct onto a system whose Qt apps are themed by KDE: take that line out
            if [ "$IS_KDE" = 1 ] && grep -qsE 'QT_QPA_PLATFORMTHEME.*qt6ct' "$f"; then
                if ask "Remove the QT_QPA_PLATFORMTHEME=qt6ct line from $f (you use KDE theming)? A backup is saved."; then
                    run cp "$f" "$f.bak"
                    run sed -i -E '/QT_QPA_PLATFORMTHEME.*qt6ct/d' "$f"
                else
                    warn "delete the QT_QPA_PLATFORMTHEME line from $f yourself if Qt apps look wrong"
                fi
            fi
        else
            run cp "$tmp" "$f"
            [ "$DRY" = 1 ] || info "wrote $f"
        fi
        rm -f "$tmp"
        cfg="$HYPR/hyprland.$mode"
        if grep -qsF 'sekaipop_session' "$cfg"; then
            info "$cfg already loads sekaipop_session"
        elif ask "Add  $reqline  to $cfg (a backup is saved next to it)?"; then
            run cp "$cfg" "$cfg.sekaipop.bak"
            run_sh "printf '\\n%s\\n' '$reqline' >> '$cfg'"
            [ "$DRY" = 1 ] || info "added  $reqline  to $cfg"
        else
            warn "add this line to $cfg yourself:  $reqline"
        fi
        [ "$mode" = lua ] && ! grep -rqs 'sekaipop_overrides' "$HYPR/hyprland.lua" 2>/dev/null && \
            warn 'also add this line to hyprland.lua so the Settings-panel Hyprland changes survive reloads:  pcall(require, "sekaipop_overrides")'
    fi
fi


# ---------------------------------------------------------------- done
[ "${SEKAIPOP_FULL_INSTALL:-0}" = 1 ] || step "Done"
if [ "${#FAILED[@]}" -gt 0 ]; then
    printf '  %s%d problem(s):%s\n' "$R" "${#FAILED[@]}" "$Z"
    for m in "${FAILED[@]}"; do printf '    %s%s%s %s\n' "$R" "$G_BAD" "$Z" "$m"; done
fi
[ "${SEKAIPOP_FULL_INSTALL:-0}" = 1 ] && exit "${#FAILED[@]}"
if [ "${#FAILED[@]}" -eq 0 ]; then result ok "Dependencies are in place"; else result bad "Finished with ${#FAILED[@]} problem(s), see above"; fi
printf '\n  %sNext%s\n' "$B" "$Z"
nx "Log out, and pick ${B}Hyprland (SekaiPop)${Z} at the login screen (your old desktop is still there)."
nx "Copy the rice folder to ${B}~/.config/quickshell/sekaipop${Z} (./install.sh does it)."
nx "Run ${B}./check-deps.sh${Z}, it should end with \"core missing: 0\"."
nx "Updating later: run this again; Nix's packages and its GPU drivers are updated together."
[ "$DRY" = 1 ] || { [ -f "$HERE/check-deps.sh" ] && { printf '\n'; bash "$HERE/check-deps.sh" --core; }; }
[ "${#FAILED[@]}" -eq 0 ]
