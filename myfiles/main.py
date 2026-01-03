import argparse
import subprocess
import sys
from pathlib import Path
from typing import List

from cli.constants import HEURISTIC_CHOICES, SEARCH_MODES
from gen.exceptions import InvalidSize
from gen.puzzle import Puzzle


def main(argc: int, argv: List[str]) -> int:
    parser = argparse.ArgumentParser(prog=argv[0])
    parser.add_argument("--input", type=Path, help="name of the file", default=None)
    parser.add_argument("-t", "--thread", type=int, help="thread number", default=1)
    parser.add_argument(
        "-u",
        "--unsolvable",
        action="store_true",
        default=False,
        help="Forces generation of an unsolvable puzzle",
    )
    parser.add_argument(
        "--heuristic",
        choices=HEURISTIC_CHOICES,
        default=HEURISTIC_CHOICES[0],
        help="heuristic function selection",
    )
    parser.add_argument(
        "-s",
        "--search",
        choices=SEARCH_MODES,
        default=SEARCH_MODES[0],
        help="search algorithm selection",
    )
    parser.add_argument(
        "-g", "--generate", type=int, help="square grid size", default=3
    )
    parser.add_argument(
        "-i", "--iteration", type=int, help="generator shuffle number", default=200
    )

    args = parser.parse_args(argv[1:])

    is_solvable = True if not args.unsolvable else False

    try:
        puzzle = Puzzle(args.generate, solvable=is_solvable)
    except (InvalidSize, Exception) as e:
        print(f"Error: {e}", file=sys.stderr)
        exit(1)

    puzzle.generate_snail()
    puzzle.shuffle(args.iteration)
    puzzle.ensure_solvability(is_solvable)

    print(puzzle)
    print(puzzle.grid)
    try:
        result = subprocess.run(
            ["./zig-out/bin/npuzzle", "3", *map(str, puzzle.grid)],
            stderr=True,
            text=True,
        )
    except Exception as e:
        print(f"Error Pierre : {e}")
        exit(1)
    output = result.stdout
    print(output)
    return 0


if __name__ == "__main__":
    main(len(sys.argv), sys.argv)
