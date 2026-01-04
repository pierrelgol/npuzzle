import math
import sys
import termios
import tty
from typing import Optional

from npuzzle.core.solution import Solution


RESET = "\033[0m"
BOLD = "\033[1m"
GREEN = "\033[32m"
RED = "\033[31m"
ORANGE = "\033[38;5;208m"


class InteractiveViewer:
    def __init__(self, solution: Solution):
        self.solution = solution
        self.current_step = 0
        self.total_steps = len(solution.states) - 1
        self.goal_state = self._generate_goal_state()

    def _generate_goal_state(self) -> list[int]:
        tiles = self.solution.states[0].tiles
        size = int(math.sqrt(len(tiles)))
        goal = [-1] * (size * size)
        
        current_value = 1
        x, y = 0, 0
        direction_x, direction_y = 1, 0
        
        while True:
            index = x + y * size
            goal[index] = current_value
            
            if current_value == 0:
                break
            
            current_value += 1
            if current_value == size * size:
                current_value = 0
            
            next_x = x + direction_x
            next_y = y + direction_y
            
            is_out_of_bounds = (
                next_x < 0 or next_x >= size or next_y < 0 or next_y >= size
            )
            is_cell_filled = False
            if not is_out_of_bounds:
                is_cell_filled = goal[next_x + next_y * size] != -1
            
            should_turn = is_out_of_bounds or is_cell_filled
            
            if should_turn:
                direction_x, direction_y = -direction_y, direction_x
            
            x += direction_x
            y += direction_y
        
        return goal

    def clear_screen(self) -> None:
        """Clear the terminal screen."""
        sys.stdout.write("\033[2J\033[H")
        sys.stdout.flush()

    def get_terminal_size(self) -> tuple[int, int]:
        """Get terminal width and height."""
        import shutil
        size = shutil.get_terminal_size(fallback=(80, 24))
        return size.columns, size.lines

    def center_text(self, text: str, width: int) -> str:
        """Center text within given width."""
        lines = text.split('\n')
        centered_lines = []
        for line in lines:

            import re
            visible_length = len(re.sub(r'\033\[[0-9;]*m', '', line))
            padding = max(0, (width - visible_length) // 2)
            centered_lines.append(' ' * padding + line)
        return '\n'.join(centered_lines)

    def render_state(self) -> None:
        self.clear_screen()
        
        width, height = self.get_terminal_size()
        state = self.solution.states[self.current_step]
        

        output_lines = []
        

        title = f"═══ N-Puzzle Solution Viewer ═══"
        output_lines.append(title)
        output_lines.append("")
        

        step_info = f"Step {self.current_step} / {self.total_steps}"
        output_lines.append(step_info)
        

        costs = f"g={state.g_cost}  h={state.h_cost}  f={state.f_cost}"
        output_lines.append(costs)
        output_lines.append("")
        

        grid_str = self._render_grid(state.tiles)
        output_lines.append(grid_str)
        output_lines.append("")
        

        legend = f"{GREEN}■{RESET} Well-placed  {RED}■{RESET} Misplaced  {BOLD}{ORANGE}■{RESET} Just moved"
        output_lines.append(legend)
        output_lines.append("")
        

        nav_parts = []
        if self.current_step > 0:
            nav_parts.append("← Prev")
        else:
            nav_parts.append("       ")
        
        nav_parts.append("  |  ")
        
        if self.current_step < self.total_steps:
            nav_parts.append("Next →")
        else:
            nav_parts.append("       ")
        
        nav_line = "".join(nav_parts)
        output_lines.append(nav_line)
        output_lines.append("")
        output_lines.append("Press 'q' to quit")
        

        full_output = '\n'.join(output_lines)
        centered = self.center_text(full_output, width)
        

        padding_lines = max(0, (height - len(output_lines)) // 2 - 2)
        sys.stdout.write('\n' * padding_lines)
        sys.stdout.write(centered)
        sys.stdout.flush()

    def _get_moved_tile(self) -> Optional[int]:
        if self.current_step == 0:
            return None
        
        prev_tiles = self.solution.states[self.current_step - 1].tiles
        curr_tiles = self.solution.states[self.current_step].tiles
        

        prev_zero = prev_tiles.index(0)
        curr_zero = curr_tiles.index(0)
        

        moved_tile = curr_tiles[prev_zero]
        return moved_tile

    def _render_grid(self, tiles: list[int]) -> str:
        size = int(math.sqrt(len(tiles)))
        width = len(str(size * size))
        horizontal = "+" + "+".join(["-" * (width + 2)] * size) + "+"
        
        moved_tile = self._get_moved_tile()
        
        lines = [horizontal]
        for r in range(size):
            row = []
            for c in range(size):
                idx = c + r * size
                value = tiles[idx]
                
                if value == 0:
                    cell = " " * width
                else:
                    text = f"{value:>{width}}"
                    
                    # Apply colors based on tile state
                    if value == moved_tile:
                        # Moved tile: bold and orange
                        text = f"{BOLD}{ORANGE}{text}{RESET}"
                    elif self.goal_state[idx] == value:
                        # Well-placed: green
                        text = f"{GREEN}{text}{RESET}"
                    else:
                        # Misplaced: red
                        text = f"{RED}{text}{RESET}"
                    
                    cell = text
                row.append(f" {cell} ")
            lines.append("|" + "|".join(row) + "|")
            lines.append(horizontal)
        
        return '\n'.join(lines)

    def get_key(self) -> str:
        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            ch = sys.stdin.read(1)
            

            if ch == '\x1b':
                ch2 = sys.stdin.read(1)
                if ch2 == '[':
                    ch3 = sys.stdin.read(1)
                    if ch3 == 'C':
                        return 'RIGHT'
                    elif ch3 == 'D':
                        return 'LEFT'
                    elif ch3 == 'A':
                        return 'UP'
                    elif ch3 == 'B':
                        return 'DOWN'
            return ch
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

    def run(self) -> None:
        try:
            self.render_state()
            
            while True:
                key = self.get_key()
                
                if key.lower() == 'q':
                    break
                elif key == 'RIGHT' and self.current_step < self.total_steps:
                    self.current_step += 1
                    self.render_state()
                elif key == 'LEFT' and self.current_step > 0:
                    self.current_step -= 1
                    self.render_state()
                elif key == ' ':  # Space bar
                    if self.current_step < self.total_steps:
                        self.current_step += 1
                        self.render_state()
            
            self.clear_screen()
            print("Exited interactive viewer.")
            
        except KeyboardInterrupt:
            self.clear_screen()
            print("\nInterrupted.")
            sys.exit(0)


def show_interactive(solution: Solution) -> None:
    viewer = InteractiveViewer(solution)
    viewer.run()

