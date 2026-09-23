#!/usr/bin/env bash
#
# verify.sh — Comprueba que el entorno quedó bien tras ejecutar install.sh.
#
# A diferencia del resumen de install.sh, que solo informa, esto afirma: sale
# con código != 0 si alguna comprobación falla, así que sirve en CI o para
# validar una prueba en contenedor sin leer el log entero.
#
#   ./verify.sh            # todas las comprobaciones
#   ./verify.sh --quiet    # solo los fallos y el recuento
#
set -Eeuo pipefail

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_DIR

# shellcheck source=lib/common.sh
source "$DOTFILES_DIR/lib/common.sh"

QUIET=false
[[ "${1:-}" == "--quiet" ]] && QUIET=true

# El entorno se configura para zsh: '~/.local/bin' entra en el PATH vía
# config/zshenv, que bash no lee. Sin esto, verify.sh (que corre en bash) no
# vería mise, herdr ni nada instalado ahí, y daría falsos negativos.
PATH="$HOME/.local/bin:$PATH"
export PATH

# Contadores. Ojo: nada de '((N++))' — con set -e, un post-incremento desde 0
# devuelve estado 1 y mataría el script.
N_PASS=0; N_FAIL=0; N_SKIP=0

pass() { [[ "$QUIET" == true ]] || ok "$1"; N_PASS=$((N_PASS + 1)); }
fail() { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; N_FAIL=$((N_FAIL + 1)); }
skip() { [[ "$QUIET" == true ]] || info "– $1"; N_SKIP=$((N_SKIP + 1)); }

section() { [[ "$QUIET" == true ]] || step "$1"; }

# check <descripción> <comando...>
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

# ── Symlinks ─────────────────────────────────────────────────────────────────
check_links() {
  section "Symlinks"
  local src dest
  while IFS='|' read -r src dest; do
    [[ -n "$src" ]] || continue
    local short="${dest/#$HOME/\~}"
    if [[ ! -e "$dest" && ! -L "$dest" ]]; then
      fail "$short no existe"
    elif [[ ! -L "$dest" ]]; then
      # Un fichero real donde debería haber un enlace: install.sh no llegó a
      # correr, o algo lo sobreescribió después.
      fail "$short es un fichero, no un enlace"
    elif [[ "$(readlink -f "$dest")" != "$(readlink -f "$DOTFILES_DIR/$src")" ]]; then
      fail "$short → $(readlink -f "$dest") (esperado $src)"
    else
      pass "$short → $src"
    fi
  done < <(dotfiles_links)
}

# ── Shell ────────────────────────────────────────────────────────────────────
check_shell() {
  section "Shell"

  if ! have zsh; then
    fail "zsh no está instalado"
    return
  fi
  pass "zsh instalado ($(zsh --version | awk '{print $2}'))"

  # La comprobación más valiosa: config/zshrc se enlaza pero nunca se ejecuta
  # durante la instalación. Un error de sintaxis ahí dejaría toda shell nueva
  # rota, con install.sh habiendo terminado en verde.
  # -s KILL: una shell *interactiva* ignora SIGTERM, así que un 'timeout' normal
  # no la mata y la verificación se colgaría para siempre. Verificado a mano con
  # un rc que hace 'read': con SIGTERM sobrevive, con SIGKILL no.
  # </dev/null: sin ello, un rc que lea entrada se comería la del propio script.
  local errs rc=0
  errs="$(timeout -s KILL 15 zsh -ic 'exit' 2>&1 >/dev/null </dev/null)" || rc=$?
  # Una shell interactiva sin terminal se queja del control de trabajos. Es
  # ruido del entorno (contenedor, CI), no un problema del zshrc: si no se
  # filtra, esta comprobación falla siempre donde no hay TTY.
  errs="$(printf '%s' "$errs" \
    | grep -vE 'cannot set terminal process group|no job control in this shell|^exit$' \
    || true)"
  if [[ "$rc" -eq 137 ]]; then
    fail "zsh no terminó en 15s (¿el zshrc espera entrada?)"
  elif [[ -z "$errs" ]]; then
    pass "zsh arranca sin errores"
  else
    fail "zsh arranca con errores: $(printf '%s' "$errs" | head -3 | tr '\n' ' ')"
  fi

  # ~/.local/bin lo pone zshenv; de él dependen mise, fresh y herdr.
  if timeout -s KILL 15 zsh -lic 'echo $PATH' 2>/dev/null </dev/null | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
    pass "~/.local/bin en el PATH"
  else
    fail "~/.local/bin no está en el PATH de una shell de login"
  fi

  # Oh My Zsh y su tema.
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    pass "Oh My Zsh instalado"
  else
    fail "falta ~/.oh-my-zsh"
  fi

  local login_shell
  login_shell="$(getent passwd "$USER" | cut -d: -f7)"
  if [[ "$login_shell" == *zsh ]]; then
    pass "shell de login: $login_shell"
  else
    # No es un fallo duro: --no-chsh es una opción legítima.
    skip "shell de login es $login_shell (¿--no-chsh?)"
  fi
}

