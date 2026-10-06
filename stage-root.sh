#!/usr/bin/env bash
set -euo pipefail

# System stage of the X Linux on WSL setup.
# Runs as root. Configures locale, keyboard, timezone, base tools and the
# sudo user for the distro. User-level environment is handled by stage-user.sh.

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SRC_DIR/lib/common.sh"
# shellcheck source=lib/ui.sh
source "$SRC_DIR/lib/ui.sh"

usage() {
    cat <<'EOF'
Usage: stage-root.sh [options]

Configures the WSL system: base tools, locale, keyboard, timezone and the
sudo user. Run as root (a fresh WSL import boots as root). Values can also
be given through X_LOCALE, X_KEYMAP, X_TIMEZONE, X_USER, X_SHELL, X_SUDO,
X_INSTALL and X_SET_DEFAULT_USER environment variables.

Options:
  --locale LOCALE   Locale to enable and set as LANG (default en_US.UTF-8).
  --keymap KEYMAP   Console keymap for /etc/vconsole.conf (default us).
  --timezone ZONE   IANA zone (for example Europe/Madrid), UTC, or
                    'windows-time' to follow the Windows clock (default).
  --user NAME       User to create or ensure with sudo (default SUDO_USER,
                    else 'x').
  --shell SHELL     Login shell for the user: zsh or bash (default zsh).
  --sudo POLICY     Sudo policy: nopasswd (default, recommended for WSL) or
                    password (prompted interactively).
  --no-install      Do not install base tools with pacman.
  -h, --help        Show this help.

Environment:
  X_DRY=1           Print the plan without applying changes.
  X_AUTO=1          Use defaults without prompting (requires no tty).
  X_SET_DEFAULT_USER=1|0
                    Pin the created user as the default user of new WSL
                    sessions in /etc/wsl.conf. Defaults to yes (1) unless
                    the file is absent; set 0 to keep logging in as root.
EOF
}

for a in "$@"; do
    case "$a" in
        -h | --help)
            usage
            exit 0
            ;;
    esac
done

x_require_root "$@"

LOCALE="${X_LOCALE:-}"
KEYMAP="${X_KEYMAP:-}"
TIMEZONE="${X_TIMEZONE:-}"
USER_NAME="${X_USER:-}"
SHELL_CHOICE="${X_SHELL:-}"
SUDO_POLICY="${X_SUDO:-}"
INSTALL_TOOLS="${X_INSTALL:-1}"

