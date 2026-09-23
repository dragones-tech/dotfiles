# dotfile

Provisión de un entorno de desarrollo en **WSL / Ubuntu 24.04 LTS**.

## Qué instala

**Paquetes del sistema (apt)**

| | |
|---|---|
| Shell | `zsh` + Oh My Zsh (tema `robbyrussell`) |
| Locale/fuentes | `locales`, `fontconfig` + JetBrainsMono Nerd Font |
| Git | `git`, `gh` (GitHub CLI, repo oficial) |
| Red | `openssh-client`, `openssh-server`, `rsync`, `curl`, `wget` |
| Archivos | `zip`, `unzip`, `jq` |
| Toolchain | `build-essential`, `pkg-config` + cabeceras para compilar Ruby/Python |
| Bases de datos | PostgreSQL 18 servidor + cliente + `libpq-dev` (repo PGDG), `sqlite3` |
| Editor | `neovim` |
| WSL | `wslu` (aporta `wslview`) |
| Agentes | [herdr](https://herdr.dev) (instalador oficial, no apt) |

**Runtimes administrados con [mise](https://mise.jdx.dev)** — declarados en `config/mise.toml`:

`ruby 4.0` · `python 3.14` · `node 24` (LTS) · `uv` · `pnpm` ·
`fresh` (vía backend `ubi` → `github:sinelaw/fresh`)

**Shell**

- **Oh My Zsh** con el tema **`robbyrussell`** (el de serie: `➜ dir git:(rama) ✗`).
- Plugins: `git`, `gh`, `sudo` (doble `ESC` reejecuta con sudo), `extract`
  (`x fichero.tar.gz`), `zsh-autosuggestions` y `zsh-syntax-highlighting`
  (estos dos se clonan en `~/.oh-my-zsh/custom/plugins`).
- Los updates de Oh My Zsh están en modo *recordatorio*, no automáticos.

## Fuentes y locale

Dos cosas distintas que suelen confundirse:

1. **El locale** — `robbyrussell` dibuja `➜` y `✗`. Sin un locale UTF-8 salen
   como `?`. El script genera `en_US.UTF-8` y `es_ES.UTF-8` y fija
   `LANG=en_US.UTF-8` (cámbialo en `config/zshenv`).
2. **La fuente** — en WSL la elige **Windows Terminal**, no la distro, así que
   instalar la fuente dentro de Linux no cambia nada en tu terminal. El script
   hace las dos mitades:
   - la instala en WSL (`~/.local/share/fonts/JetBrainsMono` + `fc-cache`),
     que es lo que sirve si alguna vez usas apps GUI por WSLg;
   - copia los cuatro cortes (regular/bold/italic/bold-italic) a
     `…/Downloads/JetBrainsMono-NerdFont` en tu carpeta de usuario de Windows.

   **El paso final es manual y tuyo**: abre esa carpeta en Windows, selecciona
   los `.ttf`, clic derecho → *Instalar para todos los usuarios*. Después, en
   Windows Terminal → Configuración → tu perfil → Apariencia → Tipo de letra →
   **JetBrainsMono Nerd Font**.

   Estrictamente `robbyrussell` no necesita una Nerd Font — con cualquier fuente
   monoespaciada UTF-8 se ve bien. La Nerd Font es para que no te falten glyphs
   si más adelante usas temas con iconos. Omítela con `--skip-font`.

**Editores**

- **Neovim** con una configuración mínima sin plugins (`config/nvim/init.lua`).
- **[fresh](https://getfresh.dev)** — editor de terminal en Rust con atajos
  familiares (`Ctrl+S` guardar, `Ctrl+P` paleta, `Ctrl+E` explorador) y
  soporte de ratón. Alias: `f`.

**Dotfiles enlazados** (symlinks, con respaldo de lo previo):

`~/.zshrc` · `~/.zshenv` · `~/.gitconfig` · `~/.gitignore_global` ·
`~/.config/mise/config.toml` · `~/.default-gems` · `~/.config/nvim/init.lua`

## Agentes de código

**[herdr](https://herdr.dev)** es un servidor que mantiene agentes de código
corriendo en segundo plano. El script lo instala con su instalador oficial
(verifica el SHA-256 contra el manifiesto de herdr.dev, el mismo que usa
`herdr update`) y deja el binario en `~/.local/bin`. Arráncalo con:

```bash
herdr
```

Omítelo con `--skip-agents`.

## Uso

Desde cero, sin clonar a mano:

```bash
curl -fsSL https://raw.githubusercontent.com/dragones-tech/dotfiles/main/bootstrap.sh | bash
```

`bootstrap.sh` instala `git` si falta, clona el repo en `~/.dotfiles` (o lo
actualiza con un `git pull --ff-only` si ya está) y ejecuta `install.sh`. Los
argumentos se le pasan tal cual al instalador:

```bash
curl -fsSL .../bootstrap.sh | bash -s -- --dry-run
```

Se puede cambiar el destino y el origen con `DOTFILES_DIR`, `DOTFILES_REPO` y
`DOTFILES_BRANCH`.

O clonando tú mismo:

```bash
git clone https://github.com/dragones-tech/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh
exec zsh
```

Opciones:

```bash
./install.sh --dry-run          # imprime cada comando sin ejecutarlo
./install.sh --skip-postgres    # omite el repo y el servidor PostgreSQL
./install.sh --no-chsh          # no cambia la shell por defecto a zsh
./install.sh --skip-font        # no descarga la Nerd Font
./install.sh --skip-agents      # omite herdr
```

El script es idempotente: se puede volver a ejecutar sin efectos duplicados.

## Validación

`verify.sh` comprueba que el entorno quedó bien y **sale con código != 0** si
algo falla, así que sirve en CI o para validar una prueba en contenedor sin
leer el log entero:

```bash
~/.dotfiles/verify.sh           # detalle de cada comprobación
~/.dotfiles/verify.sh --quiet   # solo los fallos y el recuento
```

Comprueba que los symlinks apuntan al repo, que **zsh arranca sin errores**
(`config/zshrc` se enlaza pero nunca se ejecuta durante la instalación: un
error de sintaxis ahí dejaría rota toda shell nueva y `install.sh` terminaría
en verde), que `~/.local/bin` está en el PATH, que los runtimes coinciden con
las versiones de `config/mise.toml`, y que git lee de verdad el `gitconfig`
enlazado.

Lo que depende de las banderas `--skip-*` (PostgreSQL, herdr, fresh) se marca
como omitido en vez de fallar.

## Notas para WSL

- **systemd**: sin él, los servicios se arrancan a mano
  (`sudo service postgresql start`, `sudo service ssh start`).
  Para habilitarlo, añade a `/etc/wsl.conf` y ejecuta `wsl --shutdown` en Windows:

  ```ini
  [boot]
  systemd=true
  ```

- **sshd** queda instalado pero deshabilitado; en WSL rara vez hace falta.
- PostgreSQL crea un rol superusuario con tu nombre de usuario, así que
  `psql` funciona sin flags.

## Personalización

- Versiones de runtimes → `config/mise.toml` (y `MISE_TOOLS` en `install.sh`).
- Paquetes de apt → array `APT_PACKAGES` en `install.sh`.
- Ajustes de zsh que no quieras versionar → `~/.zshrc.local` (se carga al final).
- Tema y plugins de Oh My Zsh → `ZSH_THEME` y `plugins=(…)` en `config/zshrc`.
- Locales generados y `LANG` → array `LOCALES` en `install.sh`.
- Otra Nerd Font → variable `NERD_FONT` en `install.sh` (nombre del zip en
  [nerd-fonts releases](https://github.com/ryanoasis/nerd-fonts/releases)).
- Paquetes específicos de WSL → array `WSL_PACKAGES` en `install.sh`.
- Identidad de git (`user.name` / `user.email`) **no** está en `config/gitconfig`
  a propósito; ponla en `~/.gitconfig.local` o ejecuta:

  ```bash
  git config --global user.name  "Tu Nombre"
  git config --global user.email "tu@correo.com"
  ```

## Estructura

```
bootstrap.sh        clona el repo y lanza install.sh (para 'curl | bash')
install.sh          orquestador, idempotente
verify.sh           comprueba el resultado; sale != 0 si algo falla
lib/common.sh       logging, dry-run, symlinks con respaldo
config/             ficheros que se enlazan a $HOME
```

El repo tiene que quedarse donde se clone: `install.sh` crea symlinks que
**apuntan** a `config/`, así que borrar `~/.dotfiles` rompe la configuración.

## Atajos útiles

| | |
|---|---|
| `v` / `vi` / `vim` | Neovim |
| `f` | `fresh` |
| `open <fichero\|url>` | lo abre con la app de Windows (`wslview`) |
| `pg start` | arranca PostgreSQL en WSL |
| `x <archivo>` | descomprime cualquier formato (plugin `extract`) |
| `ESC` `ESC` | reejecuta el último comando con `sudo` (plugin `sudo`) |
