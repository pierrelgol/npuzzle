import argparse
import sys
from pathlib import Path
from random import choices
from typing import List

from cli.constants import HEURISTIC_CHOICES, SEARCH_MODES
from gen.exceptions import InvalidSize
from gen.puzzle import Puzzle


def main(argc: int, argv: List[str]) -> int:
    parser = argparse.ArgumentParser(prog=argv[0])
    parser.add_argument("--input", type=Path, help="name of the file", default=None)
    parser.add_argument("-t", "--thread", type=int, help="thread number", default=1)
    parser.add_argument(
        "-s",
        "--solvable",
        type=bool,
        help="whether the puzzle should be solvable",
        default=True,
    )
    parser.add_argument(
        "--heuristic",
        choices=HEURISTIC_CHOICES,
        default=HEURISTIC_CHOICES[0],
        help="heuristic function selection",
    )
    parser.add_argument(
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
    print(f"{args.input}")

    is_solvable = bool(args.solvable)
    try:
        puzzle = Puzzle(args.generate)
    except (InvalidSize, Exception) as e:
        print(f"Error: {e}", file=sys.stderr)
        exit(1)

    puzzle.generate_snail()
    puzzle.shuffle(args.iteration)
    puzzle.ensure_solvability(is_solvable)

    print(puzzle)
    return 0


if __name__ == "__main__":
    main(len(sys.argv), sys.argv)
