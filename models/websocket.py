"""WebSocket message models for real-time STT communication."""

from datetime import datetime
from typing import Literal, Union
from pydantic import BaseModel, Field, validator



class ClientConfig(BaseModel):
    """Client configuration for WebSocket STT session."""

    model: str = Field(..., min_length=1, description="Whisper model name")
    language: str = Field(
        default="en",
        min_length=2,
        max_length=5,
        description="Language code (ISO 639-1)",
    )
    sample_rate: int = Field(
        default=16000, ge=8000, le=48000, description="Audio sample rate in Hz"
    )
    channels: int = Field(default=1, ge=1, le=2, description="Number of audio channels")
    vad_enabled: bool = Field(
        default=True, description="Enable Voice Activity Detection"
    )
    vad_aggressiveness: int = Field(
        default=3, ge=0, le=3, description="VAD aggressiveness level (0-3)"
    )

    @validator("language")
    def validate_language(cls, v):
        """Validate language code format."""
        if v and not v.isalpha():
            raise ValueError("Language code must contain only letters")
        return v.lower()

    class Config:
        extra = "forbid"


class ServerTranscription(BaseModel):
    """Server-to-client transcription response."""

    text: str = Field(default="", description="Transcribed text")
    segments: list[dict] | None = Field(
        default=None, description="Text segments with timing"
    )
    is_partial: bool = Field(
        default=True, description="Whether this is partial transcription"
    )
    language: str | None = Field(default=None, description="Detected language code")
    confidence: float | None = Field(
        default=None, ge=0, le=1, description="Overall confidence score"
    )

    @property
    def is_final(self) -> bool:
        """Helper to check if transcription is final."""
        return not self.is_partial

    class Config:
        extra = "forbid"


class ServerStatus(BaseModel):
    """Server-to-client status message."""

    status: Literal["ready", "processing", "error", "closed"] = Field(
        ..., description="Server status"
    )
    message: str = Field(default="", description="Status message")
    timestamp: datetime = Field(
        default_factory=datetime.utcnow, description="Status timestamp"
    )
    progress: float | None = Field(
        default=None, ge=0, le=1, description="Progress indicator (0-1)"
    )

    class Config:
        extra = "forbid"
