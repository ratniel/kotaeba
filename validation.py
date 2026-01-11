"""Startup validation utilities for Kotaeba STT Server."""

import sys
from pathlib import Path
from loguru import logger
from config import settings, validate_configuration, setup_logging


def validate_audio_dependencies() -> bool:
    """Validate audio processing dependencies."""
    try:
        import pyaudio
        import numpy as np
        import scipy.io.wavfile as wavfile

        # Test basic audio functionality
        pa = pyaudio.PyAudio()

        # Check if we can get default input device info
        try:
            default_input = pa.get_default_input_device_info()
            logger.debug(f"Default input device: {default_input['name']}")
        except Exception:
            logger.warning("No default audio input device found")

        pa.terminate()
        return True

    except ImportError as e:
        logger.error(f"Missing audio dependency: {e}")
        return False
    except Exception as e:
        logger.error(f"Audio dependency validation failed: {e}")
        return False


def run_startup_validation() -> bool:
    """Run essential startup validation."""
    logger.info("Running startup validation...")

    # Setup logging first
    setup_logging()

    try:
        # Validate configuration
        validate_configuration()

        # Validate essential dependencies
        validations = [
            ("Audio dependencies", validate_audio_dependencies),
        ]

        for name, validator in validations:
            if not validator():
                logger.error(f"{name} validation failed")
                return False
            logger.success(f"{name} validation passed")

        logger.success("All startup validations passed")
        return True

    except Exception as e:
        logger.error(f"Startup validation failed: {e}")
        return False


def require_validation():
    """Require successful validation or exit."""
    if not run_startup_validation():
        logger.error("Startup validation failed. Exiting.")
        sys.exit(1)
