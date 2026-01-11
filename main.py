"""WebSocket-based Streaming STT Client

Streams raw audio to the MLX Whisper server's real-time WebSocket endpoint.
Server handles Voice Activity Detection (VAD) and transcription triggering.
"""

import asyncio
import json
import signal
import sys
import wave
from datetime import datetime
from pathlib import Path
import pyaudio
import websockets
from loguru import logger
from pydantic import ValidationError

from config import settings, setup_logging

try:
    from stt.run_mlx_server import start_server
except ImportError:
    logger.error("Failed to import start_server function")
    sys.exit(1)
from models.websocket import (
    ClientConfig,
    ServerTranscription,
    ServerStatus,
)
from validation import require_validation


class WebSocketSTTClient:
    """Streams audio to MLX server via WebSocket."""

    def __init__(self):
        # Audio settings from config
        self.rate = settings.audio.rate
        self.chunk_size = settings.audio.chunk_size
        self.channels = settings.audio.channels
        self.format = settings.audio.format

        # PyAudio
        self.pa = pyaudio.PyAudio()
        self.stream = None

        # Control
        self.running = False
        self.server_process = None
        self.ws_uri = f"ws://{settings.STT_HOST}:{settings.STT_PORT}/v1/audio/transcriptions/realtime"
        
        # Audio recording
        self.audio_buffer = []
        self.transcript_buffer = []
        self.session_dir = None

    async def _stream_audio(self, websocket):
        """Task: Read audio from mic and send to WebSocket."""
        logger.info("Started audio streaming...")

        # Open mic stream (blocking, so we want to be careful or use a thread,
        # but for simplicity loop.run_in_executor is good or just simple read since we await send)
        # Note: PyAudio read is blocking. In async loop this blocks.
        # For true async we should run input in a thread, but for this simple client:
        # We'll use a small chunk size to yield control often.

        self.stream = self.pa.open(
            format=getattr(pyaudio, self.format),
            channels=self.channels,
            rate=self.rate,
            input=True,
            frames_per_buffer=self.chunk_size,
        )
        self.stream.start_stream()

        try:
            while self.running and self.stream.is_active():
                # Read raw PCM data
                # exception_on_overflow=False prevents crashes on high load
                data = self.stream.read(self.chunk_size, exception_on_overflow=False)

                # Send binary message
                await websocket.send(data)

                # Save to buffer for recording
                self.audio_buffer.append(data)

                # Small yield to let receive loop run
                await asyncio.sleep(0)

        except Exception as e:
            if self.running:  # Only log error if not shutting down
                logger.error(f"Audio stream error: {e}")
        finally:
            self._stop_audio_stream()
            self._save_recording()

    def _stop_audio_stream(self):
        """Clean up PyAudio stream."""
        if self.stream:
            self.stream.stop_stream()
            self.stream.close()
            self.stream = None

    def _save_recording(self):
        """Save captured audio buffer to a WAV file."""
        if not self.audio_buffer or not self.session_dir:
            return

        wav_path = self.session_dir / "session.wav"
        logger.info(f"Saving session recording to {wav_path}...")

        try:
            with wave.open(str(wav_path), "wb") as wf:
                wf.setnchannels(self.channels)
                wf.setsampwidth(self.pa.get_sample_size(getattr(pyaudio, self.format)))
                wf.setframerate(self.rate)
                wf.writeframes(b"".join(self.audio_buffer))
            
            size_mb = wav_path.stat().st_size / (1024 * 1024)
            logger.success(f"Saved recording ({size_mb:.2f} MB)")
        except Exception as e:
            logger.error(f"Failed to save recording: {e}")
        finally:
            self.audio_buffer = []

    def _save_transcript(self):
        """Save captured transcript buffer to a text file."""
        if not self.transcript_buffer or not self.session_dir:
            return

        transcript_path = self.session_dir / "transcript.txt"
        logger.info(f"Saving transcript to {transcript_path}...")

        try:
            with open(transcript_path, "w") as f:
                f.write("\n".join(self.transcript_buffer))
            logger.success(f"Saved transcript ({len(self.transcript_buffer)} entries)")
        except Exception as e:
            logger.error(f"Failed to save transcript: {e}")
        finally:
            self.transcript_buffer = []

    async def _receive_transcription(self, websocket):
        """Task: Listen for transcription results."""
        try:
            while self.running:
                message = await websocket.recv()

                # Validate WebSocket message using Pydantic models
                try:
                    # Try to parse as transcription first
                    server_message = ServerTranscription.model_validate_json(message)
                except ValidationError:
                    try:
                        # Try to parse as status
                        server_message = ServerStatus.model_validate_json(message)
                    except ValidationError:
                        logger.error(f"Invalid WebSocket message format")
                        logger.debug(f"Raw message: {message}")
                        continue

                # Handle different message types
                if isinstance(server_message, ServerTranscription):
                    text = server_message.text.strip()
                    if text:
                        self.transcript_buffer.append(text)
                        print(f"\n🗣️ {text}\n")
                        if server_message.language:
                            logger.debug(
                                f"Language detected: {server_message.language}"
                            )
                        if server_message.confidence:
                            logger.debug(f"Confidence: {server_message.confidence:.2f}")

                elif isinstance(server_message, ServerStatus):
                    logger.info(
                        f"Server status: {server_message.status} - {server_message.message}"
                    )
                    if server_message.progress is not None:
                        logger.debug(f"Progress: {server_message.progress:.1%}")

        except websockets.exceptions.ConnectionClosed:
            logger.warning("WebSocket connection closed")
            self.running = False
        except Exception as e:
            if self.running:
                logger.error(f"Receive error: {e}")

    async def run(self):
        """Main run loop."""
        require_validation()  # Run startup validation

        # Start server as subprocess
        logger.info("Starting MLX Whisper server...")
        self.server_process = start_server(log_output=True)

        # Give server time to bind port
        await asyncio.sleep(3)

        self.running = True

        # Create session directory
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.session_dir = Path(settings.RECORDINGS_DIR) / f"session_{timestamp}"
        self.session_dir.mkdir(parents=True, exist_ok=True)
        logger.info(f"Session directory: {self.session_dir}")

        # Connect to WebSocket
        logger.info(f"Connecting to {self.ws_uri}...")
        try:
            async with websockets.connect(self.ws_uri) as websocket:
                logger.success("Connected to server")
                print("\n🎤 Listening... (Press Ctrl+C to stop)\n")

                # Send configuration
                config = ClientConfig(
                    model=settings.STT_MODEL,
                    language=settings.LANGUAGE,
                    sample_rate=self.rate,
                    channels=self.channels,
                    vad_enabled=True,
                    vad_aggressiveness=settings.vad.vad_mode,
                )
                await websocket.send(config.model_dump_json())

                # Create concurrent tasks for send/receive
                # We use gather so if one fails/cancels, we exit
                send_task = asyncio.create_task(self._stream_audio(websocket))
                recv_task = asyncio.create_task(self._receive_transcription(websocket))

                # Handle Ctrl+C
                loop = asyncio.get_running_loop()
                stop_future = loop.create_future()

                def signal_handler():
                    self.running = False
                    stop_future.set_result(True)

                for sig in (signal.SIGINT, signal.SIGTERM):
                    loop.add_signal_handler(sig, signal_handler)

                # Wait for stop signal or connection closed
                await stop_future

                # Cleanup
                logger.info("Stopping client...")
                send_task.cancel()
                recv_task.cancel()
                
                # Ensure transcript is saved on stop
                self._save_transcript()

        except Exception as e:
            logger.error(f"Connection failed: {e}")
        finally:
            self._stop_audio_stream()
            self.pa.terminate()
            if self.server_process:
                logger.info("Terminating server...")
                self.server_process.terminate()


def main():
    try:
        # Signal handling for main thread
        client = WebSocketSTTClient()
        asyncio.run(client.run())
    except KeyboardInterrupt:
        pass  # Handled in run()


if __name__ == "__main__":
    main()
