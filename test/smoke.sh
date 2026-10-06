#!/usr/bin/env bash
set -euo pipefail

# Local smoke tests for equislinux/wsl-scripts.
# Requires no root and no network. Runs syntax checks and exercises the
# stages in dry-run mode with a temporary HOME.

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAIL=0

check() {
    local desc="$1"
    shift
    if "$@"; then
        printf 'ok - %s\n' "$desc"
    else
        printf 'FAIL - %s\n' "$desc"
        FAIL=1
    fi
}

# ---------------------------------------------------------------------------
# Syntax of every shell script in the repository.
# ---------------------------------------------------------------------------
echo "== syntax =="
while IFS= read -r f; do
    check "syntax $f" bash -n "$f"
done < <(find "$SRC" -name '*.sh' -not -path '*/.git/*' | sort)
check "syntax setup.sh" bash -n "$SRC/setup.sh"

# ---------------------------------------------------------------------------
# ui: gum detection (stubbed gum on PATH, then absent).
# ---------------------------------------------------------------------------
echo "== ui gum detection =="
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nexit 0\n' >"$TMP/bin/gum"
chmod +x "$TMP/bin/gum"

PATH="$TMP/bin:$PATH" bash -c 'source "$1/lib/ui.sh"; ui_has_gum' _ "$SRC" \
    </dev/null
check "ui_has_gum true with gum on PATH" \
    env PATH="$TMP/bin:$PATH" bash -c 'source "$1/lib/ui.sh"; ui_has_gum' _ "$SRC" \
    </dev/null
check "ui_has_gum false without gum" \
    bash -c 'source "$1/lib/ui.sh"; ! ui_has_gum' _ "$SRC" \
    </dev/null

# ---------------------------------------------------------------------------
# lib/common.sh: /etc/wsl.conf default-user helpers (temp file only).
# ---------------------------------------------------------------------------
echo "== wsl.conf default-user helpers =="
WCONF="$TMP/wsl.conf"
cat >"$WCONF" <<'EOF'
# managed test file
[boot]
systemd=true

# shipped as root
[user]
default=root

[interop]
enabled=true
appendWindowsPath=true
EOF
check "x_wsl_conf_default reads the current default" \
    bash -c 'source "$1/lib/common.sh"; test "$(x_wsl_conf_default "$2")" = root' \
    _ "$SRC" "$WCONF"
bash -c 'source "$1/lib/common.sh"; x_wsl_conf_set_default "$2" smokeuser' _ "$SRC" "$WCONF"
check "x_wsl_conf_set_default replaces the value" \
    bash -c 'source "$1/lib/common.sh"; test "$(x_wsl_conf_default "$2")" = smokeuser' \
    _ "$SRC" "$WCONF"
check "set keeps the other sections intact" \
    bash -c 'source "$1/lib/common.sh"; grep -q "^systemd=true" "$2" && grep -q "enabled=true" "$2"' \
    _ "$SRC" "$WCONF"
bash -c 'source "$1/lib/common.sh"; x_wsl_conf_set_default "$2" smokeuser' _ "$SRC" "$WCONF"
check "set is idempotent (single [user], single default)" \
    bash -c 'source "$1/lib/common.sh"; test "$(grep -c "^\[user\]" "$2")" -eq 1 && test "$(grep -c "^default=" "$2")" -eq 1' \
    _ "$SRC" "$WCONF"
check "missing file leaves the default empty and never creates it" \
    bash -c 'source "$1/lib/common.sh"; test -z "$(x_wsl_conf_default "$2")" && test ! -e "$2"' \
    _ "$SRC" "$TMP/does-not-exist"

# ---------------------------------------------------------------------------
# stage-root.sh: dry run (non-root), explicit system options.
# ---------------------------------------------------------------------------
echo "== stage-root dry run =="
ROOT_HOME="$TMP/root-home"
mkdir -p "$ROOT_HOME"
set +e
HOME="$ROOT_HOME" X_DRY=1 X_AUTO=1 \
    bash "$SRC/stage-root.sh" \
    --locale es_ES.UTF-8 --keymap es --timezone UTC \
    --user smokeuser --shell bash --sudo nopasswd \
    >"$TMP/root.out" 2>&1
ROOT_RC=$?
set -e
check "stage-root dry run exits 0" test "$ROOT_RC" -eq 0
check "dry run resolves --user" grep -q "system user: smokeuser" "$TMP/root.out"
check "dry run resolves --locale and --keymap" \
    grep -q "locale es_ES.UTF-8 | keymap es | timezone UTC | sudo nopasswd" "$TMP/root.out"
check "dry run reports no changes applied" grep -q "nothing was applied" "$TMP/root.out"

# ---------------------------------------------------------------------------
# stage-user.sh: dry run in a temporary HOME must not create anything.
# ---------------------------------------------------------------------------
echo "== stage-user dry run =="
USER_HOME="$TMP/user-home-dry"
mkdir -p "$USER_HOME"
set +e
HOME="$USER_HOME" X_DRY=1 X_AUTO=1 X_SHELL=/bin/bash \
    bash "$SRC/stage-user.sh" >"$TMP/user.out" 2>&1
USER_RC=$?
set -e
check "stage-user dry run exits 0" test "$USER_RC" -eq 0
check "dry run plans the environment block" \
    grep -q "write the environment block" "$TMP/user.out"
