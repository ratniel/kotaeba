import sys
import os
from pathlib import Path
from loguru import logger
from pydantic import BaseModel, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# MARK: Audio config
class AudioConfig(BaseModel):
    """Audio processing configuration."""

    rate: int = Field(
        default=16000, ge=8000, le=48000, description="Sample rate for audio processing"
    )
    channels: int = Field(default=1, ge=1, le=2, description="Number of audio channels")
    chunk_size: int = Field(
        default=1024, ge=256, le=8192, description="Audio chunk size for streaming"
    )
    format: str = Field(default="paInt16", description="PyAudio format constant")

    @field_validator("format")
    @classmethod
    def validate_format(cls, v: str) -> str:
        """Validate PyAudio format."""
        valid_formats = {"paInt16", "paInt24", "paInt32", "paFloat32", "paUInt8"}
        if v not in valid_formats:
            raise ValueError(f"Invalid audio format. Must be one of: {valid_formats}")
        return v

    @field_validator("chunk_size")
    @classmethod
    def validate_chunk_size(cls, v: int) -> int:
        """Validate chunk size is power of 2."""
        if v & (v - 1) != 0:  # Check if power of 2
            raise ValueError("Chunk size must be a power of 2")
        return v

# MARK: VAD config
class VADConfig(BaseModel):
    """Voice Activity Detection configuration."""

    frame_duration_ms: int = Field(
        default=30, description="VAD frame size (10, 20, or 30ms)"
    )
    vad_mode: int = Field(
        default=3, ge=0, le=3, description="Aggressiveness (0=lenient, 3=strict)"
    )
    silence_limit_ms: int = Field(
        default=1000, ge=100, le=5000, description="Pause duration to trigger send"
    )
    pre_speech_ms: int = Field(
        default=500, ge=0, le=2000, description="Pre-speech buffer for context"
    )

    @field_validator("frame_duration_ms")
    @classmethod
    def validate_frame_duration(cls, v: int) -> int:
        """Validate VAD frame duration."""
        valid_durations = {10, 20, 30}
        if v not in valid_durations:
            raise ValueError(f"Frame duration must be one of: {valid_durations}ms")
        return v

# MARK: Settings
class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    # Server Configuration
    STT_MODEL: str = Field(
        default="mlx-community/Qwen3-ASR-0.6B-8bit", description="Whisper model to use"
    )
    STT_HOST: str = Field(default="0.0.0.0", description="Server host")
    STT_PORT: int = Field(default=8000, ge=1, le=65535, description="Server port")

    # Audio Configuration (nested)
    audio: AudioConfig = Field(
        default_factory=AudioConfig, description="Audio processing settings"
    )

    # VAD Configuration (nested)
    vad: VADConfig = Field(
        default_factory=VADConfig, description="Voice Activity Detection settings"
    )

    # Additional Configuration
    LANGUAGE: str = Field(
        default="en", min_length=2, max_length=5, description="Default language code"
    )

    # Logging Configuration
    LOG_FILE: str = Field(default="logs/kotaeba.log", description="Log file path")
    LOG_ROTATION: str = Field(default="10 MB", description="Log rotation size")
    LOG_COMPRESSION: str = Field(default="zip", description="Log compression format")

    # Recording Configuration
    RECORDINGS_DIR: str = Field(default="recordings", description="Recordings directory")


def validate_configuration() -> Settings:
    """Validate configuration on startup and return settings."""
    try:
        # Validate nested configurations
        settings.model_validate(settings.model_dump())

        # Additional custom validations
        settings.audio.model_validate(settings.audio.model_dump())
        settings.vad.model_validate(settings.vad.model_dump())

        # Validate port availability (basic check)
        if not (1 <= settings.STT_PORT <= 65535):
            raise ValueError(f"Invalid port: {settings.STT_PORT}. Must be 1-65535")

        # Validate model name
        if not settings.STT_MODEL or len(settings.STT_MODEL.strip()) == 0:
            raise ValueError("STT_MODEL cannot be empty")

        # Validate log directory can be created
        log_path = Path(settings.LOG_FILE)
        try:
            log_path.parent.mkdir(parents=True, exist_ok=True)
        except PermissionError:
            raise ValueError(f"Cannot create log directory: {log_path.parent}")

        # Validate recordings directory can be created
        recordings_path = Path(settings.RECORDINGS_DIR)
        try:
            recordings_path.mkdir(parents=True, exist_ok=True)
        except PermissionError:
            raise ValueError(f"Cannot create recordings directory: {recordings_path}")

        logger.success("Configuration validation passed")
        return settings

    except Exception as e:
        logger.error(f"Configuration validation failed: {e}")
        raise


settings = Settings()


def setup_logging():
    log_path = Path(settings.LOG_FILE)
    log_path.parent.mkdir(parents=True, exist_ok=True)

    logger.remove()

    # Console handler
    logger.add(
        sys.stdout,
        format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level: <8}</level> | <cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> - <level>{message}</level>",
        colorize=True,
    )

    # File handler
    logger.add(
        settings.LOG_FILE,
        rotation=settings.LOG_ROTATION,
        compression=settings.LOG_COMPRESSION,
        format="{time:YYYY-MM-DD HH:mm:ss} | {level: <8} | {name}:{function}:{line} - {message}",
        level="DEBUG",
    )
    return settings
