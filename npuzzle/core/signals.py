import signal
import sys
from subprocess import Popen
from typing import Optional


class SignalHandler:
    def __init__(self):
        self.subprocess: Optional[Popen] = None
        self.interrupted = False

    def set_subprocess(self, process: Popen) -> None:
        self.subprocess = process

    def clear_subprocess(self) -> None:
        self.subprocess = None

    def handle_interrupt(self, signum: int, frame) -> None:
        self.interrupted = True
        print("\n\nInterrupted by user (Ctrl+C)", file=sys.stderr)

        if self.subprocess and self.subprocess.poll() is None:
            print("Terminating solver subprocess...", file=sys.stderr)
            try:
                self.subprocess.terminate()
                self.subprocess.wait(timeout=2)
            except Exception:
                print("Force killing solver subprocess...", file=sys.stderr)
                self.subprocess.kill()

        sys.exit(130)


signal_handler = SignalHandler()


def register_signal_handler() -> SignalHandler:
    signal.signal(signal.SIGINT, signal_handler.handle_interrupt)
    return signal_handler

