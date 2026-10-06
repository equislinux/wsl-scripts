# Que configura

Este repositorio gestiona la parte de usuario de X Linux en WSL. El cableado
de sistema de WSL pertenece al rootfs de `equislinux/wsl` y no se toca:
`/etc/wsl.conf` (systemd, red), el manejo de kernel/modulos y la habilitacion
de interop de Windows quedan fuera del alcance de estos scripts. La unica
excepcion es la clave `[user] default`: al crear un usuario real, este
repositorio fija esa clave a el, porque las distribuciones importadas no
tienen launcher de Windows y `/etc/wsl.conf` es la unica via soportada para
cambiar su usuario por defecto. Solo se toca ese valor, nunca el resto del
fichero.

## Fase de sistema (`stage-root.sh`, root)

| Area      | Fichero / accion                                          |
|-----------|-----------------------------------------------------------|
| Locale    | activa el locale en `/etc/locale.gen`, ejecuta `locale-gen`, escribe `LANG` en `/etc/locale.conf` |
| Teclado   | escribe `KEYMAP` en `/etc/vconsole.conf`                  |
| Zona horaria | enlaza `/usr/share/zoneinfo/<zona>` a `/etc/localtime` y, con systemd activo, llama a `timedatectl set-timezone`. Con `windows-time` no escribe nada (WSL refleja el reloj de Windows) |
| Herramientas | `pacman -S sudo git curl wget` (mas el shell de login si no esta); se omite sin red o con `--no-install` |
| Usuario   | crea o asegura el usuario, lo anade a `wheel` y fija su shell de login |
| Sudo      | `/etc/sudoers.d/x-wsl-wheel` con `%wheel ALL=(ALL:ALL) NOPASSWD: ALL` (`nopasswd`, el default) o `%wheel ALL=(ALL:ALL) ALL` (`password`); con `password` la contrasena del usuario se pide interactivamente |
| Usuario por defecto | fija `[user] default=<usuario>` en `/etc/wsl.conf` (default; desactivable con `X_SET_DEFAULT_USER=0`). Si falta `/etc/wsl.conf` o se desactiva, la fase muestra guia |
| Nota      | `/etc/profile.d/x-wsl.sh` registra el resumen de sistema   |

La politica de sudo por defecto en WSL es `nopasswd`: la distro es un equipo
personal de un solo usuario y esto mantiene el flujo automatico. Elige
`password` cuando el usuario necesite una frontera de credenciales (entonces
se pide y fija una contrasena).

El usuario por defecto de la distribucion se cambia mediante la clave
`[user] default` de `/etc/wsl.conf`, el metodo documentado para
distribuciones importadas. WSL lo lee al arrancar la instancia, asi que la
fase indica salir y relanzar antes de la fase de usuario. Cuando falta
`/etc/wsl.conf` o el pin se desactivo, un aviso explica como fijar la clave a
mano o lanzar con `wsl -d <distro> -u <usuario>`.

## Fase de usuario (`stage-user.sh`, usuario normal)

| Area       | Resultado                                                    |
|------------|--------------------------------------------------------------|
| Editor     | `EDITOR`/`VISUAL`: `X_EDITOR` si esta definido, si no el primero de `vim`, `nano`, `vi` encontrado en el sistema |
| Directorios XDG | `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` bajo `$HOME` |
| PATH       | `$HOME/.local/bin` y `$HOME/bin` antepuestos sin quitar entradas existentes |
| Prompt     | `PROMPT` (zsh) o `PS1` (bash) amigables                      |
| Aliases    | `l`, `ll`, `la`, `grep` con color, `..`, `...`               |
| Carpetas   | crea `~/.local/bin`, `~/.config/x`, `~/Projects`             |

Todo el bloque de entorno se escribe entre dos marcadores
(`# >>> equislinux/wsl-scripts: user environment` y su marcador de fin) dentro de
`~/.profile` y `~/.bashrc` (con shell de login zsh el bloque va a `~/.zprofile`
y `~/.zshrc`). Volver a ejecutar la fase reemplaza solo ese bloque, asi que tus
ediciones en el resto de los rc se conservan.

## Interop con Windows

Las entradas de interop de WSL ya presentes en `PATH` (por ejemplo
`/mnt/c/...`) nunca se eliminan: la higiene de PATH solo antepone los binarios
del usuario. Las variables `WSL_INTEROP` y relacionadas no se tocan.

## Ficheros que cambian

- `/etc/locale.gen`, `/etc/locale.conf`, `/etc/vconsole.conf`, `/etc/localtime`
- `/etc/sudoers.d/x-wsl-wheel`
- `/etc/profile.d/x-wsl.sh`
- `/etc/wsl.conf` - solo el valor `[user] default` (el resto intacto)
- `~/.profile`, `~/.bashrc` (o `~/.zprofile`, `~/.zshrc` con zsh)
- `~/.local/bin`, `~/.config/x`, `~/Projects`
