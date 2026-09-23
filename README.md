# dotfile

Mi entorno de desarrollo en WSL / Ubuntu 24.04.

## Instalación

```bash
curl -fsSL https://raw.githubusercontent.com/dragones-tech/dotfiles/main/bootstrap.sh | bash
exec zsh
```

Clona el repo en `~/.dotfiles` y lo instala todo. Se puede volver a ejecutar
cuando quieras: no duplica nada.

Déjalo donde está — la configuración son enlaces que apuntan ahí.

Para comprobar que quedó bien:

```bash
~/.dotfiles/verify.sh
```

Opciones, por si alguna vez estorban:

```bash
./install.sh --dry-run        # enseña lo que haría, sin hacerlo
./install.sh --skip-postgres  # sin el servidor PostgreSQL
./install.sh --skip-font      # sin la Nerd Font
./install.sh --skip-agents    # sin herdr
./install.sh --no-chsh        # sin cambiar la shell por defecto
```

## Qué instala

**Shell** — zsh con Oh My Zsh, tema `robbyrussell`, autosuggestions y
syntax-highlighting. Locale UTF-8 y JetBrainsMono Nerd Font.

**Runtimes**, vía [mise](https://mise.jdx.dev) — Ruby 4.0, Python 3.14,
Node 24, uv, pnpm.

**Bases de datos** — PostgreSQL 18 (servidor y cliente) y SQLite 3.

**Editores** — Neovim con una configuración mínima, y
[fresh](https://getfresh.dev), un editor de terminal con atajos familiares.

**Herramientas** — git, gh, openssh, rsync, curl, wget, jq, zip/unzip,
build-essential y las cabeceras para compilar Ruby y Python.

**Agentes** — [herdr](https://herdr.dev), que mantiene agentes de código
corriendo en segundo plano.

**Configuración** enlazada a `$HOME` — `.zshrc`, `.zshenv`, `.gitconfig`,
`.gitignore_global`, `.default-gems`, la de mise y la de Neovim.

La identidad de git no está aquí a propósito. Ponla en `~/.gitconfig.local`:

```bash
git config --global user.name  "Tu Nombre"
git config --global user.email "tu@correo.com"
```

## Nota sobre la fuente

En WSL la fuente la elige Windows Terminal, no la distro. El script copia los
`.ttf` a tu carpeta `Downloads` de Windows; instalarlos y seleccionarlos en
Windows Terminal → Apariencia → Tipo de letra es cosa tuya.
