#!/usr/bin/env python3
import subprocess

if __name__ == "__main__":
    puzzle = [1, 2, 3, 8, 4, 0, 7, 6, 5]

    result = subprocess.run(
        ["./zig-out/bin/npuzzle", "3", *map(str, puzzle)],
        capture_output=True,
        text=True,
    )

    print(result.stdout)
