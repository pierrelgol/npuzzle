import argparse
import subprocess
import sys
import time
from typing import List, Optional

from core.constants import ARGUMENTS_WHITELIST
from core.exceptions import SubprocessError
from core.signals import SignalHandler, register_signal_handler
from core.solution import Solution
from gen.exceptions import InvalidSize
from gen.puzzle import Puzzle


class Controller:
    def __init__(self, argv: List[str]):
        self.argv = argv
        self.parser = argparse.ArgumentParser(prog=argv[0])
        self.args = None
        self.puzzle = None
        self.solution = None
        self.signal_handler: SignalHandler = None
        self.solver_time: Optional[float] = None

    def register_signal_handler(self) -> None:
        """Register the SIGINT (Ctrl+C) signal handler."""
        self.signal_handler = register_signal_handler()

    def parse_arguments(self) -> argparse.Namespace:
        for arg_config in ARGUMENTS_WHITELIST:
            flags = arg_config["flags"]
            kwargs = {k: v for k, v in arg_config.items() if k != "flags"}
            self.parser.add_argument(*flags, **kwargs)

        self.args = self.parser.parse_args(self.argv[1:])
        return self.args

    def generate_puzzle(self, args: argparse.Namespace) -> Puzzle:
        is_solvable = not args.unsolvable

        try:
            puzzle = Puzzle(args.generate, solvable=is_solvable)
        except InvalidSize as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
        except Exception as e:
            print(f"Error generating puzzle: {e}", file=sys.stderr)
            sys.exit(1)

        puzzle.generate_snail()
        puzzle.shuffle(args.iteration)
        puzzle.ensure_solvability(is_solvable)

        return puzzle

    def solve_puzzle(self, puzzle: Puzzle, args: argparse.Namespace) -> str:
        try:
            start_time = time.time()

            process = subprocess.Popen(
                ["./zig-out/bin/npuzzle", str(args.generate), *map(str, puzzle.grid)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )

            if self.signal_handler:
                self.signal_handler.set_subprocess(process)

            stdout, stderr = process.communicate()

            end_time = time.time()
            self.solver_time = end_time - start_time

            if self.signal_handler:
                self.signal_handler.clear_subprocess()

            if process.returncode != 0:
                error_msg = stderr if stderr else "Unknown subprocess error"
                raise SubprocessError(
                    f"Solver failed with exit code {process.returncode}: {error_msg}"
                )

            return stdout
        except FileNotFoundError:
            raise SubprocessError("Solver binary not found at ./zig-out/bin/npuzzle")
        except Exception as e:
            raise SubprocessError(f"Failed to execute solver: {e}")

    def create_solution(self, json_output: str) -> Solution:
        try:
            solution = Solution.from_json(json_output)
            return solution
        except Exception as e:
            print(f"Error creating solution: {e}", file=sys.stderr)
            sys.exit(1)

    def display_solver_time(self) -> None:
        if self.solver_time is not None:
            seconds = int(self.solver_time)
            milliseconds = int((self.solver_time - seconds) * 1000)
            print(f"Solver execution time: {seconds}s{milliseconds}ms")

    def run(self) -> Solution:
        self.register_signal_handler()
        args = self.parse_arguments()
        self.puzzle = self.generate_puzzle(args)
        try:
            json_output = self.solve_puzzle(self.puzzle, args)
        except SubprocessError as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
        self.solution = self.create_solution(json_output)
        self.solution.display()
        self.solution.display_statistics()
        self.display_solver_time()
        return self.solution
