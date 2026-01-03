import argparse
from pathlib import Path

# TODO : Liste de dicts avec help=["help"]
ARGUMENTS_WHITELIST = [
    ("-i", "--input", Path, "name of the file", None),
    ("-t", "--thread", int, "threads number", None),
    ("-s", "--solvable", bool, "whether the puzzle should be solvable or not", None),
    (None, "--heuristic", str, "", None),
]

HEURISTIC_CHOICES = [
    "manhattan",  # distance from final position (in tiles)
    "misplaced",  # number of tiles at the wrong position
    "linear",  # does not care
]

SEARCH_MODES = [
    "astar",  # optimized optimum
    "greedy",  # optimized fast
    "ucs",  # non optimized optimum (Dijkstra BFS)
]
