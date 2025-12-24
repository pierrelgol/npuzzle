const std = @import("std");
const mem = std.mem;
const heap = std.heap;
const assert = std.debug.assert;
const process = std.process;
const fs = std.fs;
const Io = std.Io;

const state_mod = @import("state.zig");
const State = state_mod.State;
const heuristics = @import("heuristics.zig");
const HeuristicType = heuristics.HeuristicType;
const GoalLookup = heuristics.GoalLookup;
const solver = @import("solver.zig");
const SearchMode = solver.SearchMode;
const solver_parallel = @import("solver_parallel.zig");
const solvability = @import("solvability.zig");
const io = @import("io.zig");
const gen = @import("gen.zig");
const tests = @import("tests.zig");
const testing = std.testing;

comptime {
    testing.refAllDecls(state_mod);
    testing.refAllDecls(heuristics);
    testing.refAllDecls(solver);
    testing.refAllDecls(solver_parallel);
    testing.refAllDecls(solvability);
    testing.refAllDecls(io);
    testing.refAllDecls(gen);
    testing.refAllDecls(tests);
}

const Options = struct {
    heuristic: HeuristicType = .manhattan,
    search_mode: SearchMode = .astar,
    threads: usize = 1,
    input_mode: InputMode,

    const InputMode = union(enum) {
        file: []const u8,
        generate: GenerateOptions,
    };

    const GenerateOptions = struct {
        size: usize,
        solvable: ?bool = null,
        iterations: usize = 10000,
    };
};

fn parseSearchMode(s: []const u8) ?SearchMode {
    if (mem.eql(u8, s, "astar")) return .astar;
    if (mem.eql(u8, s, "ucs")) return .uniform_cost;
    if (mem.eql(u8, s, "greedy")) return .greedy;
    return null;
}

fn parseArgs(allocator: std.mem.Allocator) !Options {
    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return error.MissingArguments;
    }

    var options: Options = undefined;
    options.heuristic = .manhattan;
    options.search_mode = .astar;
    options.threads = std.Thread.getCpuCount() catch 1;
    var heuristic_explicitly_set = false;
    var input_file_path: ?[]const u8 = null;
    var puzzle_size_to_generate: ?usize = null;
    var should_be_solvable: ?bool = null;
    var shuffle_iterations: usize = 10000;

    var arg_index: usize = 1;
    while (arg_index < args.len) : (arg_index += 1) {
        const arg = args[arg_index];

        if (mem.eql(u8, arg, "--help") or mem.eql(u8, arg, "-h")) {
            printUsage();
            process.exit(0);
        } else if (mem.eql(u8, arg, "--heuristic")) {
            arg_index += 1;
            if (arg_index >= args.len) return error.MissingHeuristicValue;

            const heuristic_type = HeuristicType.fromString(args[arg_index]) orelse {
                std.debug.print("Invalid heuristic: {s}\n", .{args[arg_index]});
                std.debug.print("Valid options: manhattan, misplaced, linear\n", .{});
                return error.InvalidHeuristic;
            };

            options.heuristic = heuristic_type;
            heuristic_explicitly_set = true;
        } else if (mem.eql(u8, arg, "--search")) {
            arg_index += 1;
            if (arg_index >= args.len) return error.MissingSearchMode;

            const search_mode = parseSearchMode(args[arg_index]) orelse {
                std.debug.print("Invalid search mode: {s}\n", .{args[arg_index]});
                std.debug.print("Valid options: astar, ucs, greedy\n", .{});
                return error.InvalidSearchMode;
            };

            options.search_mode = search_mode;
        } else if (mem.eql(u8, arg, "-t") or mem.eql(u8, arg, "--threads")) {
            arg_index += 1;
            if (arg_index >= args.len) return error.MissingThreads;
            options.threads = try std.fmt.parseInt(usize, args[arg_index], 10);
        } else if (mem.eql(u8, arg, "-g") or mem.eql(u8, arg, "--generate")) {
            arg_index += 1;
            if (arg_index >= args.len) return error.MissingGenerateSize;
            puzzle_size_to_generate = try std.fmt.parseInt(usize, args[arg_index], 10);
        } else if (mem.eql(u8, arg, "-s") or mem.eql(u8, arg, "--solvable")) {
            should_be_solvable = true;
        } else if (mem.eql(u8, arg, "-u") or mem.eql(u8, arg, "--unsolvable")) {
            should_be_solvable = false;
        } else if (mem.eql(u8, arg, "-i") or mem.eql(u8, arg, "--iterations")) {
            arg_index += 1;
            if (arg_index >= args.len) return error.MissingIterationsValue;
            shuffle_iterations = try std.fmt.parseInt(usize, args[arg_index], 10);
        } else {
            input_file_path = try allocator.dupe(u8, arg);
        }
    }

    if (!heuristic_explicitly_set) {
        options.heuristic = .manhattan;
    }

    if (puzzle_size_to_generate) |size| {
        if (size < 3) {
            std.debug.print("Error: Size must be >= 3\n", .{});
            return error.InvalidSize;
        } else if (size > state_mod.MAX_SIZE) {
            std.debug.print("Error: Size must be <= {d}\n", .{state_mod.MAX_SIZE});
            return error.InvalidSize;
        }

        options.input_mode = .{
            .generate = .{
                .size = size,
                .solvable = should_be_solvable,
                .iterations = shuffle_iterations,
            },
        };
    } else if (input_file_path) |path| {
        options.input_mode = .{ .file = path };
    } else {
        std.debug.print("Error: Must specify either a file or -g/--generate\n", .{});
        printUsage();
        return error.MissingInput;
    }

    if (options.threads == 0) {
        std.debug.print("Error: Threads must be >= 1\n", .{});
        return error.InvalidThreads;
    }

    return options;
}

