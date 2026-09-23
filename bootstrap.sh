#!/usr/bin/env bash
#
# bootstrap.sh — Punto de entrada para instalar desde cero, sin clonar a mano:
#
#   curl -fsSL https://raw.githubusercontent.com/dragones-tech/dotfiles/main/bootstrap.sh | bash
#
# Clona el repo en ~/.dotfiles (o lo actualiza si ya está) y ejecuta install.sh.
# Los argumentos se pasan tal cual al instalador:
#
#   curl -fsSL .../bootstrap.sh | bash -s -- --dry-run --skip-postgres
#
# Variables de entorno:
#   DOTFILES_REPO    URL del repo    (por defecto el de arriba)
#   DOTFILES_BRANCH  rama a clonar   (por defecto 'main')
#   DOTFILES_DIR     destino         (por defecto "$HOME/.dotfiles")
#
# Este fichero es deliberadamente autocontenido: se ejecuta *antes* de que el
# repo exista, así que no puede depender de lib/common.sh.
set -Eeuo pipefail

REPO="${DOTFILES_REPO:-https://github.com/dragones-tech/dotfiles.git}"
BRANCH="${DOTFILES_BRANCH:-main}"
DEST="${DOTFILES_DIR:-$HOME/.dotfiles}"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_BLUE=$'\033[34m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
else
  C_RESET=; C_BOLD=; C_DIM=; C_BLUE=; C_GREEN=; C_YELLOW=; C_RED=
fi

step() { printf '%s▸%s %s\n' "$C_BLUE"   "$C_RESET" "$1"; }
ok()   { printf '%s✓%s %s\n' "$C_GREEN"  "$C_RESET" "$1"; }
info() { printf '%s  %s%s\n' "$C_DIM"    "$1" "$C_RESET"; }
warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$1" >&2; }
die()  { printf '%s✗%s %s\n' "$C_RED"    "$C_RESET" "$1" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

printf '\n%s╭─ dotfiles ─╮%s\n\n' "$C_BOLD$C_BLUE" "$C_RESET"

# ── git ──────────────────────────────────────────────────────────────────────
# install.sh lo instala también, pero aquí hace falta antes: sin git no hay clon.
if ! have git; then
  have sudo || die "Se necesita 'git' (y no hay 'sudo' para instalarlo)."
  step "Instalando git"
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git ca-certificates
fi

# ── Clonar o actualizar ──────────────────────────────────────────────────────
if [[ -d "$DEST/.git" ]]; then
  # Comprueba que el directorio es *este* repo y no otra cosa con el mismo nombre.
  current="$(git -C "$DEST" remote get-url origin 2>/dev/null || true)"
  if [[ -n "$current" && "${current%.git}" != "${REPO%.git}" ]]; then
    die "$DEST ya es un repo, pero de otro origen: $current"
  fi
  step "Actualizando $DEST"
  # --ff-only: si hay cambios locales divergentes, mejor fallar que pisarlos.
  git -C "$DEST" fetch --quiet origin "$BRANCH"
  if git -C "$DEST" merge --ff-only "origin/$BRANCH" 2>/dev/null; then
    ok "Actualizado a origin/$BRANCH"
  else
    warn "No se pudo hacer fast-forward (¿cambios locales?); se usa lo que hay."
  fi
elif [[ -e "$DEST" ]]; then
  die "$DEST existe y no es un repositorio git. Muévelo o usa DOTFILES_DIR=..."
else
  step "Clonando $REPO → $DEST"
  git clone --branch "$BRANCH" --depth 1 "$REPO" "$DEST"
  ok "Clonado"
fi

# ── Ejecutar el instalador ───────────────────────────────────────────────────
installer="$DEST/install.sh"
[[ -f "$installer" ]] || die "No se encontró $installer"
chmod +x "$installer" 2>/dev/null || true

step "Ejecutando install.sh ${*:-(sin opciones)}"
echo

# Bajo 'curl | bash' la stdin es la tubería, no el terminal. Reconectarla a
# /dev/tty permite que sudo (y cualquier prompt) siga funcionando.
# ('-r /dev/tty' no basta: el nodo existe aunque no haya terminal de control,
# así que hay que intentar abrirlo de verdad.)
if { : < /dev/tty; } 2>/dev/null; then
  exec "$installer" "$@" < /dev/tty
else
  info "Sin terminal interactivo: sudo debe estar preautorizado."
  exec "$installer" "$@"
fi
