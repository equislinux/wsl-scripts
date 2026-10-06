# Uso

Configuracion de X Linux para WSL solo desde terminal. Dos partes, ejecutadas
desde un checkout de este repositorio tras importar el rootfs de
[equislinux/wsl](https://github.com/equislinux/wsl).

El punto de entrada es `install.sh`, que se ejecuta dos veces. `setup.sh` es
el despachador directo y acepta las mismas opciones.

## Parte 1 - Sistema (root)

Una importacion nueva de WSL arranca como root. Deja un checkout de este
repositorio donde puedan leerlo tanto root como el futuro usuario (por
ejemplo `/opt/x-wsl-scripts`, no `/root`), y ejecuta el instalador:

```bash
./install.sh
```

El instalador detecta que eres root y ejecuta la fase de sistema. Pregunta
por:

- locale a activar y usar como `LANG` (por defecto `en_US.UTF-8`);
- mapa de teclado de consola (por defecto `us`);
- zona horaria (por defecto `windows-time`, que deja que WSL refleje el reloj
  de Windows; puedes elegir `UTC` o cualquier zona IANA como `Europe/Madrid`);
- usuario a crear o asegurar (por defecto el de `SUDO_USER`, si no `x`);
- shell de login para el usuario (`zsh` por defecto, o `bash`);
- politica de sudo: `nopasswd` (recomendada en WSL, por defecto) o
  `password`;
- si hacer que ese usuario sea el de las nuevas sesiones de WSL (recomendado,
  por defecto si).

Puedes saltarte las preguntas pasando los valores directamente. Cualquier
opcion de sistema se reenvia a la fase de sistema:

```bash
sudo ./install.sh --locale es_ES.UTF-8 --keymap es \
    --timezone Europe/Madrid --user dev --shell zsh --sudo nopasswd
```

Tambien se puede hacer sin argumentos mediante variables de entorno:

```bash
export X_LOCALE=de_DE.UTF-8 X_KEYMAP=de X_TIMEZONE=Europe/Berlin \
       X_USER=dev X_SUDO=nopasswd
sudo ./install.sh
```

Para saltar la instalacion de herramientas base (`sudo git curl wget`, mas el
shell de login si no esta), usa `--no-install` o `X_INSTALL=0`. Para seguir
entrando como root en vez de fijar el usuario nuevo, usa `X_SET_DEFAULT_USER=0`.

La fase solo aplica las acciones pedidas; con `X_DRY=1` no se aplica nada y
con `X_AUTO=1` se usan los valores por defecto sin preguntar.

### Relanzar

Cuando termina la fase de sistema, sal de la sesion y relanza la distribucion
para que WSL aplique el `/etc/wsl.conf` actualizado:

```powershell
wsl --terminate <distro>
wsl -d <distro>
```

Si se fijo el usuario por defecto (lo habitual), la nueva sesion se abre con
ese usuario. Si no, lanzala explicitamente: `wsl -d <distro> -u <usuario>`.

## Parte 2 - Usuario

Ya con el usuario creado, ejecuta el instalador otra vez desde el mismo
checkout:

```bash
cd /opt/x-wsl-scripts
./install.sh
```

Ejecutarlo con sudo tambien funciona y apunta a `SUDO_USER`:

```bash
sudo ./install.sh
```

La fase de usuario exporta el entorno desde `~/.profile` y `~/.bashrc`
(`~/.zprofile` y `~/.zshrc` si el shell de login es zsh), crea
`~/.local/bin`, `~/.config/x` y `~/Projects`, y muestra los siguientes pasos.

## Referencia de opciones (fase de sistema)

| Opcion         | Env                  | Por defecto    | Valores                           |
|----------------|----------------------|----------------|-----------------------------------|
| `--locale`     | `X_LOCALE`           | `en_US.UTF-8`  | cualquier locale, p.ej. `es_ES.UTF-8` |
| `--keymap`     | `X_KEYMAP`           | `us`           | mapa de consola                   |
| `--timezone`   | `X_TIMEZONE`         | `windows-time` | `windows-time`, `UTC`, zona IANA  |
| `--user`       | `X_USER`             | `SUDO_USER`/`x`| nombre de usuario                 |
| `--shell`      | `X_SHELL`            | `zsh`          | `zsh`, `bash` o una ruta          |
| `--sudo`       | `X_SUDO`             | `nopasswd`     | `nopasswd`, `password`            |
| `--no-install` | `X_INSTALL=0`        | instalar       | -                                 |
| -              | `X_SET_DEFAULT_USER` | `1`            | `1` (fijar usuario), `0` (root)   |

## Banderas de automatizacion

- `X_AUTO=1` - usa los valores por defecto sin preguntar (requiere no tty).
- `X_DRY=1`  - imprime el plan sin aplicar nada.

Ver [configuration.md](configuration.md) para ver exactamente que cambia cada
fase.
