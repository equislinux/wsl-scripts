#!/usr/bin/env bash
set -euo pipefail

# X Linux on WSL - setup wizard.
# Two-stage flow:
#   stage-root.sh   system stage (locale, keymap, timezone, user, sudo)
#   stage-user.sh   user stage (environment, folders)
#
# Dispatch rules:
#   - root without SUDO_USER (fresh WSL import)      -> system stage
#   - root via sudo (SUDO_USER set)                  -> user stage
#   - regular user                                   -> user stage
# Passing system options (--locale, --keymap, --timezone, --user, --shell,
# --sudo, --no-install) always selects the system stage.

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SRC_DIR/lib/common.sh"

usage() {
    cat <<'EOF'
Usage: setup.sh [system options...]

Direct dispatcher of the X Linux on WSL setup. New users normally run the
guided wrapper instead (./install.sh); setup.sh exposes the same flow with
less prose and forwards system options to stage-root.sh.

Context detection:
  root, no SUDO_USER (default WSL login)   -> system stage
  sudo ./setup.sh (existing sudo user)      -> user stage for that user
  ./setup.sh (regular user)                 -> user stage

System options are forwarded to stage-root.sh:
  --locale LOCALE   Locale (default en_US.UTF-8).
  --keymap KEYMAP   Keyboard keymap (default us).
  --timezone ZONE   windows-time, UTC or an IANA zone.
  --user NAME       User to create or ensure with sudo.
  --shell SHELL     Login shell: zsh or bash.
  --sudo POLICY     Sudo policy: nopasswd or password.
  --no-install      Skip installing base tools and the X identity layer (x-release).

Environment:
  X_AUTO=1          Use defaults without prompting.
  X_DRY=1           Print the plan without applying changes.
  -h, --help        Show this help.
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

SYSTEM_FLAG=0
for a in "$@"; do
    case "$a" in
        --locale* | --keymap* | --timezone* | --user* | --shell* | --sudo* | --no-install)
            SYSTEM_FLAG=1
            ;;
    esac
done

if [[ $EUID -eq 0 ]]; then
    if [[ -z "${SUDO_USER:-}" ]] || [[ "$SYSTEM_FLAG" == 1 ]]; then
        if [[ "$SYSTEM_FLAG" == 1 && -z "${SUDO_USER:-}" ]]; then
            log_warn "running the system stage with explicit options"
        fi
        exec bash "$SRC_DIR/stage-root.sh" "$@"
    fi
    log_info "root via sudo; running the user stage for $SUDO_USER"
    if [[ "$SYSTEM_FLAG" == 1 ]]; then
        log_warn "system options are ignored in user stage; use ./stage-root.sh for them"
    fi
    exec bash "$SRC_DIR/stage-user.sh"
fi

if [[ "$SYSTEM_FLAG" == 1 ]]; then
    log_err "system options require root; run as root (fresh import) or: sudo ./stage-root.sh $*"
    exit 1
fi

exec bash "$SRC_DIR/stage-user.sh"