while (($# > 0)); do
    arg="$1"
    case "$arg" in
        --locale=*) LOCALE="${arg#*=}" ;;
        --keymap=*) KEYMAP="${arg#*=}" ;;
        --timezone=*) TIMEZONE="${arg#*=}" ;;
        --user=*) USER_NAME="${arg#*=}" ;;
        --shell=*) SHELL_CHOICE="${arg#*=}" ;;
        --sudo=*) SUDO_POLICY="${arg#*=}" ;;
        --locale) (($# >= 2)) || { log_err "--locale needs a value"; exit 1; }; shift; LOCALE="$1" ;;
        --keymap) (($# >= 2)) || { log_err "--keymap needs a value"; exit 1; }; shift; KEYMAP="$1" ;;
        --timezone) (($# >= 2)) || { log_err "--timezone needs a value"; exit 1; }; shift; TIMEZONE="$1" ;;
        --user) (($# >= 2)) || { log_err "--user needs a value"; exit 1; }; shift; USER_NAME="$1" ;;
        --shell) (($# >= 2)) || { log_err "--shell needs a value"; exit 1; }; shift; SHELL_CHOICE="$1" ;;
        --sudo) (($# >= 2)) || { log_err "--sudo needs a value"; exit 1; }; shift; SUDO_POLICY="$1" ;;
        --no-install) INSTALL_TOOLS=0 ;;
        *)
            log_err "unknown option: $arg"
            usage
            exit 1
            ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# Resolve values (option > environment > interactive/default).
# ---------------------------------------------------------------------------

if [[ -z "$LOCALE" ]]; then
    LOCALE="$(ask_default "Locale (LANG)" "en_US.UTF-8")"
fi
if [[ -z "$KEYMAP" ]]; then
    KEYMAP="$(ask_default "Keyboard keymap" "us")"
fi
if [[ -z "$TIMEZONE" ]]; then
    TIMEZONE="$(ask_default "Timezone (windows-time | UTC | IANA zone)" "windows-time")"
fi
if [[ -z "$USER_NAME" ]]; then
    def="${SUDO_USER:-x}"
    USER_NAME="$(ask_default "User to create or ensure with sudo" "$def")"
fi
if [[ -z "$SHELL_CHOICE" ]]; then
    SHELL_CHOICE="$(ask_choice "User login shell" 1 "zsh" "bash")"
fi
if [[ -z "$SUDO_POLICY" ]]; then
    SUDO_POLICY="$(ask_choice "Sudo policy" 1 "nopasswd (recommended for WSL)" "password")"
    case "$SUDO_POLICY" in
        nopasswd*) SUDO_POLICY=nopasswd ;;
        password*) SUDO_POLICY=password ;;
    esac
fi
case "$SUDO_POLICY" in
    nopasswd | password) ;;
    *)
        log_err "invalid --sudo policy: $SUDO_POLICY (expected nopasswd or password)"
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Validate the resolved values.
# ---------------------------------------------------------------------------

if [[ ! "$USER_NAME" =~ ^[a-z_][a-z0-9_-]*$ ]] || ((${#USER_NAME} > 32)); then
    log_err "invalid user name: $USER_NAME"
    exit 1
fi
if [[ "$USER_NAME" == "root" ]]; then
    log_err "--user root is not allowed; choose a regular user"
    exit 1
fi
if [[ ! "$LOCALE" =~ ^[A-Za-z0-9_@.+-]+$ ]]; then
    log_err "invalid locale: $LOCALE"
    exit 1
fi
if [[ ! "$KEYMAP" =~ ^[A-Za-z0-9-]+$ ]]; then
    log_err "invalid keymap: $KEYMAP"
    exit 1
fi
if [[ "$TIMEZONE" != "windows-time" ]]; then
    if [[ -d /usr/share/zoneinfo ]]; then
        if [[ ! -e "/usr/share/zoneinfo/$TIMEZONE" ]]; then
            log_err "unknown timezone: $TIMEZONE"
            exit 1
        fi
    fi
fi
case "$SHELL_CHOICE" in
    zsh | bash | /*) ;;
    *)
        log_err "invalid --shell: $SHELL_CHOICE (expected zsh, bash or a path)"
        exit 1
        ;;
esac

if [[ "$SHELL_CHOICE" == /* ]]; then
    SHELL_PATH="$SHELL_CHOICE"
else
    SHELL_PATH="$(command -v "$SHELL_CHOICE" 2>/dev/null || printf '/bin/%s' "$SHELL_CHOICE")"
fi

log_info "target system user: $USER_NAME (shell $SHELL_PATH)"
log_info "locale $LOCALE | keymap $KEYMAP | timezone $TIMEZONE | sudo $SUDO_POLICY"
if x_is_wsl; then
    log_info "WSL detected"
fi

# ---------------------------------------------------------------------------
# Base tools (Arch: git, sudo and the login shell; zsh when requested).
# ---------------------------------------------------------------------------

tools=(sudo git curl wget)
case "$SHELL_PATH" in
    */zsh) tools+=(zsh) ;;
esac
if [[ "$INSTALL_TOOLS" == 1 ]] && x_have pacman; then
    if x_is_dry; then
        log_info "plan: install base tools with pacman: ${tools[*]}"
    else
        log_info "refreshing package databases"
        if pacman -Sy --noconfirm >/dev/null 2>&1; then
            log_info "installing base tools: ${tools[*]}"
            pacman -S --noconfirm --needed "${tools[@]}" ||
                log_warn "package install reported errors (offline?); continuing"
        else
            log_warn "pacman refresh failed (offline?); continuing without new tools"
        fi
    fi
elif x_is_dry; then
    log_info "plan: skip base tools install"
else
    log_info "not Arch or install disabled; base tools left untouched"
fi

# ---------------------------------------------------------------------------
# Locale.
# ---------------------------------------------------------------------------

x_step "enable locale $LOCALE in /etc/locale.gen and set /etc/locale.conf"
if ! x_is_dry; then
    if [[ -f /etc/locale.gen ]]; then
        sed -i -E "s|^#?[[:space:]]*${LOCALE}([[:space:]]+[A-Z0-9.-]+)?$|${LOCALE} UTF-8|" /etc/locale.gen
        grep -qE "^${LOCALE}[[:space:]]" /etc/locale.gen ||
            printf '%s UTF-8\n' "$LOCALE" >>/etc/locale.gen
    fi
    printf 'LANG=%s\n' "$LOCALE" >/etc/locale.conf
    if x_have locale-gen; then
        locale-gen >/dev/null 2>&1 ||
            log_warn "locale-gen reported errors; LANG will still be exported"
    else
        log_warn "locale-gen not found; locale not generated"
    fi
fi

# ---------------------------------------------------------------------------
# Keyboard.
# ---------------------------------------------------------------------------

x_step "write /etc/vconsole.conf with KEYMAP=$KEYMAP"
if ! x_is_dry; then
    printf 'KEYMAP=%s\n' "$KEYMAP" >/etc/vconsole.conf
fi

# ---------------------------------------------------------------------------
# Timezone.
# ---------------------------------------------------------------------------

if [[ "$TIMEZONE" == "windows-time" ]]; then
    log_info "timezone left to WSL (it mirrors the Windows clock)"
else
    x_step "set timezone to $TIMEZONE"
    if ! x_is_dry; then
        ln -sfn "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
        if x_have timedatectl && [[ -d /run/systemd/system ]]; then
            timedatectl set-timezone "$TIMEZONE" ||
                log_warn "timedatectl failed; /etc/localtime was linked anyway"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Profile note (system summary; user env is owned by stage-user.sh).
# ---------------------------------------------------------------------------

x_step "write system note /etc/profile.d/x-wsl.sh"
if ! x_is_dry; then
    cat >/etc/profile.d/x-wsl.sh <<'PROFILE_NOTE'
# Managed by equislinux/wsl-scripts (stage-root).
# System locale/keymap/timezone/user live in:
#   /etc/locale.conf  /etc/vconsole.conf  /etc/localtime
#   /etc/sudoers.d/x-wsl-wheel
# The default WSL login user is the [user] default key of /etc/wsl.conf.
# Per-user environment is applied by stage-user.sh (equislinux/wsl-scripts).
PROFILE_NOTE
fi

# ---------------------------------------------------------------------------
# User, wheel group and sudo policy.
# ---------------------------------------------------------------------------

if ! x_is_dry && x_have pacman && ! id "$USER_NAME" >/dev/null 2>&1 &&
    [[ "$INSTALL_TOOLS" == 1 ]]; then
    x_have sudo || log_warn "sudo is missing and could not be installed"
fi

x_step "ensure user $USER_NAME with login shell $SHELL_PATH"
if ! x_is_dry; then
    if [[ ! -x "$SHELL_PATH" ]]; then
        log_warn "shell $SHELL_PATH not available; falling back to /bin/bash"
        SHELL_PATH=/bin/bash
    fi
    if id "$USER_NAME" >/dev/null 2>&1; then
        log_ok "user $USER_NAME already exists"
    else
        useradd -m -G wheel -s "$SHELL_PATH" "$USER_NAME"
        log_ok "user $USER_NAME created"
    fi
    usermod -aG wheel "$USER_NAME"
    usermod -s "$SHELL_PATH" "$USER_NAME"
fi

if [[ "$SUDO_POLICY" == "nopasswd" ]]; then
    x_step "grant passwordless sudo to wheel (recommended on WSL)"
else
    x_step "grant password sudo to wheel"
fi
if ! x_is_dry; then
    mkdir -p /etc/sudoers.d
    if [[ "$SUDO_POLICY" == "nopasswd" ]]; then
        printf '%%wheel ALL=(ALL:ALL) NOPASSWD: ALL\n' >/etc/sudoers.d/x-wsl-wheel
    else
        printf '%%wheel ALL=(ALL:ALL) ALL\n' >/etc/sudoers.d/x-wsl-wheel
    fi
    chmod 0440 /etc/sudoers.d/x-wsl-wheel
fi

if [[ "$SUDO_POLICY" == "password" ]]; then
    if x_is_dry; then
        log_info "plan: set a password for $USER_NAME"
    else
        if ! x_is_tty; then
            log_err "password policy chosen but no interactive terminal is available"
            exit 1
        fi
        printf 'Password for %s: ' "$USER_NAME" >&2
        IFS= read -rs pass1 || { log_err "password read aborted"; exit 1; }
        printf '\n' >&2
        printf 'Repeat password for %s: ' "$USER_NAME" >&2
        IFS= read -rs pass2 || { log_err "password read aborted"; exit 1; }
        printf '\n' >&2
        if [[ -z "$pass1" || "$pass1" != "$pass2" ]]; then
            log_err "passwords do not match or are empty"
            exit 1
        fi
        printf '%s:%s\n' "$USER_NAME" "$pass1" | chpasswd
        unset pass1 pass2
    fi
fi

# ---------------------------------------------------------------------------
# Default user for new WSL sessions ([user] default in /etc/wsl.conf).
#
# Imported distributions have no Windows launcher, so their default user can
# only be changed through /etc/wsl.conf (see "Change the default user for a
# distribution" and the [user] section of the official WSL docs). The initial
# file shipped by equislinux/wsl keeps default=root so the first import always
# boots; once a real user exists we point that key at it. Editing only ever
# touches the [user] default value, never the rest of the file.
# ---------------------------------------------------------------------------

DISTRO="${WSL_DISTRO_NAME:-<distro>}"

SET_DEFAULT_USER=""
if x_is_dry; then
    SET_DEFAULT_USER=1
elif [[ -n "${X_SET_DEFAULT_USER:-}" ]]; then
    SET_DEFAULT_USER="$X_SET_DEFAULT_USER"
fi
case "$SET_DEFAULT_USER" in
    0 | 1) ;;
    '')
        if [[ -f /etc/wsl.conf ]] || x_is_wsl; then
            if ask_yesno "Make ${USER_NAME} the default user of new WSL sessions (recommended)?" yes; then
                SET_DEFAULT_USER=1
            else
                SET_DEFAULT_USER=0
            fi
        else
            SET_DEFAULT_USER=0
        fi
        ;;
    *)
        log_err "invalid X_SET_DEFAULT_USER: $SET_DEFAULT_USER (expected 1 or 0)"
        exit 1
        ;;
