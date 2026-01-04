from pathlib import Path
from typing import List

from npuzzle.core.constants import MAX_SIZE
from npuzzle.io.exceptions import (
    InvalidDimensions,
    InvalidSizeError,
    MissingSizeError,
)


def parse_input_file(file_path: Path) -> List[int]:
    with open(file_path, "r", encoding="utf-8") as f:
        file_content = f.read()

    size = None
    tiles = []

    for line in file_content.splitlines():
        trimmed = line.strip()
        if not trimmed or trimmed.startswith("#"):
            continue

        if size is None:
            size = int(trimmed)
            if size < 3 or size > MAX_SIZE:
                raise InvalidSizeError
        else:
            for num_str in trimmed.split():
                tiles.append(int(num_str))

    if size is None:
        raise MissingSizeError

    if len(tiles) != size * size:
        raise InvalidDimensions

    return tiles
