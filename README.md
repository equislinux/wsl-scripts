# X Linux for WSL - setup scripts

Friendly, mostly automatic setup for **X Linux on WSL** (terminal only, no
GUI). This repository turns the freshly imported rootfs from
[equislinux/wsl](https://github.com/equislinux/wsl) into a usable X Linux system: a
regular user with sudo, sane locale/keymap/timezone values and a comfortable
terminal environment.

The scripts ask plain-text questions (gum is used automatically when it is
installed) and degrade to unattended mode with `X_AUTO=1`.

## Flow

The importable rootfs and the first-run setup live in two repositories that
are used in order:

```
equislinux/wsl                     equislinux/wsl-scripts
--------------                --------------------
build-rootfs.sh       ->      import on Windows (install.ps1)
(minimal Arch rootfs)         then, inside the distro:
                              1. ./install.sh as root  (system stage)
                              2. exit, relaunch
                              3. ./install.sh as user  (user stage)
```

See `docs/en/architecture.md` (or `docs/es/architecture.md`) for the full
picture and for how `wsl.conf` / `.wslconfig` / `systemd` map to the official
WSL documentation.

## Quick start

Inside the imported distribution, the first session opens as root (that is
the WSL default for imported distributions). From a checkout of this
repository that the future user can read (for example
`/opt/x-wsl-scripts`, **not** `/root`):

```bash
git clone https://github.com/equislinux/wsl-scripts /opt/x-wsl-scripts
cd /opt/x-wsl-scripts
./install.sh
```

This first run is the **system stage**: locale, keymap, timezone, base tools
and the sudo user. When it finishes, exit the session and relaunch the
distribution (or run `wsl --terminate <distro>` followed by `wsl -d
<distro>`). The new session opens as your user, because the installer pinned
`[user] default` in `/etc/wsl.conf`. Then run the installer again:

```bash
cd /opt/x-wsl-scripts
./install.sh
```

This second run is the **user stage**: environment variables, shell prompt,
aliases and development folders.

`install.sh` is a friendly wrapper around `setup.sh`; `setup.sh` remains the
direct dispatcher and accepts the same options. See
[docs/en/usage.md](docs/en/usage.md) for every option.

## Repository layout

```
install.sh          friendly entry point (run as root, then as your user)
setup.sh            direct stage dispatcher
stage-root.sh       system stage (root): locale, keymap, timezone, user, sudo
stage-user.sh       user stage: shell, environment, folders
lib/common.sh       shared helpers (X_DRY, X_AUTO, logs, wsl.conf helpers)
lib/ui.sh           prompts: gum with a plain fallback
test/smoke.sh       local tests (no root required)
docs/en|es/         guides: architecture, usage, configuration
legacy/             previous WSL bootstrap kept for review (not part of the
                    active flow; untouched)
```

The system-level WSL wiring (systemd, networking, the initial `/etc/wsl.conf`)
belongs to the `equislinux/wsl` rootfs and is not recreated here. This repository
only ever adjusts the `[user] default` key of `/etc/wsl.conf` once it has
created a real user, which is the documented way to change the default user of
an imported distribution.

## Automation

The scripts are safe to run unattended:

- `X_AUTO=1` uses the defaults without prompting.
- `X_DRY=1` prints the plan without changing anything.
- System options can be set through `X_LOCALE`, `X_KEYMAP`, `X_TIMEZONE`,
  `X_USER`, `X_SHELL`, `X_SUDO`, `X_INSTALL` and `X_SET_DEFAULT_USER`.

## Tests

```bash
./test/smoke.sh
```

Runs a syntax check over every shell script and exercises the wsl.conf
helpers, both stages in dry-run mode and the real user stage in a temporary
`HOME`. It requires no root and no network.

## See also

- `docs/en/usage.md` / `docs/es/usage.md` - the two-stage walkthrough.
- `docs/en/configuration.md` / `docs/es/configuration.md` - exactly what each
  stage changes.
- `docs/en/architecture.md` / `docs/es/architecture.md` - end-to-end flow and
  mapping to the official WSL documentation.
- [equislinux/wsl](https://github.com/equislinux/wsl) - builds the importable rootfs.
