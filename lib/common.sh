#!/usr/bin/env bash
# Utilidades compartidas: logging, ejecución en dry-run, enlaces simbólicos.

DRY_RUN="${DRY_RUN:-false}"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_BLUE=$'\033[34m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
else
  C_RESET=; C_BOLD=; C_DIM=; C_BLUE=; C_GREEN=; C_YELLOW=; C_RED=
fi

banner() { printf '\n%s╭─ %s ─╮%s\n\n' "$C_BOLD$C_BLUE" "$1" "$C_RESET"; }
step()   { printf '%s▸%s %s\n' "$C_BLUE" "$C_RESET" "$1"; }
ok()     { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
info()   { printf '%s  %s%s\n' "$C_DIM" "$1" "$C_RESET"; }
warn()   { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$1" >&2; }
die()    { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Ejecuta un comando, o lo imprime si DRY_RUN=true.
run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '%s  $ %s%s\n' "$C_DIM" "$*" "$C_RESET"
    return 0
  fi
  "$@"
}

is_wsl() { [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; }

systemd_running() { [[ -d /run/systemd/system ]]; }

require_ubuntu_noble() {
  [[ -r /etc/os-release ]] || die "No se puede leer /etc/os-release; se espera Ubuntu."
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || die "Este script es para Ubuntu (detectado: ${PRETTY_NAME:-desconocido})."
  if [[ "${VERSION_ID:-}" != "24.04" ]]; then
    warn "Probado en Ubuntu 24.04 LTS; detectado ${VERSION_ID:-?}. Continuando."
  fi
  have sudo || die "Se requiere 'sudo'."
}

# link <origen> <destino>: crea un symlink respaldando lo que hubiera antes.
link() {
  local src="$1" dest="$2"
  [[ -e "$src" ]] || { warn "No existe $src; se omite el enlace"; return 0; }

  if [[ -L "$dest" && "$(readlink -f "$dest")" == "$(readlink -f "$src")" ]]; then
    ok "$(basename "$dest") ya enlazado"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "(dry-run) ln -sfn $src $dest"
    return 0
  fi

  mkdir -p "$(dirname "$dest")"
  if [[ -e "$dest" || -L "$dest" ]]; then
    local backup="$dest.bak.$(date +%Y%m%d%H%M%S)"
    mv "$dest" "$backup"
    info "Respaldo: $backup"
  fi
  ln -sfn "$src" "$dest"
  ok "$dest → $src"
}

# Ficheros que se enlazan a $HOME, como pares "ruta-en-repo|destino".
# Fuente única: la usan install.sh (para crearlos) y verify.sh (para
# comprobarlos), de modo que no puedan desincronizarse.
dotfiles_links() {
  cat <<PAIRS
config/zshrc|$HOME/.zshrc
config/zshenv|$HOME/.zshenv
config/gitconfig|$HOME/.gitconfig
config/gitignore|$HOME/.gitignore_global
config/mise.toml|$HOME/.config/mise/config.toml
config/default-gems|$HOME/.default-gems
config/nvim/init.lua|$HOME/.config/nvim/init.lua
PAIRS
}
