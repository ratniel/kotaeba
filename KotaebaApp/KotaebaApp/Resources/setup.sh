#!/bin/bash
# Kotaeba Setup Script
# Syncs the locked fallback runtime used when no bundled app runtime is present.

set -e  # Exit on error

SUPPORT_DIR="$HOME/Library/Application Support/Kotaeba"
VENV_DIR="$SUPPORT_DIR/.venv"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_PROJECT_DIR="$SCRIPT_DIR/PythonRuntime"

if [[ ! -f "$RUNTIME_PROJECT_DIR/pyproject.toml" || ! -f "$RUNTIME_PROJECT_DIR/uv.lock" ]]; then
    if [[ -f "$SCRIPT_DIR/pyproject.toml" && -f "$SCRIPT_DIR/uv.lock" ]]; then
        RUNTIME_PROJECT_DIR="$SCRIPT_DIR"
    fi
fi

echo "🚀 Kotaeba Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create support directory
mkdir -p "$SUPPORT_DIR"
cd "$SUPPORT_DIR"

# Check if uv is installed
if ! command -v uv &> /dev/null; then
    echo "📦 Installing uv package manager..."
    if command -v brew &> /dev/null; then
        brew install uv
    else
        echo "❌ uv is not installed and Homebrew is unavailable."
        echo "   Please install uv manually (e.g. via Homebrew) and re-run setup."
        exit 1
    fi
fi

# Verify uv installation
if ! command -v uv &> /dev/null; then
    echo "❌ Failed to install uv"
    exit 1
fi

echo "✅ uv package manager ready"

if [[ ! -f "$RUNTIME_PROJECT_DIR/pyproject.toml" || ! -f "$RUNTIME_PROJECT_DIR/uv.lock" ]]; then
    echo "❌ Locked runtime project not found at: $RUNTIME_PROJECT_DIR"
    exit 1
fi

echo "🐍 Syncing locked Python runtime..."
echo "   This may take a few minutes..."

mkdir -p "$VENV_DIR"

export UV_PROJECT_ENVIRONMENT="$VENV_DIR"

uv sync \
    --project "$RUNTIME_PROJECT_DIR" \
    --locked \
    --no-dev \
    --no-install-project \
    --python 3.11

echo ""
echo "✨ Setup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Locked runtime synced to:"
echo "  • $VENV_DIR"
echo ""
echo "Kotaeba is ready to use! 🎤"
