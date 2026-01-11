"""Error response models for standardized error handling across the application."""

from datetime import datetime
from typing import Any, Dict
from pydantic import BaseModel, Field


class ErrorDetail(BaseModel):
    """Detailed error information."""

    code: str = Field(
        ..., min_length=1, description="Error code for programmatic handling"
    )
    message: str = Field(..., min_length=1, description="Human-readable error message")
    field: str | None = Field(
        default=None, description="Field that caused the error (if applicable)"
    )
    context: Dict[str, Any] | None = Field(
        default=None, description="Additional error context"
    )


class ErrorResponse(BaseModel):
    """Standardized error response format."""

    success: bool = Field(default=False, description="Operation success status")
    error: ErrorDetail = Field(..., description="Error details")
    timestamp: datetime = Field(
        default_factory=datetime.utcnow, description="Error timestamp"
    )
    request_id: str | None = Field(
        default=None, description="Request identifier for tracing"
    )

    class Config:
        json_encoders = {datetime: lambda v: v.isoformat()}


class ValidationError(ErrorResponse):
    """Validation-specific error response."""

    def __init__(self, message: str, field: str | None = None, **kwargs):
        error_detail = ErrorDetail(
            code="VALIDATION_ERROR", message=message, field=field
        )
        super().__init__(error=error_detail, **kwargs)


class ClientError(ErrorResponse):
    """Client-side error response."""

    def __init__(self, message: str, code: str = "CLIENT_ERROR", **kwargs):
        error_detail = ErrorDetail(code=code, message=message)
        super().__init__(error=error_detail, **kwargs)
