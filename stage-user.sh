#!/usr/bin/env bash
set -euo pipefail

# User stage of the X Linux on WSL setup.
# Runs as the target user. Exports the user environment from the login rc
# files (~/.profile and ~/.bashrc, or the zsh equivalents), adds PATH hygiene
# that keeps WSL interop working, and creates the usual development folders.

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SRC_DIR/lib/common.sh"

usage() {
    cat <<'EOF'
Usage: stage-user.sh

Configures the current user for X Linux on WSL:
  - appends the environment block (EDITOR, XDG dirs, PATH, prompt, aliases)
    to ~/.profile and ~/.bashrc (~/.zprofile and ~/.zshrc with zsh)
  - creates ~/.local/bin, ~/Projects and ~/.config/x

Must run as the target user. Invoked with sudo it drops back to SUDO_USER.

Environment:
  X_EDITOR=editor   Preferred editor (default: vim, else nano, else vi).
  X_SHELL=path      Login shell used to pick rc files (default: from passwd).
  X_DRY=1           Print the plan without applying changes.
  X_AUTO=1          Use defaults without prompting.
EOF
}

for a in "$@"; do
    case "$a" in
        -h | --help)
            usage
            exit 0
            ;;
        *)
            log_err "unknown option: $a"
            usage
            exit 1
            ;;
    esac
done

x_require_user "$@"

TARGET_USER="$(id -un)"
TARGET_HOME="${HOME:-$(getent passwd "$TARGET_USER" | cut -d: -f6)}"

if [[ -n "${X_SHELL:-}" ]]; then
    SHELL_PATH="$X_SHELL"
else
    SHELL_PATH="$(getent passwd "$TARGET_USER" | cut -d: -f7)"
fi
[[ -n "$SHELL_PATH" ]] || SHELL_PATH="${SHELL:-/bin/bash}"
SHELL_NAME="${SHELL_PATH##*/}"

case "$SHELL_NAME" in
    zsh) RCS=("$TARGET_HOME/.zprofile" "$TARGET_HOME/.zshrc") ;;
    bash | sh) RCS=("$TARGET_HOME/.profile" "$TARGET_HOME/.bashrc") ;;
    *) RCS=("$TARGET_HOME/.profile") ;;
esac
DIRS=("$TARGET_HOME/.local/bin" "$TARGET_HOME/Projects" "$TARGET_HOME/.config/x")

MARK_START='# >>> equislinux/wsl-scripts: user environment'
MARK_END='# <<< equislinux/wsl-scripts: user environment (end)'

log_info "user: $TARGET_USER"
log_info "home: $TARGET_HOME"
log_info "login shell: $SHELL_NAME ($SHELL_PATH)"
log_info "rc files: ${RCS[*]}"

# ---------------------------------------------------------------------------
# Environment block content.
# ---------------------------------------------------------------------------

emit_env_block() {
    cat <<'EOF'
# Preferred editor. Override with X_EDITOR before running stage-user.sh.
if [ -z "${EDITOR:-}" ]; then
    if command -v "${X_EDITOR:-none}" >/dev/null 2>&1; then
        EDITOR="$X_EDITOR"
    elif command -v vim >/dev/null 2>&1; then
        EDITOR=vim
    elif command -v nano >/dev/null 2>&1; then
        EDITOR=nano
    else
        EDITOR=vi
    fi
fi
export EDITOR
export VISUAL="${VISUAL:-$EDITOR}"

# XDG base directories stay inside the Linux home.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# PATH hygiene: local bins are prepended without touching the system dirs or
# the WSL interop entries (for example existing /mnt/c paths keep working).
case ":${PATH:-}:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
esac
case ":${PATH:-}:" in
    *":$HOME/bin:"*) ;;
    *) PATH="$HOME/bin:$PATH" ;;
esac
export PATH

# Friendly prompt.
if [ -n "${ZSH_VERSION:-}" ]; then
    PROMPT='%n@%m:%3~ %# '
elif [ -n "${BASH_VERSION:-}" ]; then
    PS1='\u@\h:\w\$ '
fi

# Aliases.
alias la='ls -A'
alias ll='ls -lh'
alias l='ls -CF'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
EOF
}

# Remove a previous x-wsl region from a file, keeping anything after it.
strip_region() {
    local file="$1"
    awk -v s="$MARK_START" -v e="$MARK_END" '
        { if ($0 == s) { inblock = 1 }
          if (inblock) { if ($0 == e) { inblock = 0 }; next }
          print
        }
    ' "$file" >"$file.new"
    mv -- "$file.new" "$file"
}

apply_env_block() {
    local file="$1" block
    block="$(emit_env_block)"
    if [[ -f "$file" ]] && grep -qF -- "$MARK_START" "$file"; then
        strip_region "$file"
    fi
    printf '\n%s\n%s\n%s\n' "$MARK_START" "$block" "$MARK_END" >>"$file"
}

for rc in "${RCS[@]}"; do
    x_step "write the environment block to $rc"
    if ! x_is_dry; then
        if [[ ! -f "$rc" ]]; then
            : >"$rc"
        fi
        apply_env_block "$rc"
    fi
done

# ---------------------------------------------------------------------------
# Folders.
# ---------------------------------------------------------------------------

for d in "${DIRS[@]}"; do
    x_step "create $d"
    if ! x_is_dry; then
        mkdir -p "$d"
    fi
done

# ---------------------------------------------------------------------------
# Done.
# ---------------------------------------------------------------------------

if x_is_dry; then
    log_info "dry-run: nothing was applied"
else
    log_ok "user stage complete"
fi
echo
echo "Next steps:"
echo "  1. Start a new session so the shell reads the updated rc files"
echo "     (exit and reopen, or from Windows run: wsl --terminate <distro>"
echo "     followed by wsl -d <distro>)."
echo "  2. Check the environment:  echo \$EDITOR \$XDG_CONFIG_HOME"
echo "  3. Your project folder is ready at: $TARGET_HOME/Projects"
if x_is_wsl && [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    echo
    echo "If the new session still opens as root, the [user] default of"
    echo "/etc/wsl.conf is not pointing at $TARGET_USER. Set it there or"
    echo "launch from Windows with:  wsl -d ${WSL_DISTRO_NAME} -u $TARGET_USER"
fi
echo
