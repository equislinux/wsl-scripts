# Usage

Terminal-only setup for X Linux on WSL. Two parts, run from a checkout of this
repository after importing the rootfs from [equislinux/wsl](https://github.com/equislinux/wsl).

The entry point is `install.sh`, run twice. `setup.sh` is the direct
dispatcher and accepts the same options.

## Part 1 - System (root)

A fresh WSL import boots as root. Put a checkout of this repository where
both root and the future user can read it (for example `/opt/x-wsl-scripts`,
not `/root`), then run the installer:

```bash
./install.sh
```

The installer detects that you are root and runs the system stage. It asks
for:

- locale to enable and set as `LANG` (default `en_US.UTF-8`);
- keyboard keymap for the console (default `us`);
- timezone (default `windows-time`, which lets WSL mirror the Windows clock;
  you can pick `UTC` or any IANA zone such as `Europe/Madrid`);
- user to create or ensure (default from `SUDO_USER`, otherwise `x`);
- login shell for the user (`zsh` by default, or `bash`);
- sudo policy: `nopasswd` (recommended on WSL, default) or `password`;
- whether to make that user the default user of new WSL sessions
  (recommended, default yes).

You can skip the prompts by passing the values directly. Any system option
forwards to the system stage:

```bash
sudo ./install.sh --locale es_ES.UTF-8 --keymap es \
    --timezone Europe/Madrid --user dev --shell zsh --sudo nopasswd
```

The same can be done without arguments through environment variables:

```bash
export X_LOCALE=de_DE.UTF-8 X_KEYMAP=de X_TIMEZONE=Europe/Berlin \
       X_USER=dev X_SUDO=nopasswd
sudo ./install.sh
```

To skip the base-tool install (`sudo git curl wget`, plus the login shell when
it is not present), use `--no-install` or `X_INSTALL=0`. To keep logging in as
root instead of pinning the new user, use `X_SET_DEFAULT_USER=0`.

The stage applies only the requested actions; with `X_DRY=1` nothing is
changed and with `X_AUTO=1` the defaults are used without prompting.

### Relaunch

When the system stage finishes, exit the session and relaunch the
distribution so WSL applies the updated `/etc/wsl.conf`:

```powershell
wsl --terminate <distro>
wsl -d <distro>
```

If the default user was pinned (the default), the new session opens as that
user. Otherwise launch it explicitly: `wsl -d <distro> -u <user>`.

## Part 2 - User

Logged in as the created user, run the installer again from the same checkout:

```bash
cd /opt/x-wsl-scripts
./install.sh
```

Running it through sudo also works and targets `SUDO_USER`:

```bash
sudo ./install.sh
```

The user stage exports the environment from `~/.profile` and `~/.bashrc`
(`~/.zprofile` and `~/.zshrc` when the login shell is zsh), creates
`~/.local/bin`, `~/.config/x` and `~/Projects`, and prints the next steps.

## Options reference (system stage)

| Option            | Env                  | Default        | Values                          |
|-------------------|----------------------|----------------|---------------------------------|
| `--locale`        | `X_LOCALE`           | `en_US.UTF-8`  | any locale, e.g. `es_ES.UTF-8`  |
| `--keymap`        | `X_KEYMAP`           | `us`           | console keymap                  |
| `--timezone`      | `X_TIMEZONE`         | `windows-time` | `windows-time`, `UTC`, IANA zone|
| `--user`          | `X_USER`             | `SUDO_USER`/`x`| user name                       |
| `--shell`         | `X_SHELL`            | `zsh`          | `zsh`, `bash` or a path         |
| `--sudo`          | `X_SUDO`             | `nopasswd`     | `nopasswd`, `password`          |
| `--no-install`    | `X_INSTALL=0`        | install        | -                               |
| -                 | `X_SET_DEFAULT_USER` | `1`            | `1` (pin user), `0` (keep root) |

## Automation flags

- `X_AUTO=1` - use defaults without prompting (requires no tty).
- `X_DRY=1`  - print the plan, apply nothing.

See [configuration.md](configuration.md) for exactly what each stage changes.
