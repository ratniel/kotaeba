"""MLX Audio STT Server Wrapper

Provides functions to start and manage of MLX Whisper server as a subprocess.
"""

import subprocess
import sys
import signal
import threading
from loguru import logger
from config import settings, setup_logging


def start_server(log_output: bool = True) -> subprocess.Popen:
    """
    Start the MLX audio server as a background subprocess.

    Args:
        log_output: If True, spawn a thread to log server output.

    Returns:
        The subprocess.Popen handle for the server process.
    """
    command = [
        "mlx_audio.server",
        "--host",
        settings.STT_HOST,
        "--port",
        str(settings.STT_PORT),
        # "--model",
        # settings.STT_MODEL,
    ]

    logger.info(f"Starting MLX server: {' '.join(command)}")

    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    if log_output:

        def log_server_output():
            if process.stdout:
                for line in process.stdout:
                    logger.opt(raw=True).info(line)

        log_thread = threading.Thread(target=log_server_output, daemon=True)
        log_thread.start()

    return process


if __name__ == "__main__":
    setup_logging()
    command = [
        "mlx_audio.server",
        "--host",
        settings.STT_HOST,
        "--port",
        str(settings.STT_PORT),
        "--model",
        settings.STT_MODEL,
    ]
    logger.info(f"Starting MLX server: {' '.join(command)}")

    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    for line in process.stdout:
        logger.opt(raw=True).info(line)

    process.wait()
    if process.returncode != 0:
        logger.error(f"Process finished with return code {process.returncode}")
        sys.exit(process.returncode)
    else:
        logger.info("Process finished successfully")
