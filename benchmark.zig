const std = @import("std");
const state_mod = @import("src/state.zig");
const State = state_mod.State;
const heuristics = @import("src/heuristics.zig");
const solver = @import("src/solver.zig");
const solver_parallel = @import("src/solver_parallel.zig");
const SearchMode = solver.SearchMode;
const gen = @import("src/gen.zig");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var rng = std.Random.DefaultPrng.init(std.crypto.random.int(u64));

    const modes = [_]SearchMode{
        .greedy,
        .astar,
        .uniform_cost,
    };
    const cpu_count = std.Thread.getCpuCount() catch 1;
    const threads = if (cpu_count == 0) 1 else cpu_count;

    std.debug.print("Benchmarking N-Puzzle (sizes 3..4), 100 runs each, heuristic=manhattan\n\n", .{});

    for (3..5) |size| {
        std.debug.print("Size {d}x{d}\n", .{ size, size });
        for (modes) |mode| {
            var accum = Accumulator{};
            for (0..4) |_| {
                const initial = try generateState(allocator, size, rng.random());

                const goal = try buildGoalState(allocator, size);
                defer goal.deinit();

                var goal_lookup = try heuristics.GoalLookup.init(allocator, goal);
                defer goal_lookup.deinit();

                const heuristic_fn = heuristics.manhattanDistance;

                var timer = try std.time.Timer.start();
                const solution_opt = try solver_parallel.solveParallel(
                    allocator,
                    initial,
                    goal,
                    &goal_lookup,
                    heuristic_fn,
                    mode,
                    threads,
                );
                var solution = solution_opt orelse return error.UnexpectedUnsolvable;
                const elapsed = timer.read(); // ns

                defer solution.deinit();

                accum.addRun(elapsed, &solution.stats);
            }
            accum.printSummary(size, mode, threads);
        }
        std.debug.print("\n", .{});
    }
}

const Accumulator = struct {
    total_time_ns: u128 = 0,
    total_states_selected: u128 = 0,
    total_max_states: u128 = 0,
    total_length: u128 = 0,
    runs: u32 = 0,

    fn addRun(self: *Accumulator, duration_ns: u64, stats: *const solver.Statistics) void {
        self.total_time_ns += duration_ns;
        self.total_states_selected += @as(u128, stats.states_selected);
        self.total_max_states += @as(u128, stats.max_states_in_memory);
        self.total_length += @as(u128, stats.solution_length);
        self.runs += 1;
    }

    fn printSummary(self: *const Accumulator, size: usize, mode: SearchMode, threads: usize) void {
        const avg_time_ms: f64 = @as(f64, @floatFromInt(self.total_time_ns)) / @as(f64, @floatFromInt(self.runs)) / 1_000_000.0;
        const avg_states = self.total_states_selected / self.runs;
        const avg_max_states = self.total_max_states / self.runs;
        const avg_length = self.total_length / self.runs;

        std.debug.print(
            "  N={d} [{s:12}] threads={d} avg_time={d:.2}ms avg_states={d} avg_space={d} avg_len={d}\n",
            .{
                size,
                @tagName(mode),
                threads,
                avg_time_ms,
                avg_states,
                avg_max_states,
                avg_length,
            },
        );
    }
};

fn generateState(allocator: std.mem.Allocator, size: usize, rand: std.Random) !*State {
    var puzzle = try gen.Puzzle.init(allocator, size);
    errdefer puzzle.deinit();

    puzzle.generateSnail();
    puzzle.shuffle(1000, rand);
    puzzle.ensureSolvability(true);

    const state = try puzzleToState(allocator, &puzzle);
    puzzle.deinit();
    return state;
}

fn buildGoalState(allocator: std.mem.Allocator, size: usize) !*State {
    var goal_puzzle = try gen.Puzzle.init(allocator, size);
    defer goal_puzzle.deinit();
    goal_puzzle.generateSnail();
    return try puzzleToState(allocator, &goal_puzzle);
}

fn puzzleToState(allocator: std.mem.Allocator, puzzle: *const gen.Puzzle) !*State {
    var tiles = try allocator.alloc(u8, puzzle.size * puzzle.size);
    errdefer allocator.free(tiles);

    for (puzzle.grid, 0..) |val, i| {
        tiles[i] = @intCast(val);
    }

    const state = try State.initFromTiles(allocator, puzzle.size, tiles);
    allocator.free(tiles);
    return state;
}
