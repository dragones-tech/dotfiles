#!/usr/bin/env bash
#
# install.sh — Provisiona un entorno de desarrollo en WSL / Ubuntu 24.04 LTS
#
#   Sistema (apt): zsh, git, gh, openssh, rsync, curl/wget, zip/unzip, jq,
#                  build-essential, PostgreSQL 18 + cliente, SQLite 3, Neovim
#   Shell:         Oh My Zsh con el tema 'robbyrussell' + locale UTF-8
#   Fuentes:       JetBrainsMono Nerd Font (en WSL y copiada a Windows)
#   Mise:          ruby 4.0, python 3.14, node 24 (LTS), uv, pnpm,
#                  fresh (editor de terminal)
#   Agentes:       herdr (orquestador de agentes de código)
#
# Uso:
#   ./install.sh                 # todo
#   ./install.sh --skip-postgres # omite el servidor PostgreSQL
#   ./install.sh --skip-font     # no descarga la Nerd Font
#   ./install.sh --skip-agents   # omite herdr
#   ./install.sh --no-chsh       # no cambia la shell por defecto
#   ./install.sh --dry-run       # muestra lo que haría
#
set -Eeuo pipefail

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_DIR

# shellcheck source=lib/common.sh
source "$DOTFILES_DIR/lib/common.sh"

# ── Versiones ────────────────────────────────────────────────────────────────
PG_MAJOR="18"
MISE_TOOLS=(
  "ruby@4.0"
  "python@3.14"
  "node@24"
  "uv@latest"
  "pnpm@latest"
  "github:sinelaw/fresh@latest" # editor de terminal (backend ubi)
)

APT_PACKAGES=(
  # Shell y utilidades base
  zsh git openssh-client rsync curl wget zip unzip jq ca-certificates gnupg
  # Locale UTF-8 y fuentes (los glyphs de robbyrussell necesitan UTF-8)
  locales fontconfig
  # Toolchain de compilación
  build-essential pkg-config
  # Editor
  neovim
  # SQLite
  sqlite3 libsqlite3-dev
  # Dependencias de compilación para Ruby/Python vía mise
  autoconf bison libssl-dev libreadline-dev zlib1g-dev libyaml-dev libffi-dev
  libgmp-dev libncurses-dev libxml2-dev libxslt1-dev libdb-dev uuid-dev
  liblzma-dev libbz2-dev tk-dev
)

# Paquetes que sólo tienen sentido dentro de una distro WSL.
WSL_PACKAGES=(wslu)

SKIP_POSTGRES=false
SKIP_FONT=false
SKIP_AGENTS=false
DO_CHSH=true

# Locales que se generan (el primero es el que se fija como LANG).
LOCALES=(en_US.UTF-8 es_ES.UTF-8)
NERD_FONT="JetBrainsMono"

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-postgres) SKIP_POSTGRES=true ;;
      --skip-font)     SKIP_FONT=true ;;
      --skip-agents)   SKIP_AGENTS=true ;;
      --no-chsh)       DO_CHSH=false ;;
      --dry-run)       DRY_RUN=true ;;
      -h|--help)       sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) die "Opción desconocida: $1 (usa --help)" ;;
    esac
    shift
  done
}

# ── Pasos ────────────────────────────────────────────────────────────────────

apt_bootstrap() {
  step "Actualizando índices de apt"
  run sudo apt-get update -qq
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg lsb-release
}

install_apt_packages() {
  step "Instalando paquetes del sistema"
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    "${APT_PACKAGES[@]}"
}

install_openssh_server() {
  # En WSL el cliente basta casi siempre; el servidor es opcional pero se pide
  # "OpenSSH", así que instalamos ambos y dejamos el daemon deshabilitado.
  step "Instalando OpenSSH (cliente + servidor)"
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    openssh-server
  # El criterio es si hay systemd, no si es WSL: un contenedor tampoco lo tiene
  # y 'systemctl' ni siquiera existe, lo que abortaría el script por pipefail.
  if is_wsl; then
    info "WSL detectado: sshd instalado pero no habilitado (arráncalo con 'sudo service ssh start')"
  elif systemd_running; then
    run sudo systemctl enable --now ssh
  else
    info "Sin systemd: sshd instalado pero no habilitado (arráncalo con 'sudo service ssh start')"
  fi
}

