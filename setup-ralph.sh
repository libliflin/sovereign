#!/bin/bash
# Setup Ralph for the Sovereign platform project
# Run this once after cloning both sovereign and ralph repos

set -e

SOVEREIGN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🏗️  Setting up Ralph for Sovereign Platform..."
echo ""

# Check prerequisites
command -v claude >/dev/null 2>&1 || { echo "❌ Claude Code CLI not found. Install: https://docs.claude.ai/en/docs/claude-code"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "❌ git not found."; exit 1; }

# Create scripts/ralph directory
mkdir -p "$SOVEREIGN_DIR/scripts/ralph"

# Check if ralph is already cloned
if [ ! -f "$SOVEREIGN_DIR/scripts/ralph/ralph.sh" ]; then
  echo "📥 Cloning snarktank/ralph into scripts/ralph..."
  git clone https://github.com/snarktank/ralph.git "$SOVEREIGN_DIR/scripts/ralph-src"
  cp "$SOVEREIGN_DIR/scripts/ralph-src/ralph.sh" "$SOVEREIGN_DIR/scripts/ralph/"
  cp "$SOVEREIGN_DIR/scripts/ralph-src/CLAUDE.md" "$SOVEREIGN_DIR/scripts/ralph/"
  rm -rf "$SOVEREIGN_DIR/scripts/ralph-src"
  chmod +x "$SOVEREIGN_DIR/scripts/ralph/ralph.sh"
  echo "✅ Ralph installed"
else
  echo "✅ Ralph already installed"
fi

# Copy prd.json and progress.txt into ralph directory (ralph.sh looks for them there)
cp "$SOVEREIGN_DIR/prd.json" "$SOVEREIGN_DIR/scripts/ralph/prd.json"
cp "$SOVEREIGN_DIR/progress.txt" "$SOVEREIGN_DIR/scripts/ralph/progress.txt"

# Copy sovereign CLAUDE.md to project root (Claude Code reads this automatically)
echo ""
echo "✅ Setup complete!"
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  HOW TO RUN"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Start the autonomous build loop:"
echo "  ./scripts/ralph/ralph.sh --tool claude 10"
echo ""
echo "  Ralph will run 10 iterations, then stop."
echo "  Re-run the same command to continue after hitting"
echo "  daily token limits. It picks up where it left off."
echo ""
echo "  Monitor progress:"
echo "  cat scripts/ralph/progress.txt"
echo ""
echo "  Check what's done:"
echo "  cat scripts/ralph/prd.json | grep -A2 '\"passes\"'"
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  STACK STATUS (25 stories total)"
echo "═══════════════════════════════════════════════════════"
echo ""
TOTAL=$(grep -c '"passes"' "$SOVEREIGN_DIR/scripts/ralph/prd.json" 2>/dev/null || echo 25)
DONE=$(grep -c '"passes": true' "$SOVEREIGN_DIR/scripts/ralph/prd.json" 2>/dev/null || echo 0)
echo "  Completed: $DONE / $TOTAL stories"
echo ""