esac

if [[ "$SET_DEFAULT_USER" == 1 ]]; then
    if [[ -f /etc/wsl.conf ]]; then
        CURRENT_DEFAULT="$(x_wsl_conf_default /etc/wsl.conf)"
        if [[ "$CURRENT_DEFAULT" == "$USER_NAME" ]]; then
            log_ok "/etc/wsl.conf already logs new sessions in as $USER_NAME"
        else
            x_step "pin [user] default=$USER_NAME in /etc/wsl.conf"
            if ! x_is_dry; then
                if x_wsl_conf_set_default /etc/wsl.conf "$USER_NAME"; then
                    log_ok "/etc/wsl.conf now logs new sessions in as $USER_NAME"
                else
                    log_warn "could not write /etc/wsl.conf; keeping its current default"
                fi
            fi
        fi
    elif ! x_is_dry; then
        log_warn "/etc/wsl.conf not found; new sessions will keep booting as root"
    fi
fi

# What the final summary should tell the user about the default login user.
DEFAULT_USER_STATE=not_pinned
if [[ -f /etc/wsl.conf ]] && [[ "$(x_wsl_conf_default /etc/wsl.conf)" == "$USER_NAME" ]]; then
    DEFAULT_USER_STATE=pinned
elif x_is_dry && [[ "$SET_DEFAULT_USER" == 1 ]] && [[ -f /etc/wsl.conf ]]; then
    DEFAULT_USER_STATE=will_pin
