import sys
from typing import List

from cli.controller import Controller


def main(argc: int, argv: List[str]) -> int:
    controller = Controller(argv)
    try:
        solution = controller.run()
        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(len(sys.argv), sys.argv))
