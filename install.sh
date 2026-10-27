#!/usr/bin/env bash
set -euo pipefail

# X Linux on WSL - guided installer (single friendly entry point).
#
# Runs the two-part setup for a freshly imported X Linux distribution. It
# detects the context and forwards to the matching stage; setup.sh remains the
# lower-level dispatcher and accepts the same options.
#
#   Part 1 (system): root on a fresh import  -> stage-root.sh
#         locale, keymap, timezone, base tools and the sudo user
#   Part 2 (user):   the created user        -> stage-user.sh
#         shell prompt, environment variables and folders
#
# Typical flow:
#   1. wsl -d <distro>                         (opens as root)
#   2. ./install.sh                            (Part 1, system)
#   3. exit, then wsl -d <distro> again        (now opens as your user)
#   4. ./install.sh                            (Part 2, user)

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SRC_DIR/lib/common.sh"

usage() {
    cat <<'EOF'
Usage: install.sh [system options...]

Guided setup for X Linux on WSL.

Run it twice on the freshly imported distribution:
  as root            -> Part 1 (system): locale, keymap, timezone, base
                        tools and the sudo user.
  as your new user   -> Part 2 (user): shell, environment and folders.

System options are forwarded to the system stage:
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

# Detect which part this invocation will run (setup.sh does the real
# dispatch; this only makes the friendly messages accurate).
SYSTEM_FLAG=0
for a in "$@"; do
    case "$a" in
        --locale* | --keymap* | --timezone* | --user* | --shell* | --sudo* | --no-install)
            SYSTEM_FLAG=1
            ;;
    esac
done

cat <<BANNER
X Linux on WSL - guided setup

This installer runs in two parts:
  Part 1 (system):  as root, right after importing the distribution.
                    Configures locale, keymap, timezone, base tools and
                    creates your user with sudo.
  Part 2 (user):    as that user, after relaunching the distribution.
                    Configures your shell prompt, environment and folders.

BANNER

if [[ $EUID -eq 0 && -z "${SUDO_USER:-}" ]]; then
    log_info "running as root; this is Part 1 (system)."
    log_info "after it finishes, exit, relaunch and run this same script again as your user."
elif [[ $EUID -eq 0 && "$SYSTEM_FLAG" == 1 ]]; then
    log_info "system options given; this is Part 1 (system)."
elif [[ $EUID -eq 0 ]]; then
    log_info "running through sudo; this is Part 2 (user) for $SUDO_USER."
else
    log_info "running as $(id -un); this is Part 2 (user)."
fi
echo

exec bash "$SRC_DIR/setup.sh" "$@"