install_github_cli() {
  if have gh; then
    ok "GitHub CLI ya instalado ($(gh --version | head -1))"
    return
  fi
  step "Añadiendo repositorio de GitHub CLI"
  run sudo install -m 0755 -d /etc/apt/keyrings
  run bash -c 'curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null'
  run sudo chmod 0644 /etc/apt/keyrings/githubcli-archive-keyring.gpg
  run bash -c 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null'
  run sudo apt-get update -qq
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y gh
}

install_postgresql() {
  if [[ "$SKIP_POSTGRES" == true ]]; then
    info "Omitiendo PostgreSQL (--skip-postgres)"
    return
  fi
  step "Añadiendo repositorio PGDG (PostgreSQL $PG_MAJOR)"
  run sudo install -m 0755 -d /etc/apt/keyrings
  run bash -c 'curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | sudo gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg'
  run sudo chmod 0644 /etc/apt/keyrings/postgresql.gpg
  run bash -c 'echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
    | sudo tee /etc/apt/sources.list.d/pgdg.list >/dev/null'
  run sudo apt-get update -qq

  step "Instalando PostgreSQL $PG_MAJOR (servidor + cliente + libpq-dev)"
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    "postgresql-$PG_MAJOR" "postgresql-client-$PG_MAJOR" "postgresql-contrib-$PG_MAJOR" libpq-dev

  if systemd_running; then
    run sudo systemctl enable --now postgresql
  elif is_wsl; then
    info "WSL sin systemd: arranca el servidor con 'sudo service postgresql start'"
    info "Para arranque automático, activa systemd en /etc/wsl.conf ([boot] systemd=true)"
  else
    info "Sin systemd: arranca el servidor con 'sudo service postgresql start'"
  fi

  # Rol de superusuario con el nombre del usuario actual → 'psql' sin flags.
  step "Creando rol de PostgreSQL para '$USER'"
  if [[ "$DRY_RUN" == true ]]; then
    info "(dry-run) createuser -s $USER"
  else
    sudo service postgresql start >/dev/null 2>&1 || true
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$USER'" 2>/dev/null | grep -q 1; then
      ok "El rol '$USER' ya existe"
    else
      sudo -u postgres createuser -s "$USER" \
        && sudo -u postgres createdb "$USER" 2>/dev/null || true
      ok "Rol y base de datos '$USER' creados"
    fi
  fi
}

install_mise() {
  if have mise; then
    ok "mise ya instalado ($(mise --version))"
  else
    step "Instalando mise"
    run bash -c 'curl -fsSL https://mise.run | sh'
  fi
  export PATH="$HOME/.local/bin:$PATH"
}

# El tema robbyrussell dibuja ➜ y ✗: sin un locale UTF-8 salen como '?'.
setup_locale() {
  step "Generando locales UTF-8: ${LOCALES[*]}"
  local loc
  for loc in "${LOCALES[@]}"; do
    if [[ "$DRY_RUN" != true ]] && locale -a 2>/dev/null | grep -qix "${loc//-/}"; then
      ok "$loc ya generado"
      continue
    fi
    run sudo locale-gen "$loc"
  done
  run sudo update-locale "LANG=${LOCALES[0]}"
  info "LANG=${LOCALES[0]} (cámbialo en config/zshenv si prefieres otro)"
}

install_oh_my_zsh() {
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    ok "Oh My Zsh ya instalado"
  else
    step "Instalando Oh My Zsh (tema robbyrussell)"
    # --keep-zshrc: no sobreescribe nuestro ~/.zshrc; --unattended: sin chsh ni shell nueva.
    run bash -c 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
      "" --unattended --keep-zshrc'
  fi

  # Plugins externos que config/zshrc declara pero Oh My Zsh no trae.
  local custom="$HOME/.oh-my-zsh/custom/plugins"
  clone_plugin() {
    local name="$1" url="$2"
    if [[ -d "$custom/$name" ]]; then
      ok "plugin $name ya presente"
    else
      step "Clonando plugin $name"
      run git clone --depth 1 "$url" "$custom/$name"
    fi
  }
  run mkdir -p "$custom"
  clone_plugin zsh-autosuggestions     https://github.com/zsh-users/zsh-autosuggestions.git
  clone_plugin zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git
}

