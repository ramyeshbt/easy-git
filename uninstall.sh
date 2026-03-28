#!/usr/bin/env bash
# uninstall.sh — Remove easy-git (g) from PATH and shell config
# Mirrors the changes made by install.sh — safe to run multiple times

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SCRIPT_DIR}/bin"

echo ""
echo "=== Easy Git Tool — Uninstaller ==="
echo ""

# Detect the same shell config file install.sh would have used
detect_shell_config() {
  if [ -n "${BASH_VERSION:-}" ]; then
    if [ -f "${HOME}/.bashrc" ]; then
      echo "${HOME}/.bashrc"
    elif [ -f "${HOME}/.bash_profile" ]; then
      echo "${HOME}/.bash_profile"
    else
      echo "${HOME}/.bashrc"
    fi
  elif [ -n "${ZSH_VERSION:-}" ] || [ "${SHELL:-}" = "/bin/zsh" ] || [ "${SHELL:-}" = "/usr/bin/zsh" ]; then
    echo "${HOME}/.zshrc"
  else
    echo "${HOME}/.profile"
  fi
}

SHELL_CONFIG=$(detect_shell_config)

# ── Remove PATH entry from shell config ──────────────────────────────────────
if [ -f "$SHELL_CONFIG" ] && grep -qF "${BIN_DIR}" "$SHELL_CONFIG" 2>/dev/null; then
  # Back up the config file before editing
  cp "$SHELL_CONFIG" "${SHELL_CONFIG}.bak"
  echo "→  Backed up ${SHELL_CONFIG} to ${SHELL_CONFIG}.bak"

  # Use a temp file for portability (no sed -i on all platforms).
  # BUG FIX: grep -v returns exit code 1 when ALL lines match (nothing passes through),
  # which would kill the script under set -euo pipefail. Use || true to handle that
  # gracefully — an empty output file is valid (the config only had easy-git lines).
  # Also register a trap so the temp file is cleaned up on any failure.
  local_tmp=$(mktemp) && chmod 600 "$local_tmp"
  trap 'rm -f "$local_tmp"' EXIT

  # Remove the two lines added by install.sh: the comment and the export line.
  # || true prevents set -e from aborting when grep finds no surviving lines.
  {
    grep -v "# easy-git" "$SHELL_CONFIG" \
      | grep -v "export PATH=\"${BIN_DIR}" \
      || true
  } > "$local_tmp"

  # Preserve original file permissions on the config
  chmod --reference="$SHELL_CONFIG" "$local_tmp" 2>/dev/null || true

  mv "$local_tmp" "$SHELL_CONFIG"
  trap - EXIT  # clear trap after successful mv

  echo "✓  Removed easy-git PATH entry from ${SHELL_CONFIG}"
else
  echo "○  No entry found in ${SHELL_CONFIG} — nothing to remove"
fi

# ── Verify removal ────────────────────────────────────────────────────────────
if grep -qF "${BIN_DIR}" "$SHELL_CONFIG" 2>/dev/null; then
  echo "⚠  Warning: entry may still exist in ${SHELL_CONFIG} — please check manually."
  echo "   You can edit it directly and remove the lines containing: ${BIN_DIR}"
else
  echo "✓  ${SHELL_CONFIG} is clean"
fi

# ── Note about the project files ─────────────────────────────────────────────
echo ""
echo "○  Project files at '${SCRIPT_DIR}' were NOT deleted."
echo "   To fully remove the tool, delete that directory manually:"
echo ""
echo "   rm -rf \"${SCRIPT_DIR}\""
echo ""

echo "=== Uninstall complete ==="
echo ""
echo "Restart your terminal (or run: source ${SHELL_CONFIG}) to apply changes."
echo ""
