# Arquitectura

Este documento explica como se ensambla la experiencia de X Linux en WSL entre
los repositorios de la organizacion [equislinux](https://github.com/equislinux) y como
cada pieza se corresponde con la documentacion oficial de WSL
(https://learn.microsoft.com/windows/wsl). Es la contrapartida de
`docs/architecture.md` del repositorio `equislinux/wsl`, vista desde el lado del
setup.

## Flujo completo

X Linux para WSL es headless (solo terminal). Tres repositorios trabajan en
secuencia para producir una distribucion corriendo y aprovisionada:

```
  equislinux/wsl                  equislinux/wsl            equislinux/wsl-scripts
  (host Arch)                (host Windows)       (dentro de la distro)
  ----------------           ----------------     ----------------
  1. build-rootfs.sh         2. install.ps1       3. install.sh (root)
     pacstrap de un rootfs      wsl --import         fase de sistema:
     Arch minimo, con un         --version 2          locale, keymap,
     /etc/wsl.conf inicial       (WSL 2)              zona horaria,
     (systemd activo, [user]     wsl --set-default    herramientas,
     default=root, [time])                            usuario con sudo;
                                                      fija [user] default
                                  4. exit, relanza       5. install.sh (usuario)
                                                                  fase de usuario:
        out/x-wsl-rootfs.tar.gz                        shell, env, carpetas
```

`wsl` es el repositorio de la *distro*: produce el rootfs importable y aloja
el importador del lado Windows. `wsl-scripts` es el repositorio del *setup*:
corre dentro de la distribucion importada y configura el sistema y el usuario.
Cada repositorio es independiente, con su propio origin y publicacion en
`main`.

## Donde vive cada parte

| Area                           | Repositorio    | Fichero / accion                            |
|--------------------------------|----------------|---------------------------------------------|
| Build del rootfs (host Arch)   | `wsl`          | `build-rootfs.sh` (pacstrap + plantillas)   |
| Importacion WSL en Windows     | `wsl`          | `install.ps1` (`wsl --import --version 2`)  |
| Ajustes WSL por distro         | `wsl`          | `templates/wsl.conf` -> `/etc/wsl.conf`     |
| Ejemplo de ajustes globales    | `wsl`          | `templates/.wslconfig` (lado host)          |
| Aprovisionamiento de sistema   | `wsl-scripts`  | `stage-root.sh` (via `install.sh`)          |
| Aprovisionamiento de usuario   | `wsl-scripts`  | `stage-user.sh` (via `install.sh`)          |

## Correspondencia con la documentacion oficial de WSL

El rootfs incluye `/etc/wsl.conf` (generado desde `templates/wsl.conf`) para
que una distribucion recien importada se comporte como un sistema moderno
gestionado por systemd. Cada clave usada se corresponde con la referencia
oficial de ajustes:

| Ajuste en `/etc/wsl.conf`          | Seccion / clave oficial              | Notas |
|------------------------------------|--------------------------------------|-------|
| `[boot] systemd=true`              | [Systemd support](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#systemd-support) | Requiere la build de WSL de Microsoft Store y Windows 11 (o Server 2022). |
| `[user] default=root` inicial      | [User settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#user-settings) | Las distribuciones importadas arrancan como root hasta fijar aqui un usuario real. `wsl-scripts` lo cambia al usuario creado. |
| `[interop] enabled / appendWindowsPath` | [Interop settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#interop-settings) | Mantiene la interop con Windows (`.exe`, PATH de Windows). |
| `[network] generateHosts / generateResolvConf` | [Network settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#network-settings) | WSL gestiona `/etc/hosts` y `/etc/resolv.conf`. |
| `[time] useWindowsTimezone=true`   | [Time settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#time-settings) | El reloj y la zona horaria de la instancia siguen a Windows. |

El `templates/.wslconfig` del lado host documenta los ajustes globales de la
VM WSL 2 (`memory`, `processors`, `guiApplications=false` para una distro
headless, y las claves `[experimental]` `autoMemoryReclaim` / `sparseVhd`).
Ambos ficheros se explican en
[Global settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#wslconfig).
WSL no tiene `.wslconfig` por defecto; hay que crearlo en `%UserProfile%`, por
eso el importador solo ofrece guia y nunca sobrescribe uno existente.

Ver `docs/en/import.md` del repositorio `wsl` para el paseo de build e
importacion.

## Por que importa el usuario por defecto

WSL inicia la sesion como el usuario indicado por `[user] default` en
`/etc/wsl.conf`. Para las distribuciones de la Store ese valor es el usuario
del primer arranque; para una distribucion **importada** no hay asistente de
primer arranque ni launcher de Windows, asi que:

- el valor debe existir ya en la distribucion, o WSL se niega a arrancar (por
  eso el rootfs trae `default=root`);
- solo se puede cambiar via `/etc/wsl.conf`; el comando de launcher
  `config --default-user` **no** funciona con distribuciones importadas.

Por tanto este repositorio crea el usuario real en la fase de sistema y luego
fija `[user] default` a ese usuario. Como WSL lee `/etc/wsl.conf` al iniciar
la instancia (y la instancia debe detenerse antes, la llamada "regla de los
8 segundos"), la fase pide salir y relanzar antes de ejecutar la fase de
usuario. Las funciones que leen y reescriben solo el valor `[user] default`
viven en `lib/common.sh` y estan cubiertas por `test/smoke.sh`.

## Ajustes que aplican las fases

### Fase de sistema (`stage-root.sh`, como root)

- Activa un locale en `/etc/locale.gen`, ejecuta `locale-gen` y fija `LANG`
  en `/etc/locale.conf`.
- Escribe el keymap de consola en `/etc/vconsole.conf`.
- Con una zona IANA concreta, enlaza `/usr/share/zoneinfo/<zona>` a
  `/etc/localtime`; el default `windows-time` no escribe nada, porque WSL ya
  refleja la zona horaria de Windows. Esto coincide con el default de la
  seccion `[time]` de `/etc/wsl.conf`.
- Instala herramientas base con pacman (`sudo git curl wget`, mas el shell de
  login si no esta).
- Crea (o asegura) el usuario, lo anade a `wheel`, fija su shell de login y
  escribe la politica de sudo en `/etc/sudoers.d/x-wsl-wheel` (`nopasswd` por
  defecto, recomendado para un equipo WSL personal).
- Fija `[user] default` en `/etc/wsl.conf` al usuario creado (salvo que se
  desactive con `X_SET_DEFAULT_USER=0` o no exista `/etc/wsl.conf`).

### Fase de usuario (`stage-user.sh`, como el usuario creado)

- Anade un bloque de entorno marcado (editor, directorios XDG, higiene de
  PATH que conserva la interop de WSL, prompt, alias) a los rc de login.
- Crea `~/.local/bin`, `~/.config/x` y `~/Projects`.
- Repetir la fase reemplaza solo el bloque marcado, de forma que las ediciones
  fuera de el sobreviven (idempotente).

## Modelo de ejecucion

- `install.sh` es el punto de entrada unico y amigable. Se ejecuta una vez
  como root (fase de sistema), se relanza la distribucion y se vuelve a
  ejecutar como usuario (fase de usuario). `setup.sh` es el despachador de
  bajo nivel con las mismas opciones.
- Ambas fases respetan `X_AUTO=1` (defaults, sin preguntas) y `X_DRY=1`
  (imprimir el plan, no cambiar nada).
- Ninguna fase depende de infraestructura externa: el smoke test
  (`test/smoke.sh`) cubre sintaxis, las funciones de wsl.conf y ambas fases en
  modo dry-run/aislado y pasa sin root ni red.
