# N-Puzzle Solver

High-performance sliding tile puzzle solver written in Zig.

![Demo](demo/Screenshot%20From%202025-12-31%2011-20-43.png)

## Build

```bash
zig build
```

## Usage

```bash
# Solve from file
./zig-out/bin/npuzzle puzzle.txt

# Generate and solve random puzzle
./zig-out/bin/npuzzle -g 3 -s          # 3x3 solvable puzzle
./zig-out/bin/npuzzle -g 4 -s -i 5000  # 4x4 with 5000 shuffles

# Use different heuristics and search modes
./zig-out/bin/npuzzle --heuristic linear --search astar puzzle.txt

# Multi-threaded solving
./zig-out/bin/npuzzle -t 32 -g 5 -s
```

## Options

```
--heuristic <TYPE>    manhattan (default), misplaced, linear
--search <MODE>       astar (default), ucs, greedy
-t, --threads <N>     Number of threads (default: CPU count)
-g, --generate <SIZE> Generate random SIZE x SIZE puzzle
-s, --solvable        Force generated puzzle to be solvable
-u, --unsolvable      Force generated puzzle to be unsolvable
-i, --iterations <N>  Shuffle iterations (default: 10000)
-h, --help            Show help
```

## Puzzle File Format

```
# Comment
3
1 2 3
4 5 6
7 8 0
```

First line: size. Next lines: tiles (0 = empty space).