# ── Runtimes de mise ─────────────────────────────────────────────────────────
# Las versiones esperadas se leen de config/mise.toml, no se repiten aquí.
toml_version() {
  awk -F'"' -v k="$1" '$0 ~ "^[ \t]*"k"[ \t]*=" { print $2; exit }' \
    "$DOTFILES_DIR/config/mise.toml"
}

check_runtimes() {
  section "Runtimes (mise)"

  if ! have mise; then
    fail "mise no está instalado"
    return
  fi
  pass "mise instalado ($(mise --version 2>/dev/null | awk '{print $1}'))"

  local tool expected actual
  for tool in ruby python node; do
    expected="$(toml_version "$tool")"
    if [[ -z "$expected" ]]; then
      skip "$tool no está declarado en mise.toml"
      continue
    fi
    actual="$(mise current "$tool" 2>/dev/null | awk '{print $1}')"
    if [[ -z "$actual" ]]; then
      fail "$tool no instalado (esperado $expected)"
    elif [[ "$actual" == "$expected"* ]]; then
      pass "$tool $actual"
    else
      fail "$tool $actual (esperado $expected)"
    fi
  done

  # uv/pnpm van a 'latest': basta con que respondan.
  local t
  for t in uv pnpm; do
    if mise exec -- "$t" --version >/dev/null 2>&1; then
      pass "$t disponible"
    else
      fail "$t no responde"
    fi
  done
}

# ── Herramientas del sistema ─────────────────────────────────────────────────
check_tools() {
  section "Herramientas"
  local t
  for t in git gh jq nvim sqlite3 rsync; do
    if have "$t"; then pass "$t"; else fail "$t no encontrado"; fi
  done

  # Opcionales: dependen de las banderas --skip-*.
  for t in psql herdr; do
    if have "$t"; then pass "$t"; else skip "$t ausente (¿--skip-*?)"; fi
  done

  # fresh lo administra mise, así que no está en el PATH salvo que mise esté
  # activado (cosa que hace zshrc, no bash). Hay que preguntárselo a mise.
  if have mise && mise exec -- fresh --version >/dev/null 2>&1; then
    pass "fresh"
  else
    skip "fresh ausente (¿--skip-*?)"
  fi
}

# ── Configuración de git ─────────────────────────────────────────────────────
check_git_config() {
  section "Git"
  have git || { fail "git no está instalado"; return; }

  # Que git lea de verdad el fichero enlazado, no solo que el enlace exista.
  local branch excludes
  branch="$(git config --get init.defaultBranch 2>/dev/null || true)"
  [[ "$branch" == "main" ]] \
    && pass "init.defaultBranch = main" \
    || fail "init.defaultBranch = '${branch:-<vacío>}' (¿se lee ~/.gitconfig?)"

  excludes="$(git config --get core.excludesfile 2>/dev/null || true)"
  [[ -n "$excludes" ]] \
    && pass "core.excludesfile = $excludes" \
    || fail "core.excludesfile sin definir"

  # La identidad vive fuera del repo a propósito; avisar, no fallar.
  if git config --get user.email >/dev/null 2>&1; then
    pass "user.email configurado"
  else
    skip "user.email sin configurar (ponlo en ~/.gitconfig.local)"
  fi
}

# ── Locale ───────────────────────────────────────────────────────────────────
check_locale() {
  section "Locale"
  if locale -a 2>/dev/null | grep -qi 'en_US.utf-\?8'; then
    pass "en_US.UTF-8 generado"
  else
    fail "en_US.UTF-8 no está generado (el tema saldrá con '?')"
  fi
}

main() {
  banner "Verificando el entorno"
  check_links
  check_shell
  check_runtimes
  check_tools
  check_git_config
  check_locale

  echo
  local total=$((N_PASS + N_FAIL))
  if [[ "$N_FAIL" -eq 0 ]]; then
    ok "$N_PASS/$total comprobaciones correctas${N_SKIP:+ ($N_SKIP omitidas)}"
    return 0
  fi
  printf '%s✗%s %s\n' "$C_RED" "$C_RESET" \
    "$N_FAIL fallo(s) de $total comprobaciones${N_SKIP:+ ($N_SKIP omitidas)}"
  return 1
}

main "$@"
