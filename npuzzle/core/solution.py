from __future__ import annotations

import json
import math
from dataclasses import dataclass

from npuzzle.core.exceptions import InvalidSolutionFormat, SolverFailedError

RESET = "\033[0m"
BOLD = "\033[1m"
BLUE = "\033[34m"
ORANGE = "\033[38;5;208m"


def bold(text: str) -> str:
    return f"{BOLD}{text}{RESET}"


def blue(text: str) -> str:
    return f"{BLUE}{text}{RESET}"


def orange(text: str) -> str:
    return f"{ORANGE}{text}{RESET}"


@dataclass(frozen=True)
class State:
    tiles: list[int]
    g_cost: int
    h_cost: int
    f_cost: int


@dataclass(frozen=True)
class Statistics:
    states_selected: int
    max_states_in_memory: int
    solution_length: int


@dataclass
class Solution:
    states: list[State]
    statistics: Statistics

    @classmethod
    def from_json(cls, raw: str) -> "Solution":
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as e:
            raise InvalidSolutionFormat(f"Failed to parse JSON output: {e}")

        if not data.get("success"):
            raise SolverFailedError("solver reported failure")

        try:
            states = [
                State(
                    tiles=entry["tiles"],
                    g_cost=entry["g_cost"],
                    h_cost=entry["h_cost"],
                    f_cost=entry["f_cost"],
                )
                for entry in data["path"]
            ]

            stats = data["statistics"]
            statistics = Statistics(
                states_selected=stats["states_selected"],
                max_states_in_memory=stats["max_states_in_memory"],
                solution_length=stats["solution_length"],
            )

            return cls(states=states, statistics=statistics)
        except (KeyError, TypeError, IndexError) as e:
            raise InvalidSolutionFormat(f"Invalid solution format: {e}")

    def _grid_size(self) -> int:
        return int(math.sqrt(len(self.states[0].tiles)))

    def _diff_tiles(
        self, prev: list[int], curr: list[int]
    ) -> tuple[int | None, int | None]:
        prev_zero = prev.index(0)
        curr_zero = curr.index(0)

        tile_out = curr[prev_zero]
        tile_in = prev[curr_zero]

        return tile_out, tile_in

    def display(self) -> None:
        size = self._grid_size()

        for i, state in enumerate(self.states):
            prev_tiles = self.states[i - 1].tiles if i > 0 else None
            moved_out = moved_in = None

            if prev_tiles:
                moved_out, moved_in = self._diff_tiles(prev_tiles, state.tiles)

            print(f"\nStep {i}")
            print(f"g={state.g_cost}  h={state.h_cost}  f={state.f_cost}")
            self._print_grid(
                state.tiles,
                size,
                moved_out=moved_out,
                moved_in=moved_in,
            )

    def _print_grid(
        self,
        tiles: list[int],
        size: int,
        *,
        moved_out: int | None,
        moved_in: int | None,
    ) -> None:
        width = len(str(size * size))
        horizontal = "+" + "+".join(["-" * (width + 2)] * size) + "+"

        print(horizontal)
        for r in range(size):
            row = []
            for c in range(size):
                value = tiles[c + r * size]
                if value == 0:
                    cell = " " * width
                else:
                    text = f"{value:>{width}}"
                    text = bold(text)
                    if value == moved_in:
                        text = blue(text)
                    elif value == moved_out:
                        text = orange(text)
                    cell = text
                row.append(f" {cell} ")
            print("|" + "|".join(row) + "|")
            print(horizontal)

    def display_statistics(self) -> None:
        s = self.statistics
        print("\nStatistics")
        print(f"States selected      : {s.states_selected}")
        print(f"Max states in memory : {s.max_states_in_memory}")
        print(f"Solution length      : {s.solution_length}")
