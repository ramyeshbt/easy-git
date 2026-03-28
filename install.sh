#!/usr/bin/env bash
# install.sh — Install easy-git (g) by adding bin/ to PATH
# Idempotent: safe to run multiple times

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SCRIPT_DIR}/bin"

# Make bin/g executable
chmod +x "${BIN_DIR}/g"

echo ""
echo "=== Easy Git Tool — Installer ==="
echo ""

# Detect shell config file
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
EXPORT_LINE="export PATH=\"${BIN_DIR}:\$PATH\"  # easy-git"

# Check if already installed
if echo "$PATH" | grep -q "${BIN_DIR}"; then
  echo "✓  Already installed (${BIN_DIR} is in PATH)"
else
  # Check if line already in config
  if grep -qF "${BIN_DIR}" "${SHELL_CONFIG}" 2>/dev/null; then
    echo "✓  PATH entry already exists in ${SHELL_CONFIG}"
  else
    echo "→  Adding to ${SHELL_CONFIG}:"
    echo "   ${EXPORT_LINE}"
    echo "" >> "${SHELL_CONFIG}"
    echo "# easy-git" >> "${SHELL_CONFIG}"
    echo "${EXPORT_LINE}" >> "${SHELL_CONFIG}"
    echo ""
    echo "✓  Done! Restart your terminal or run:"
    echo ""
    echo "   source ${SHELL_CONFIG}"
    echo ""
  fi
fi

# Verify g is runnable
if command -v g &>/dev/null; then
  echo "✓  'g' is available ($(g --version 2>/dev/null || echo 'installed'))"
else
  # Not in PATH yet — run directly
  echo "✓  Run the following to start using 'g':"
  echo ""
  echo "   source ${SHELL_CONFIG}"
  echo "   g --help"
fi

echo ""
echo "=== Optional dependencies ==="
echo ""
for dep in fzf gh delta; do
  if command -v "$dep" &>/dev/null; then
    echo "✓  $dep — installed"
  else
    echo "○  $dep — not installed (optional)"
  fi
done
echo ""
echo "  fzf:   brew install fzf      (fuzzy branch/stash selection)"
echo "  gh:    brew install gh       (PR creation from CLI)"
echo "  delta: brew install git-delta (prettier diffs)"
echo ""
echo "=== Installation complete ==="
echo ""
