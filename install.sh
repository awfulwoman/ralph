#!/bin/bash
# Install Ralph into the current project directory
#
# Usage: curl -fsSL https://raw.githubusercontent.com/awfulwoman/ralph/main/install.sh | bash

set -e

REPO="awfulwoman/ralph"

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

mkdir -p scripts
curl -fsSL "$BASE_URL/scripts/ralph.sh" -o scripts/ralph.sh
curl -fsSL "$BASE_URL/scripts/ralph.md" -o scripts/ralph.md
chmod +x scripts/ralph.sh

INSTALLED_VERSION=$(grep '^RALPH_VERSION=' scripts/ralph.sh | cut -d'"' -f2)
echo "Installed Ralph v${INSTALLED_VERSION} to $(pwd)"
echo ""
echo "Next steps:"
echo "  1. Use /ralph-github to plan a feature and create GitHub Issues"
echo "  2. Run: ./scripts/ralph.sh --milestone <name>"
