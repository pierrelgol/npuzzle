#!/usr/bin/env python3
import json
import subprocess

if __name__ == "__main__":
    puzzle = [7, 2, 4, 6, 3, 1, 5, 8, 0]

    result = subprocess.run(
        ["./zig-out/bin/npuzzle", "3", *map(str, puzzle)],
        capture_output=True,
        text=True,
    )

    output = result.stdout
    print(output)