fn printUsage() void {
    std.debug.print(
        \\Usage: npuzzle [OPTIONS] [FILE]
        \\
        \\Solve N-puzzle using A* search algorithm
        \\
        \\OPTIONS:
        \\  --heuristic <TYPE>     Heuristic function to use
        \\                         manhattan  - Manhattan distance (default)
        \\                         misplaced  - Misplaced tiles count
        \\                         linear     - Linear conflict
        \\  --search <MODE>        Search strategy to use
        \\                         astar      - Standard A* (default)
        \\                         ucs        - Uniform-Cost Search (h=0)
        \\                         greedy     - Greedy Best-First (g=0 for ordering)
        \\  -t, --threads <N>      Number of threads (default: CPU count)
        \\  -g, --generate <SIZE>  Generate random puzzle of SIZE x SIZE
        \\  -s, --solvable         Ensure generated puzzle is solvable
        \\  -u, --unsolvable       Ensure generated puzzle is unsolvable
        \\  -i, --iterations <N>   Shuffle iterations (default: 10000)
        \\  -h, --help             Show this help message
        \\
        \\ARGS:
        \\  <FILE>                 Input file with puzzle definition
        \\
        \\EXAMPLES:
        \\  npuzzle puzzle.txt
        \\  npuzzle --heuristic linear puzzle.txt
        \\  npuzzle -g 3 -s
        \\  npuzzle -g 4 --heuristic misplaced
        \\
    , .{});
}

fn puzzleToState(allocator: std.mem.Allocator, puzzle: *const gen.Puzzle) !*State {
    assert(puzzle.size > 0);
    return State.initFromTiles(allocator, puzzle.size, puzzle.grid);
}

fn generatePuzzle(
    allocator: std.mem.Allocator,
    generate_options: Options.GenerateOptions,
) !*State {
    assert(generate_options.size >= 3);

    var puzzle = try gen.Puzzle.init(allocator, generate_options.size);
    defer puzzle.deinit();

    puzzle.generateSnail();

    const random_seed = std.crypto.random.int(u64);
    var pseudo_random = std.Random.DefaultPrng.init(random_seed);
    const random = pseudo_random.random();

    puzzle.shuffle(generate_options.iterations, random);

    if (generate_options.solvable) |should_be_solvable| {
        puzzle.ensureSolvability(should_be_solvable);
    }

    return try puzzleToState(allocator, &puzzle);
}

