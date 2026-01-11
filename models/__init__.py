"""Pydantic models for Kotaeba STT Server.

This package provides validated data models for:
- WebSocket message communication
- Audio processing configuration
- Standardized error responses
"""

from .websocket import ClientConfig, ServerTranscription, ServerStatus
from .errors import (
    ErrorDetail,
    ErrorResponse,
    ValidationError,
    ValidationError as ValidationErrorResponse,
)

__all__ = [
    # WebSocket models
    "ClientConfig",
    "ServerTranscription",
    "ServerStatus",
    # Error models
    "ErrorDetail",
    "ErrorResponse",
    "ValidationError",
    "ValidationErrorResponse",
]