check "dry run creates no rc files" test ! -e "$USER_HOME/.profile"
check "dry run creates no folders" test ! -d "$USER_HOME/Projects"
check "dry run reports no changes applied" grep -q "nothing was applied" "$TMP/user.out"

# ---------------------------------------------------------------------------
# stage-user.sh: real apply in a temporary HOME.
# ---------------------------------------------------------------------------
echo "== stage-user apply =="
APPLY_HOME="$TMP/user-home-apply"
mkdir -p "$APPLY_HOME"
printf 'my line\nexport CUSTOM=1\n' >"$APPLY_HOME/.bashrc"

HOME="$APPLY_HOME" X_AUTO=1 X_SHELL=/bin/bash X_EDITOR=vim \
    bash "$SRC/stage-user.sh" >"$TMP/apply.out" 2>&1
check "apply exits 0" grep -q "user stage complete" "$TMP/apply.out"
check "apply writes the env exports to .profile" \
    grep -q "export EDITOR" "$APPLY_HOME/.profile"
check "apply writes the env exports to .bashrc" \
    grep -q "export XDG_CONFIG_HOME" "$APPLY_HOME/.bashrc"
check "apply keeps existing .bashrc content" \
    grep -q "my line" "$APPLY_HOME/.bashrc"
check "apply creates Projects" test -d "$APPLY_HOME/Projects"
check "apply creates .local/bin" test -d "$APPLY_HOME/.local/bin"
check "apply creates .config/x" test -d "$APPLY_HOME/.config/x"

START_MARKER='^# >>> equislinux/wsl-scripts: user environment$'
PROFILE_BLOCKS="$(grep -c "$START_MARKER" "$APPLY_HOME/.profile")"
check "apply keeps a single environment block (.profile)" \
    test "$PROFILE_BLOCKS" -eq 1

# Idempotent second run: one block, custom content preserved.
HOME="$APPLY_HOME" X_AUTO=1 X_SHELL=/bin/bash X_EDITOR=nano \
    bash "$SRC/stage-user.sh" >/dev/null 2>&1
check "second run stays idempotent (one block)" \
    test "$(grep -c "$START_MARKER" "$APPLY_HOME/.profile")" -eq 1
check "second run keeps user content outside the block" \
    grep -q "my line" "$APPLY_HOME/.bashrc"
check "second run updates the block (editor)" \
    grep -q "export EDITOR" "$APPLY_HOME/.profile"

# ---------------------------------------------------------------------------
# setup.sh: dispatch.
# ---------------------------------------------------------------------------
echo "== setup dispatch =="
set +e
HOME="$APPLY_HOME" X_DRY=1 X_AUTO=1 \
    bash "$SRC/setup.sh" >"$TMP/setup-user.out" 2>&1
SETUP_RC=$?
set -e
check "setup.sh as regular user exits 0" test "$SETUP_RC" -eq 0
check "setup.sh dispatches to the user stage" \
    grep -q "environment block" "$TMP/setup-user.out"

set +e
HOME="$APPLY_HOME" X_DRY=1 X_AUTO=1 \
    bash "$SRC/setup.sh" --locale fr_FR.UTF-8 >"$TMP/setup-root.out" 2>&1
SETUP_SYS_RC=$?
set -e
if [[ "$SETUP_SYS_RC" -eq 0 ]]; then
    check "setup.sh system options as regular user refuse" false
else
    check "setup.sh system options as regular user refuse" true
fi
check "setup.sh explains the root requirement" \
    grep -q "system options require root" "$TMP/setup-root.out"

# ---------------------------------------------------------------------------
# install.sh: friendly wrapper dispatch and help.
# ---------------------------------------------------------------------------
echo "== install wrapper =="
set +e
bash "$SRC/install.sh" --help >"$TMP/install-help.out" 2>&1
INSTALL_HELP_RC=$?
set -e
check "install.sh --help exits 0" test "$INSTALL_HELP_RC" -eq 0
check "install.sh help explains the two parts" \
    grep -q "Part 1" "$TMP/install-help.out"

set +e
HOME="$APPLY_HOME" X_DRY=1 X_AUTO=1 \
    bash "$SRC/install.sh" >"$TMP/install-user.out" 2>&1
INSTALL_RC=$?
set -e
check "install.sh as regular user exits 0" test "$INSTALL_RC" -eq 0
check "install.sh dispatches to the user stage" \
    grep -q "environment block" "$TMP/install-user.out"

set +e
HOME="$APPLY_HOME" X_DRY=1 X_AUTO=1 \
    bash "$SRC/install.sh" --locale fr_FR.UTF-8 >"$TMP/install-root.out" 2>&1
INSTALL_SYS_RC=$?
set -e
if [[ "$INSTALL_SYS_RC" -eq 0 ]]; then
    check "install.sh system options as regular user refuse" false
else
    check "install.sh system options as regular user refuse" true
fi
check "install.sh explains the root requirement" \
    grep -q "system options require root" "$TMP/install-root.out"

# ---------------------------------------------------------------------------
echo
if [[ "$FAIL" -eq 0 ]]; then
    echo "smoke: OK"
else
    echo "smoke: failures detected"
    exit 1
fi
