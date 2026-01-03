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
const testing = std.testing;

comptime {
    testing.refAllDecls(state_mod);
    testing.refAllDecls(heuristics);
    testing.refAllDecls(solver);
    testing.refAllDecls(solver_parallel);
    testing.refAllDecls(solvability);
    testing.refAllDecls(io);
    testing.refAllDecls(gen);
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

const ParsedArgs = struct {
    size: usize,
    tiles: []u8,
    heuristic: HeuristicType,
    search_mode: SearchMode,
    threads: usize,
};

fn parseArgsSimple(allocator: std.mem.Allocator) !ParsedArgs {
    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    if (args.len < 2) return error.MissingArguments;

    const size = try std.fmt.parseInt(usize, args[1], 10);
    if (size < 3 or size > state_mod.MAX_SIZE) return error.InvalidSize;

    const expected_tiles = size * size;
    const tiles_end = 2 + expected_tiles;
    if (args.len < tiles_end) return error.InsufficientTiles;

    var tiles = try allocator.alloc(u8, expected_tiles);
    for (0..expected_tiles) |i| {
        tiles[i] = try std.fmt.parseInt(u8, args[2 + i], 10);
    }

    var parsed = ParsedArgs{
        .size = size,
        .tiles = tiles,
        .heuristic = .manhattan,
        .search_mode = .astar,
        .threads = std.Thread.getCpuCount() catch 1,
    };

    var i = tiles_end;
    while (i < args.len) : (i += 1) {
        if (mem.eql(u8, args[i], "--heuristic") and i + 1 < args.len) {
            i += 1;
            parsed.heuristic = HeuristicType.fromString(args[i]) orelse return error.InvalidHeuristic;
        } else if (mem.eql(u8, args[i], "--search") and i + 1 < args.len) {
            i += 1;
            parsed.search_mode = parseSearchMode(args[i]) orelse return error.InvalidSearchMode;
        } else if (mem.eql(u8, args[i], "--threads") or mem.eql(u8, args[i], "-t")) {
            i += 1;
            parsed.threads = try std.fmt.parseInt(usize, args[i], 10);
        }
    }

    return parsed;
}

fn puzzleToState(allocator: std.mem.Allocator, puzzle: *const gen.Puzzle) !*State {
    assert(puzzle.size > 0);
    return State.initFromTiles(allocator, puzzle.size, puzzle.grid);
}

pub fn main() !void {
    const allocator = heap.smp_allocator;

    var threaded: Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(threaded.io(), &stdout_buffer);
    const stdout: *Io.Writer = &stdout_writer.interface;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = Io.File.stderr().writer(threaded.io(), &stderr_buffer);
    const stderr: *Io.Writer = &stderr_writer.interface;

    const args = parseArgsSimple(allocator) catch |err| {
        const json_output = try state_mod.stringify(allocator, null, @errorName(err));
        defer allocator.free(json_output);
        try stdout.writeAll(json_output);
        try stdout.flush();
        try stderr.print("Error parsing arguments: {}\n", .{err});
        try stderr.flush();
        process.exit(1);
    };
    defer allocator.free(args.tiles);

    var initial_state = State.initFromTiles(allocator, args.size, args.tiles) catch |err| {
        const json_output = try state_mod.stringify(allocator, null, @errorName(err));
        defer allocator.free(json_output);
        try stdout.writeAll(json_output);
        try stdout.flush();
        try stderr.print("Error creating state: {}\n", .{err});
        try stderr.flush();
        process.exit(1);
    };
    errdefer initial_state.deinit(allocator);

    solvability.validatePuzzle(initial_state) catch |err| {
        const json_output = try state_mod.stringify(allocator, null, @errorName(err));
        defer allocator.free(json_output);
        try stdout.writeAll(json_output);
        try stdout.flush();
        try stderr.print("Invalid puzzle: {}\n", .{err});
        try stderr.flush();
        initial_state.deinit(allocator);
        process.exit(1);
    };

    var goal_puzzle = try gen.Puzzle.init(allocator, args.size);
    defer goal_puzzle.deinit();
    goal_puzzle.generateSnail();

    var goal_state = try State.initFromTiles(allocator, args.size, goal_puzzle.grid);
    defer goal_state.deinit(allocator);

    var goal_lookup = try GoalLookup.init(allocator, goal_state);
    defer goal_lookup.deinit();

    if (!solvability.isSolvable(initial_state, goal_state)) {
        const json_output = try state_mod.stringify(allocator, null, "Puzzle is unsolvable");
        defer allocator.free(json_output);
        try stdout.writeAll(json_output);
        try stdout.flush();
        initial_state.deinit(allocator);
        process.exit(0);
    }

    const heuristic_fn = heuristics.getHeuristic(args.heuristic);

    const solution_opt = if (args.threads > 1)
        try solver_parallel.solveParallel(
            allocator,
            initial_state,
            goal_state,
            &goal_lookup,
            heuristic_fn,
            args.search_mode,
            args.threads,
        )
    else
        try solver.solve(
            allocator,
            initial_state,
            goal_state,
            &goal_lookup,
            heuristic_fn,
            args.search_mode,
        );

    if (solution_opt) |solution| {
        var mut_solution = solution;
        defer mut_solution.deinit();
        const json_output = try state_mod.stringify(allocator, mut_solution, null);
        defer allocator.free(json_output);
        try stdout.writeAll(json_output);
        try stdout.flush();
    } else {
        const json_output = try state_mod.stringify(allocator, null, "No solution found");
        defer allocator.free(json_output);
        try stdout.writeAll(json_output);
        try stdout.flush();
    }
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
