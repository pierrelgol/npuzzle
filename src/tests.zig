const std = @import("std");
const testing = std.testing;
const state_mod = @import("state.zig");
const State = state_mod.State;
const heuristics = @import("heuristics.zig");
const GoalLookup = heuristics.GoalLookup;
const solver = @import("solver.zig");
const solver_parallel = @import("solver_parallel.zig");
const solvability = @import("solvability.zig");

fn createGoal3x3(allocator: std.mem.Allocator) !*State {
    const tiles = [_]u8{ 1, 2, 3, 8, 0, 4, 7, 6, 5 };
    return State.initFromTiles(allocator, 3, &tiles);
}

test "Integration: Parallel Solver vs Sequential Solver (3x3)" {
    const allocator = testing.allocator;

    const goal_state = try createGoal3x3(allocator);
    defer goal_state.deinit();

    var goal_lookup = try GoalLookup.init(allocator, goal_state);
    defer goal_lookup.deinit();

    const initial_tiles = [_]u8{ 1, 2, 3, 0, 8, 4, 7, 6, 5 };
    const initial_state = try State.initFromTiles(allocator, 3, &initial_tiles);
    defer initial_state.deinit();

    const initial_for_sequential = try initial_state.clone();
    const initial_for_parallel = try initial_state.clone();

    var sequential_solution = (try solver.solve(
        allocator,
        initial_for_sequential,
        goal_state,
        &goal_lookup,
        heuristics.manhattanDistance,
        .astar,
    )).?;
    defer sequential_solution.deinit();

    var parallel_solution = (try solver_parallel.solveParallel(
        allocator,
        initial_for_parallel,
        goal_state,
        &goal_lookup,
        heuristics.manhattanDistance,
        .astar,
        2,
    )).?;
    defer parallel_solution.deinit();

    try testing.expectEqual(sequential_solution.stats.solution_length, parallel_solution.stats.solution_length);
    try testing.expectEqual(sequential_solution.path.len, parallel_solution.path.len);
}

test "Integration: Parallel Solver (4 threads)" {
    const allocator = testing.allocator;

    const goal_state = try createGoal3x3(allocator);
    defer goal_state.deinit();

    var goal_lookup = try GoalLookup.init(allocator, goal_state);
    defer goal_lookup.deinit();

    const initial_tiles = [_]u8{ 1, 2, 3, 0, 8, 4, 7, 6, 5 };
    const initial_state = try State.initFromTiles(allocator, 3, &initial_tiles);

    var solution = (try solver_parallel.solveParallel(
        allocator,
        initial_state,
        goal_state,
        &goal_lookup,
        heuristics.manhattanDistance,
        .astar,
        4,
    )).?;
    defer solution.deinit();

    try testing.expectEqual(@as(usize, 1), solution.stats.solution_length);
}

test "Integration: Parallel Solver (1 thread fallback)" {
    const allocator = testing.allocator;

    const goal_state = try createGoal3x3(allocator);
    defer goal_state.deinit();

    var goal_lookup = try GoalLookup.init(allocator, goal_state);
    defer goal_lookup.deinit();

    const initial_tiles = [_]u8{ 1, 2, 3, 0, 8, 4, 7, 6, 5 };
    const initial_state = try State.initFromTiles(allocator, 3, &initial_tiles);

    var solution = (try solver_parallel.solveParallel(
        allocator,
        initial_state,
        goal_state,
        &goal_lookup,
        heuristics.manhattanDistance,
        .astar,
        1,
    )).?;
    defer solution.deinit();

    try testing.expectEqual(@as(usize, 1), solution.stats.solution_length);
}

test "Integration: Unsolvable Puzzle detection" {
    const allocator = testing.allocator;

    const goal_state = try createGoal3x3(allocator);
    defer goal_state.deinit();

    const unsolvable_tiles = [_]u8{ 2, 1, 3, 8, 0, 4, 7, 6, 5 };
    const unsolvable_state = try State.initFromTiles(allocator, 3, &unsolvable_tiles);
    defer unsolvable_state.deinit();

    try testing.expect(!solvability.isSolvable(unsolvable_state, goal_state));
}

test "Integration: Large Puzzle (4x4) Parallel" {
    const allocator = testing.allocator;

    const goal_tiles = [_]u8{
        1,  2,  3,  4,
        5,  6,  7,  8,
        9,  10, 11, 12,
        13, 14, 15, 0,
    };
    const goal_state = try State.initFromTiles(allocator, 4, &goal_tiles);
    defer goal_state.deinit();

    var goal_lookup = try GoalLookup.init(allocator, goal_state);
    defer goal_lookup.deinit();

    const initial_tiles = [_]u8{
        1,  2,  3,  4,
        5,  6,  7,  8,
        9,  10, 11, 12,
        13, 14, 0,  15,
    };
    const initial_state = try State.initFromTiles(allocator, 4, &initial_tiles);

    var solution = (try solver_parallel.solveParallel(
        allocator,
        initial_state,
        goal_state,
        &goal_lookup,
        heuristics.manhattanDistance,
        .astar,
        4,
    )).?;
    defer solution.deinit();

    try testing.expectEqual(@as(usize, 1), solution.stats.solution_length);
}
