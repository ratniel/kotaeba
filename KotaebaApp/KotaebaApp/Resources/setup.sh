#!/bin/bash
# Kotaeba Setup Script
# Installs uv, creates venv, and installs dependencies

set -e  # Exit on error

SUPPORT_DIR="$HOME/Library/Application Support/Kotaeba"
VENV_DIR="$SUPPORT_DIR/venv"

echo "🚀 Kotaeba Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create support directory
mkdir -p "$SUPPORT_DIR"
cd "$SUPPORT_DIR"

# Check if uv is installed
if ! command -v uv &> /dev/null; then
    echo "📦 Installing uv package manager..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    
    # Add to PATH for current session
    export PATH="$HOME/.local/bin:$PATH"
fi

# Verify uv installation
if ! command -v uv &> /dev/null; then
    echo "❌ Failed to install uv"
    exit 1
fi

echo "✅ uv package manager ready"

# Create virtual environment
echo "🐍 Creating Python virtual environment..."
uv venv "$VENV_DIR" --python 3.11

# Activate venv
source "$VENV_DIR/bin/activate"

# Install dependencies
echo "📚 Installing dependencies..."
echo "   This may take a few minutes..."

uv pip install mlx-audio mlx fastapi uvicorn websockets

echo ""
echo "✨ Setup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Dependencies installed:"
echo "  • mlx-audio (speech-to-text)"
echo "  • mlx (Apple Silicon ML)"
echo "  • fastapi (web framework)"
echo "  • uvicorn (server)"
echo "  • websockets (real-time communication)"
echo ""
echo "Kotaeba is ready to use! 🎤"
