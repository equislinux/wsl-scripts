# Architecture

This document explains how the X Linux WSL experience is put together across
the repositories of the [equislinux](https://github.com/equislinux) organization and how
the pieces map to the official WSL documentation
(https://learn.microsoft.com/windows/wsl). It is the counterpart of
`docs/architecture.md` in the `equislinux/wsl` repository, seen from the setup
side.

## The end-to-end flow

X Linux for WSL is headless (terminal only). Three repositories work in
sequence to produce a running, provisioned distribution:

```
  equislinux/wsl                  equislinux/wsl            equislinux/wsl-scripts
  (Arch host)                (Windows host)       (inside the distro)
  ----------------           ----------------     ----------------
  1. build-rootfs.sh         2. install.ps1       3. install.sh (root)
     pacstrap of a minimal      wsl --import         system stage:
     Arch rootfs, with a         --version 2          locale, keymap,
     default /etc/wsl.conf       (WSL 2)              timezone, tools,
     (systemd on, [user]         wsl --set-default    sudo user; pins
     default=root, [time])                            [user] default
                                  4. exit, relaunch
        out/x-wsl-rootfs.tar.gz    5. install.sh (user)
                                          user stage: shell, env, folders
```

`wsl` is the *distro* repository: it produces the importable rootfs and hosts
the Windows-side importer. `wsl-scripts` is the *setup* repository: it runs
inside the imported distribution and configures the system and the user. Each
repository is independent, with its own origin and release on `main`.

## Where each concern lives

| Concern                        | Repository       | File / action                                |
|--------------------------------|------------------|----------------------------------------------|
| Rootfs build (Arch host)       | `wsl`            | `build-rootfs.sh` (pacstrap + templates)     |
| WSL import on Windows          | `wsl`            | `install.ps1` (`wsl --import --version 2`)   |
| Per-distro WSL settings        | `wsl`            | `templates/wsl.conf` -> `/etc/wsl.conf`      |
| Global WSL 2 settings example  | `wsl`            | `templates/.wslconfig` (host-side)           |
| System provisioning            | `wsl-scripts`    | `stage-root.sh` (via `install.sh`)           |
| User provisioning              | `wsl-scripts`    | `stage-user.sh` (via `install.sh`)           |

## Mapping to the official WSL documentation

The rootfs ships `/etc/wsl.conf` (built from `templates/wsl.conf`) so that a
freshly imported distribution behaves as a modern, systemd-managed system.
Every key used maps directly to the official settings reference:

| Setting used in `/etc/wsl.conf`      | Official section / key                  | Notes |
|--------------------------------------|-----------------------------------------|-------|
| `[boot] systemd=true`                | [Systemd support](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#systemd-support) | Requires the Microsoft Store build of WSL and Windows 11 (or Server 2022). |
| `[user] default=root` initially      | [User settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#user-settings) | Imported distributions boot as root until a real user is set here. Changed to the created user by `wsl-scripts`. |
| `[interop] enabled / appendWindowsPath` | [Interop settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#interop-settings) | Keeps Windows interop (running `.exe`, Windows PATH) available. |
| `[network] generateHosts / generateResolvConf` | [Network settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#network-settings) | WSL owns `/etc/hosts` and `/etc/resolv.conf`. |
| `[time] useWindowsTimezone=true`     | [Time settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#time-settings) | The instance clock and timezone follow Windows. |

The host-side `templates/.wslconfig` documents global WSL 2 VM settings
(`memory`, `processors`, `guiApplications=false` for a headless distro, and
the `[experimental]` `autoMemoryReclaim` / `sparseVhd` keys). Both files are
explained in [Global settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#wslconfig).
WSL has no default `.wslconfig`; it must be created in `%UserProfile%`, which
is why the importer only offers guidance and never overwrites an existing one.

See `docs/en/import.md` in the `wsl` repository for the build and import
walkthrough.

## Why the default user matters

WSL starts a session as the user named by `[user] default` in `/etc/wsl.conf`.
For distributions installed from the Store that value is the first-run user;
for an **imported** distribution there is no first-run wizard and no Windows
launcher, so:

- the value must already exist in the distribution, otherwise WSL refuses to
  start (which is why the rootfs ships `default=root`);
- it can only be changed through `/etc/wsl.conf` - the
  `wslconfig.exe`-style `config --default-user` launcher command does **not**
  work for imported distributions.

This repository therefore creates the real user in the system stage and then
pins `[user] default` to it. Because WSL reads `/etc/wsl.conf` on instance
start (and needs the instance to stop first, the so-called "8 second rule"),
the stage asks you to exit and relaunch before running the user stage. The
helper functions that read and rewrite only the `[user] default` value live in
`lib/common.sh` and are covered by `test/smoke.sh`.

## Settings the stages apply

### System stage (`stage-root.sh`, as root)

- Enables a locale in `/etc/locale.gen`, runs `locale-gen`, sets `LANG` in
  `/etc/locale.conf`.
- Writes the console keymap to `/etc/vconsole.conf`.
- With a concrete IANA zone, links `/usr/share/zoneinfo/<zone>` to
  `/etc/localtime`; the default `windows-time` writes nothing, because WSL
  mirrors the Windows timezone. This matches the default of the `[time]`
  section in `/etc/wsl.conf`.
- Installs base tools with pacman (`sudo git curl wget`, plus the login shell
  when it is not already present).
- Creates (or ensures) the user, adds it to `wheel`, sets its login shell and
  writes the sudo policy to `/etc/sudoers.d/x-wsl-wheel` (`nopasswd` by
  default, recommended for a personal WSL box).
- Pins `[user] default` in `/etc/wsl.conf` to the created user (unless
  disabled with `X_SET_DEFAULT_USER=0` or no `/etc/wsl.conf` is present).

### User stage (`stage-user.sh`, as the created user)

- Appends a marked environment block (editor, XDG dirs, PATH hygiene that
  keeps WSL interop, prompt, aliases) to the login rc files.
- Creates `~/.local/bin`, `~/.config/x` and `~/Projects`.
- Re-running only replaces the marked block, so edits elsewhere in the rc
  files survive (idempotent).

## Running model

- `install.sh` is the friendly, single entry point. Run once as root (system
  stage), relaunch the distribution, then run it again as your user (user
  stage). `setup.sh` is the lower-level dispatcher with the same options.
- Both stages honour `X_AUTO=1` (defaults, no prompts) and `X_DRY=1` (print
  the plan, change nothing).
- Neither stage needs external infrastructure: the smoke test
  (`test/smoke.sh`) exercises syntax, the wsl.conf helpers and both stages in
  dry-run/isolated mode and passes without root or network access.