fi

# ---------------------------------------------------------------------------
# Summary and next steps.
# ---------------------------------------------------------------------------

log_ok "system stage complete"
if x_is_dry; then
    log_info "dry-run: nothing was applied"
fi

if [[ "$DEFAULT_USER_STATE" == not_pinned ]] && ! x_is_dry && [[ -f /etc/wsl.conf ]]; then
    log_warn "/etc/wsl.conf does not pin the default user to $USER_NAME"
    log_warn "new sessions will still open as root until you set:"
    log_warn "  [user] default=$USER_NAME   (in /etc/wsl.conf)"
fi

echo
echo "The user '$USER_NAME' is ready with the requested locale, keymap,"
echo "timezone and sudo access. The user environment is configured next."
echo

if x_is_wsl; then
    if [[ "$DEFAULT_USER_STATE" == pinned || "$DEFAULT_USER_STATE" == will_pin ]]; then
        echo "Exit this session and relaunch the distribution from Windows; WSL"
        echo "applies /etc/wsl.conf on start and the new session opens as '$USER_NAME':"
        echo "    wsl --terminate ${DISTRO}"
        echo "    wsl -d ${DISTRO}"
    else
        echo "Exit this session and relaunch as '$USER_NAME' from Windows:"
        echo "    wsl --terminate ${DISTRO}"
        echo "    wsl -d ${DISTRO} -u ${USER_NAME}"
    fi
else
    echo "Log in as '$USER_NAME' (for example: su - $USER_NAME)."
fi
echo
echo "Then run the user stage from a checkout of this repository that the"
echo "user can read (if you cloned it under /root, move it first, e.g. to"
echo "a shared path such as /opt/x-wsl-scripts):"
echo "    ${SRC_DIR}/install.sh"
echo
echo "That second run configures the shell prompt, environment variables"
echo "and the development folders (see stage-user.sh and the docs)."
echo
