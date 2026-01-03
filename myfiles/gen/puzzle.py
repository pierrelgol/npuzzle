import random as rd
from typing import List

from gen.exceptions import InvalidSize


class Puzzle:
    grid: List[int] = []
    size: int = 0
    solvable: bool = False

    def __init__(self, size: int, solvable: bool = True) -> None:
        if not (2 < size < 16):
            raise InvalidSize("Size not good : 3 < size < 16")
        self.size = size
        self.grid = [-1 for _ in range(size * size)]
        self.solvable = solvable

    def __repr__(self) -> str:
        lines = []

        state = "solvable" if self.solvable else "unsolvable"
        lines.append(f"# This puzzle is {state}")
        lines.append(str(self.size))

        max_value = self.size * self.size
        field_width = len(str(max_value))

        for row in range(self.size):
            row_values = []
            for col in range(self.size):
                value = self.grid[col + row * self.size]
                row_values.append(str(value).rjust(field_width))
            lines.append(" ".join(row_values))

        return "\n".join(lines)

    def generate_snail(self) -> None:
        current_value: int = 1
        x: int = 0
        y: int = 0
        direction_x: int = 1
        direction_y: int = 0
        size: int = self.size
        max_tile_value: int = size * size

        while True:
            index = x + y * self.size
            self.grid[index] = current_value

            if current_value == 0:
                break

            current_value += 1
            if current_value == max_tile_value:
                current_value = 0

            next_x = x + direction_x
            next_y = y + direction_y

            is_out_of_bounds = (
                next_x < 0 or next_x >= size or next_y < 0 or next_y >= size
            )
            is_cell_filled: bool = False
            if not is_out_of_bounds:
                is_cell_filled = self.grid[next_x + next_y * size] != -1
            else:
                is_cell_filled = False
            should_turn = is_out_of_bounds or is_cell_filled

            if should_turn:
                direction_x, direction_y = -direction_y, direction_x

            x += direction_x
            y += direction_y

    def shuffle(self, iterations: int) -> None:
        for _ in range(iterations):

            idx = self.grid.index(0)
            

            possible_swaps = []
            if idx % self.size > 0:
                possible_swaps.append(idx - 1)
            if idx % self.size < self.size - 1:
                possible_swaps.append(idx + 1)
            if idx // self.size > 0:
                possible_swaps.append(idx - self.size)
            if idx // self.size < self.size - 1:
                possible_swaps.append(idx + self.size)
            
            swap_idx = rd.choice(possible_swaps)
            self.grid[idx] = self.grid[swap_idx]
            self.grid[swap_idx] = 0

    def ensure_solvability(self, should_be_solvable: bool) -> None:
        if should_be_solvable:
            return

        last_index = len(self.grid) - 1
        empty_at_start = self.grid[0] == 0 or self.grid[1] == 0
        if empty_at_start:
            self.grid[last_index], self.grid[last_index - 1] = (
                self.grid[last_index - 1],
                self.grid[last_index],
            )
        else:
            self.grid[0], self.grid[1] = self.grid[1], self.grid[0]
