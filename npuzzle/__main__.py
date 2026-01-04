import sys
from typing import List

from npuzzle.cli.controller import Controller


def main(argc: int, argv: List[str]) -> int:
    controller = Controller(argv)
    try:
        solution = controller.run()
        if solution is None:
            return 1
        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(len(sys.argv), sys.argv))
