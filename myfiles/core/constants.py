from pathlib import Path

MAX_SIZE = 16
DEFAULT_TILE_VALUE = -1

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

ARGUMENTS_WHITELIST = [
    {
        "flags": ["--input"],
        "type": Path,
        "help": "name of the file",
        "default": None,
    },
    {
        "flags": ["-t", "--thread"],
        "type": int,
        "help": "thread number",
        "default": 1,
    },
    {
        "flags": ["-u", "--unsolvable"],
        "action": "store_true",
        "default": False,
        "help": "Forces generation of an unsolvable puzzle",
    },
    {
        "flags": ["--heuristic"],
        "choices": HEURISTIC_CHOICES,
        "default": HEURISTIC_CHOICES[0],
        "help": "heuristic function selection",
    },
    {
        "flags": ["-s", "--search"],
        "choices": SEARCH_MODES,
        "default": SEARCH_MODES[0],
        "help": "search algorithm selection",
    },
    {
        "flags": ["-g", "--generate"],
        "type": int,
        "help": "square grid size",
        "default": 3,
    },
    {
        "flags": ["-i", "--iteration"],
        "type": int,
        "help": "generator shuffle number",
        "default": 200,
    },
]
