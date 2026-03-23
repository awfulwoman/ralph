#!/bin/bash
# Install Ralph into the current project directory
#
# Usage: curl -fsSL https://raw.githubusercontent.com/awfulwoman/ralph/main/install.sh | bash

set -e

BASE_URL="https://raw.githubusercontent.com/awfulwoman/ralph/main"

echo "Installing Ralph..."

curl -fsSL "$BASE_URL/ralph.sh" -o ralph.sh
curl -fsSL "$BASE_URL/ralph.md" -o ralph.md
chmod +x ralph.sh

echo "Installed ralph.sh and ralph.md to $(pwd)"
echo ""
echo "Next steps:"
echo "  1. Use /ralph to plan a feature and create GitHub Issues"
echo "  2. Run: ./ralph.sh --milestone <name>"
