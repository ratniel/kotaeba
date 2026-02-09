#!/usr/bin/env python3
"""
Pre-download the default Parakeet model for Kotaeba.

This script ensures the default model is cached locally before first use,
providing a better user experience.
"""

import sys
from pathlib import Path

try:
    from mlx_audio.utils import load_model
except ImportError:
    print("Error: mlx_audio not installed. Please run: uv pip install mlx-audio")
    sys.exit(1)


def download_default_model():
    """Download the default Parakeet model."""
    default_model = "mlx-community/parakeet-tdt-0.6b-v2"

    print(f"Downloading default model: {default_model}")
    print("This may take a few minutes on first run...")
    print()

    try:
        # Loading the model will automatically download and cache it
        model_data = load_model(default_model)
        print()
        print(f"✓ Successfully downloaded and cached: {default_model}")
        print(f"  Model type: {model_data.get('task', 'unknown')}")
        return True
    except Exception as e:
        print()
        print(f"✗ Failed to download model: {e}")
        return False


if __name__ == "__main__":
    print("=" * 60)
    print("Kotaeba - Default Model Setup")
    print("=" * 60)
    print()

    success = download_default_model()

    print()
    print("=" * 60)

    if success:
        print("Setup complete! You can now use Kotaeba.")
        sys.exit(0)
    else:
        print("Setup failed. Please check the error above.")
        sys.exit(1)