pub fn main() !void {
    const allocator = heap.smp_allocator;

    var stderr_buffer: [8192]u8 = undefined;
    var stderr_file = fs.File.stderr().writer(&stderr_buffer);
    const stderr: *Io.Writer = &stderr_file.interface;

    var stdout_buffer: [8192]u8 = undefined;
    var stdout_file = fs.File.stdout().writer(&stdout_buffer);
    const stdout: *Io.Writer = &stdout_file.interface;

    const opts = parseArgs(allocator) catch |err| {
        stderr.print("Error: {}\n", .{err}) catch {};
        process.exit(1);
    };
    defer {
        if (opts.input_mode == .file) {
            allocator.free(opts.input_mode.file);
        }
    }

    const initial_state = switch (opts.input_mode) {
        .file => |path| blk: {
            break :blk io.parseInputFile(allocator, path) catch |err| {
                std.debug.print("Error parsing file: {}\n", .{err});
                process.exit(1);
            };
        },
        .generate => |gen_opts| blk: {
            break :blk generatePuzzle(allocator, gen_opts) catch |err| {
                std.debug.print("Error generating puzzle: {}\n", .{err});
                process.exit(1);
            };
        },
    };

    solvability.validatePuzzle(initial_state) catch |err| {
        std.debug.print("Invalid puzzle: {}\n", .{err});
        initial_state.deinit();
        process.exit(1);
    };

    var goal_puzzle = try gen.Puzzle.init(allocator, initial_state.size);
    defer goal_puzzle.deinit();
    goal_puzzle.generateSnail();

    const goal_state = try puzzleToState(allocator, &goal_puzzle);
    defer goal_state.deinit();

    var goal_lookup = try GoalLookup.init(allocator, goal_state);
    defer goal_lookup.deinit();

    const is_solvable = solvability.isSolvable(initial_state, goal_state);

    if (!is_solvable) {
        try stdout.print("This puzzle is unsolvable.\n", .{});
        initial_state.deinit();
        return;
    }

    const heuristic_fn = heuristics.getHeuristic(opts.heuristic);

    std.debug.print("Solving {d}x{d} puzzle using {s} heuristic ({s} search, {d} thread(s))...\n", .{
        initial_state.size,
        initial_state.size,
        @tagName(opts.heuristic),
        @tagName(opts.search_mode),
        opts.threads,
    });

    const solution_opt = if (opts.threads > 1)
        try solver_parallel.solveParallel(
            allocator,
            initial_state,
            goal_state,
            &goal_lookup,
            heuristic_fn,
            opts.search_mode,
            opts.threads,
        )
    else
        try solver.solve(
            allocator,
            initial_state,
            goal_state,
            &goal_lookup,
            heuristic_fn,
            opts.search_mode,
        );

    var solution = solution_opt orelse {
        try stdout.print("This puzzle is unsolvable.\n", .{});
        return;
    };
    defer solution.deinit();

    try stdout.print("Solution found!\n\n", .{});
    try stdout.print("Time complexity: {d} states selected\n", .{solution.stats.states_selected});
    try stdout.print("Space complexity: {d} max states in memory\n", .{solution.stats.max_states_in_memory});
    try stdout.print("Solution length: {d} moves\n\n", .{solution.stats.solution_length});

    try stdout.print("Solution path:\n", .{});
    try stdout.print("=================================================\n", .{});

    const puzzle_size = solution.path[0].size;
    const max_tile_value = puzzle_size * puzzle_size - 1;
    const tile_width: usize = if (max_tile_value < 10) 1 else 2;
    const box_width = puzzle_size * (tile_width + 1) + 1;

    const CYAN = "\x1b[36m";
    const YELLOW = "\x1b[33m";
    const RESET = "\x1b[0m";

    for (solution.path, 0..) |state, i| {
        var moved_tile: ?u8 = null;
        if (i > 0) {
            const prev_state = solution.path[i - 1];
            moved_tile = state.tiles[prev_state.empty_pos];
        }

        try stdout.print("\nStep {d}:\n┌", .{i});
        for (0..box_width) |_| try stdout.print("─", .{});
        try stdout.print("┐\n", .{});

        for (0..state.size) |row| {
            try stdout.print("│ ", .{});
            for (0..state.size) |col| {
                const tile = state.tiles[row * state.size + col];

                if (tile == 0) {
                    if (tile_width == 1) {
                        try stdout.print("{s}{d}{s} ", .{ CYAN, tile, RESET });
                    } else {
                        try stdout.print("{s}{d:>2}{s} ", .{ CYAN, tile, RESET });
                    }
                } else if (moved_tile != null and tile == moved_tile.?) {
                    if (tile_width == 1) {
                        try stdout.print("{s}{d}{s} ", .{ YELLOW, tile, RESET });
                    } else {
                        try stdout.print("{s}{d:>2}{s} ", .{ YELLOW, tile, RESET });
                    }
                } else {
                    if (tile_width == 1) {
                        try stdout.print("{d} ", .{tile});
                    } else {
                        try stdout.print("{d:>2} ", .{tile});
                    }
                }
            }
            try stdout.print("│\n", .{});
        }

        try stdout.print("└", .{});
        for (0..box_width) |_| try stdout.print("─", .{});
        try stdout.print("┘\n", .{});
    }

    try stdout.print("\n=================================================\n", .{});
    assert(solution.stats.solution_length == solution.path.len - 1);
}

test "puzzleToState - converts correctly" {
    const allocator = std.testing.allocator;

    var puzzle = try gen.Puzzle.init(allocator, 3);
    defer puzzle.deinit();

    puzzle.generateSnail();

    const state = try puzzleToState(allocator, &puzzle);
    defer state.deinit();

    try std.testing.expectEqual(@as(usize, 3), state.size);
    try std.testing.expectEqual(@as(usize, 9), state.tiles.len);

    try std.testing.expectEqual(@as(u8, 1), state.tiles[0]);
    try std.testing.expectEqual(@as(u8, 0), state.tiles[4]);
}

test "generatePuzzle - creates valid puzzle" {
    const allocator = std.testing.allocator;

    const opts = Options.GenerateOptions{
        .size = 3,
        .solvable = true,
        .iterations = 100,
    };

    const state = try generatePuzzle(allocator, opts);
    defer state.deinit();

    try std.testing.expectEqual(@as(usize, 3), state.size);
    try solvability.validatePuzzle(state);
}
