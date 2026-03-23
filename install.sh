#!/bin/bash
# Install Ralph into the current project directory
#
# Usage: curl -fsSL https://raw.githubusercontent.com/awfulwoman/ralph/main/install.sh | bash

set -e

BASE_URL="https://raw.githubusercontent.com/awfulwoman/ralph/main"

echo "Installing Ralph..."

mkdir -p scripts
curl -fsSL "$BASE_URL/scripts/ralph.sh" -o scripts/ralph.sh
curl -fsSL "$BASE_URL/scripts/ralph.md" -o scripts/ralph.md
chmod +x scripts/ralph.sh

echo "Installed scripts/ralph.sh and scripts/ralph.md to $(pwd)"
echo ""
echo "Next steps:"
echo "  1. Use /ralph to plan a feature and create GitHub Issues"
echo "  2. Run: ./scripts/ralph.sh --milestone <name>"