# robbyrussell solo necesita UTF-8, no una Nerd Font. Pero en WSL la fuente la
# elige *Windows Terminal*, no la distro, así que instalamos la fuente en ambos
# lados y dejamos dicho qué seleccionar.
install_nerd_font() {
  if [[ "$SKIP_FONT" == true ]]; then
    info "Omitiendo la Nerd Font (--skip-font)"
    return
  fi
  local font_dir="$HOME/.local/share/fonts/$NERD_FONT"
  if [[ -d "$font_dir" ]] && compgen -G "$font_dir/*.ttf" >/dev/null; then
    ok "$NERD_FONT Nerd Font ya instalada en WSL"
  else
    step "Descargando $NERD_FONT Nerd Font"
    local url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$NERD_FONT.zip"
    if [[ "$DRY_RUN" == true ]]; then
      info "(dry-run) curl -fsSL $url | unzip -d $font_dir"
    else
      # Limpieza explícita, no 'trap ... RETURN': en bash ese trap NO muere con
      # la función, sigue armado y vuelve a dispararse en retornos posteriores,
      # cuando '$tmp' (local) ya no existe → "tmp: unbound variable" con set -u.
      local tmp
      tmp="$(mktemp -d)"
      if curl -fsSL -o "$tmp/font.zip" "$url"; then
        mkdir -p "$font_dir"
        # Solo los 4 cortes que usa una terminal; el zip trae ~100 ficheros.
        unzip -qo "$tmp/font.zip" -d "$font_dir" \
          "${NERD_FONT}NerdFont-Regular.ttf" "${NERD_FONT}NerdFont-Bold.ttf" \
          "${NERD_FONT}NerdFont-Italic.ttf" "${NERD_FONT}NerdFont-BoldItalic.ttf"
        fc-cache -f "$font_dir" >/dev/null
        rm -rf "$tmp"
        ok "Instalada en $font_dir"
      else
        rm -rf "$tmp"
        warn "No se pudo descargar la fuente; instálala a mano desde nerdfonts.com"
        return
      fi
    fi
  fi

  # ── Lado Windows ──────────────────────────────────────────────────────────
  is_wsl || return 0
  local win_user_dir
  win_user_dir="$(wslpath "$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')" 2>/dev/null || true)"
  [[ -d "$win_user_dir" ]] || win_user_dir="/mnt/c/Users/$USER"
  local dest="$win_user_dir/Downloads/$NERD_FONT-NerdFont"

  if [[ "$DRY_RUN" == true ]]; then
    info "(dry-run) copiando los .ttf a $dest"
  elif [[ -d "$(dirname "$dest")" ]]; then
    mkdir -p "$dest"
    cp -f "$font_dir"/*.ttf "$dest"/ 2>/dev/null || true
    ok "Copiada a $dest"
  else
    warn "No se encontró la carpeta de usuario de Windows; copia los .ttf a mano"
    return
  fi

  info "Instálala en Windows: abre esa carpeta, selecciona los .ttf,"
  info "clic derecho → 'Instalar para todos los usuarios'."
  info "Luego en Windows Terminal: Configuración → tu perfil → Apariencia →"
  info "Tipo de letra → '$NERD_FONT Nerd Font'."
}

link_configs() {
  step "Enlazando ficheros de configuración"
  local src dest
  while IFS='|' read -r src dest; do
    [[ -n "$src" ]] || continue
    link "$DOTFILES_DIR/$src" "$dest"
  done < <(dotfiles_links)
}

install_mise_tools() {
  step "Instalando runtimes con mise: ${MISE_TOOLS[*]}"
  have mise || die "mise no está en el PATH"
  # config.toml ya declara las versiones; 'use -g' las fija y las instala.
  for tool in "${MISE_TOOLS[@]}"; do
    info "→ $tool"
    run mise use --global --yes "$tool"
  done
  run mise install --yes
}

# ── Extras de WSL ────────────────────────────────────────────────────────────
#
# wslu aporta 'wslview', que abre URLs y ficheros con la app de Windows
# asociada (lo usa el alias 'open' del zshrc).

install_wsl_extras() {
  if ! is_wsl; then
    return
  fi

  step "Instalando utilidades de WSL"
  run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    "${WSL_PACKAGES[@]}"
}

# ── Agentes de código ────────────────────────────────────────────────────────
#
# herdr (https://herdr.dev) es un servidor que mantiene agentes de código
# corriendo en segundo plano.

install_herdr() {
  if have herdr; then
    ok "herdr ya instalado ($(herdr --version 2>/dev/null | head -1))"
    return
  fi
  step "Instalando herdr"
  # El instalador oficial verifica el SHA-256 contra el manifiesto de
  # herdr.dev, el mismo que usa 'herdr update'. Instala en ~/.local/bin.
  run bash -c 'curl -fsSL https://herdr.dev/install.sh | sh'
}

install_agents() {
  if [[ "$SKIP_AGENTS" == true ]]; then
    info "Omitiendo herdr (--skip-agents)"
    return
  fi
  install_herdr
}

set_default_shell() {
  if [[ "$DO_CHSH" != true ]]; then
    info "Omitiendo chsh (--no-chsh)"
    return
  fi
  local zsh_path
  zsh_path="$(command -v zsh || true)"
  [[ -n "$zsh_path" ]] || { warn "zsh no encontrado; no se cambia la shell"; return; }
  if [[ "${SHELL:-}" == "$zsh_path" ]]; then
    ok "zsh ya es la shell por defecto"
    return
  fi
  step "Estableciendo zsh como shell por defecto"
  grep -qxF "$zsh_path" /etc/shells || run bash -c "echo '$zsh_path' | sudo tee -a /etc/shells >/dev/null"
  run sudo chsh -s "$zsh_path" "$USER"
}

summary() {
  echo
  step "Resumen"
  # 'head -1' mata el productor con SIGPIPE; pipefail lo convertiría en error.
  ver() { set +o pipefail; have "$1" || { echo '-'; return 0; }; shift; "$@" 2>/dev/null; }

  printf '  %-10s %s\n' zsh     "$(ver zsh     bash -c "zsh --version | awk '{print \$2}'")"
  printf '  %-10s %s\n' git     "$(ver git     bash -c "git --version | awk '{print \$3}'")"
  printf '  %-10s %s\n' gh      "$(ver gh      bash -c "gh --version | awk 'NR==1{print \$3}'")"
  printf '  %-10s %s\n' rsync   "$(ver rsync   bash -c "rsync --version | awk 'NR==1{print \$3}'")"
  printf '  %-10s %s\n' jq      "$(ver jq      jq --version)"
  printf '  %-10s %s\n' sqlite3 "$(ver sqlite3 bash -c "sqlite3 --version | awk '{print \$1}'")"
  printf '  %-10s %s\n' nvim    "$(ver nvim    bash -c "nvim --version | awk 'NR==1{print \$2}'")"
  printf '  %-10s %s\n' psql    "$(ver psql    bash -c "psql --version | awk '{print \$3}'")"
  printf '  %-10s %s\n' mise    "$(ver mise    bash -c "mise --version | awk '{print \$1}'")"
  printf '  %-10s %s\n' fresh   "$(ver fresh   bash -c "fresh --version | awk '{print \$2}'")"
  printf '  %-10s %s\n' omz     "$([[ -d "$HOME/.oh-my-zsh" ]] && echo 'robbyrussell' || echo '-')"
  printf '  %-10s %s\n' LANG    "${LOCALES[0]}"
  printf '  %-10s %s\n' herdr   "$(ver herdr   bash -c "herdr --version | awk 'NR==1{print \$NF}'")"

  if have mise && [[ "$DRY_RUN" != true ]]; then
    echo
    mise ls --current 2>/dev/null || true
  fi

  echo
  ok "Listo. Abre una shell nueva (o 'exec zsh') para cargar el entorno."
  is_wsl && info "PostgreSQL en WSL: 'sudo service postgresql start'"
  is_wsl && [[ "$SKIP_FONT" != true ]] && \
    info "Recuerda seleccionar '$NERD_FONT Nerd Font' en Windows Terminal"
  [[ "$SKIP_AGENTS" != true ]] && info "Arranca el orquestador de agentes con: herdr"
  return 0
}

main() {
  parse_args "$@"
  require_ubuntu_noble
  banner "Provisionando entorno de desarrollo"

  apt_bootstrap
  install_apt_packages
  install_openssh_server
  install_github_cli
  install_postgresql
  install_mise
  setup_locale
  install_oh_my_zsh
  install_nerd_font
  link_configs
  install_mise_tools
  install_wsl_extras
  install_agents
  set_default_shell
  summary
}

main "$@"
