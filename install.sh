#!/bin/bash
# Install Ralph into the current project directory
#
# Usage: curl -fsSL https://raw.githubusercontent.com/awfulwoman/ralph/main/install.sh | bash
#        curl -fsSL ... | bash -s -- --dir path/to/project

set -e

REPO="awfulwoman/ralph"
INSTALL_DIR="./scripts"

while [[ $# -gt 0 ]]; do
  case $1 in
    --dir)   INSTALL_DIR="$2"; shift 2 ;;
    --dir=*) INSTALL_DIR="${1#*=}"; shift ;;
    *) shift ;;
  esac
done

echo "Installing Ralph..."

# Fetch latest release tag
LATEST=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep '"tag_name"' | head -1 | sed 's/.*"tag_name":[[:space:]]*"\(.*\)".*/\1/')

if [[ -z "$LATEST" ]]; then
  echo "Error: Could not determine latest release from GitHub."
  exit 1
fi

echo "Latest release: $LATEST"

BASE_URL="https://raw.githubusercontent.com/$REPO/$LATEST"

mkdir -p "$INSTALL_DIR"
curl -fsSL "$BASE_URL/scripts/ralph.sh" -o "$INSTALL_DIR/ralph.sh"
curl -fsSL "$BASE_URL/scripts/ralph.md" -o "$INSTALL_DIR/ralph.md"
chmod +x "$INSTALL_DIR/ralph.sh"

echo "Installed Ralph ${LATEST} to $INSTALL_DIR"
echo ""
echo "Next steps:"
echo "  1. Use /ralph-github to plan a feature and create GitHub Issues"
echo "  2. Run: $INSTALL_DIR/ralph.sh --milestone <name>"
