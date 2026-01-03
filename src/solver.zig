const std = @import("std");
const assert = std.debug.assert;
const State = @import("state.zig").State;
const heuristics = @import("heuristics.zig");
const GoalLookup = heuristics.GoalLookup;
const HeuristicFn = heuristics.HeuristicFn;
const Allocator = std.mem.Allocator;

pub const SearchMode = enum {
    astar,
    uniform_cost,
    greedy,
};

pub const Statistics = struct {
    states_selected: usize,
    max_states_in_memory: usize,
    solution_length: usize,

    pub fn init() Statistics {
        return .{
            .states_selected = 0,
            .max_states_in_memory = 0,
            .solution_length = 0,
        };
    }
};

pub const Solution = struct {
    path: []*const State,
    stats: Statistics,
    allocator: Allocator,
    closed_set: std.HashMap(*const State, void, StateHashContext, 80),

    pub fn deinit(self: *Solution) void {
        var iter = self.closed_set.keyIterator();
        while (iter.next()) |state_ptr| {
            const state: *State = @constCast(state_ptr.*);
            state.deinit(self.allocator);
        }
        self.closed_set.deinit();
        self.allocator.free(self.path);
    }
};

const PQNode = struct {
    state: *State,

    fn compareFn(context: void, a: PQNode, b: PQNode) std.math.Order {
        _ = context;

        if (a.state.f_cost < b.state.f_cost) return .lt;
        if (a.state.f_cost > b.state.f_cost) return .gt;

        if (a.state.h_cost < b.state.h_cost) return .lt;
        if (a.state.h_cost > b.state.h_cost) return .gt;

        return .eq;
    }
};

pub const StateHashContext = struct {
    pub fn hash(self: @This(), key: *const State) u64 {
        _ = self;
        return key.hash();
    }

    pub fn eql(self: @This(), a: *const State, b: *const State) bool {
        _ = self;
        return a.eql(b);
    }
};

pub fn solve(
    allocator: Allocator,
    initial: *State,
    goal: *const State,
    goal_lookup: *const GoalLookup,
    heuristic_fn: HeuristicFn,
    mode: SearchMode,
) !?Solution {
    assert(initial.size == goal.size);
    assert(goal.size == goal_lookup.size);

    var stats = Statistics.init();

    var closed_set = std.HashMap(*const State, void, StateHashContext, 80).init(allocator);
    errdefer {
        var closed_iter = closed_set.keyIterator();
        while (closed_iter.next()) |state_ptr| {
            const state: *State = @constCast(state_ptr.*);
            state.deinit(allocator);
        }
        closed_set.deinit();
    }

    var open_set = std.PriorityQueue(PQNode, void, PQNode.compareFn).init(allocator, {});
    defer {
        while (open_set.removeOrNull()) |node| {
            node.state.deinit(allocator);
        }
        open_set.deinit();
    }

    initial.g_cost = 0;
    initial.h_cost = if (mode == .uniform_cost) 0 else heuristic_fn(initial, goal_lookup);
    initial.f_cost = computeFCost(mode, initial.g_cost, initial.h_cost);
    initial.parent = null;
    initial.validateInvariants();

    try open_set.add(.{ .state = initial });
    stats.max_states_in_memory = @max(stats.max_states_in_memory, open_set.count() + closed_set.count());

    while (open_set.removeOrNull()) |node| {
        const current_state = node.state;
        stats.states_selected += 1;

        if (closed_set.contains(current_state)) {
            current_state.deinit(allocator);
            continue;
        }

        current_state.validateInvariants();

        if (current_state.eql(goal)) {
            try closed_set.put(current_state, {});
            stats.max_states_in_memory = @max(stats.max_states_in_memory, open_set.count() + closed_set.count());
            const solution = try reconstructPath(allocator, current_state, &stats, closed_set);
            return solution;
        }

        try closed_set.put(current_state, {});
        stats.max_states_in_memory = @max(stats.max_states_in_memory, open_set.count() + closed_set.count());

        const successors = try generateSuccessors(allocator, current_state, goal_lookup, heuristic_fn, mode);
        defer allocator.free(successors);

        for (successors) |successor| {
            if (closed_set.contains(successor)) {
                successor.deinit(allocator);
                continue;
            }
            try open_set.add(.{ .state = successor });
        }
        stats.max_states_in_memory = @max(stats.max_states_in_memory, open_set.count() + closed_set.count());
    }

    var closed_iter = closed_set.keyIterator();
    while (closed_iter.next()) |state_ptr| {
        const state: *State = @constCast(state_ptr.*);
        state.deinit(allocator);
    }
    closed_set.deinit();

    return null;
}

pub fn generateSuccessors(
    allocator: Allocator,
    current: *const State,
    goal_lookup: *const GoalLookup,
    heuristic_fn: HeuristicFn,
    mode: SearchMode,
) ![]const *State {
    assert(current.size > 0);
    assert(current.empty_pos < current.tiles.len);

    var successors: std.ArrayList(*State) = .empty;
    errdefer {
        for (successors.items) |successor| successor.deinit(allocator);
        successors.deinit(allocator);
    }

    const empty_row = current.empty_pos / current.size;
    const empty_col = current.empty_pos % current.size;

    const Direction = struct { delta_row: isize, delta_col: isize };
    const directions = [_]Direction{
        .{ .delta_row = -1, .delta_col = 0 },
        .{ .delta_row = 1, .delta_col = 0 },
        .{ .delta_row = 0, .delta_col = -1 },
        .{ .delta_row = 0, .delta_col = 1 },
    };

    for (directions) |direction| {
        const new_row = @as(isize, @intCast(empty_row)) + direction.delta_row;
        const new_col = @as(isize, @intCast(empty_col)) + direction.delta_col;

        const size_as_isize = @as(isize, @intCast(current.size));
        const is_out_of_bounds = new_row < 0 or new_row >= size_as_isize or new_col < 0 or new_col >= size_as_isize;

        if (is_out_of_bounds) continue;

        const new_empty_pos = @as(usize, @intCast(new_row)) * current.size + @as(usize, @intCast(new_col));
        assert(new_empty_pos < current.tiles.len);

        const successor = try current.clone(allocator);
        errdefer successor.deinit(allocator);

        successor.tiles[current.empty_pos] = successor.tiles[new_empty_pos];
        successor.tiles[new_empty_pos] = 0;
        successor.empty_pos = new_empty_pos;

        assert(successor.tiles[new_empty_pos] == 0);
        assert(successor.tiles[current.empty_pos] != 0);

        successor.g_cost = current.g_cost + 1;
        successor.h_cost = if (mode == .uniform_cost) 0 else heuristic_fn(successor, goal_lookup);
        successor.f_cost = computeFCost(mode, successor.g_cost, successor.h_cost);
        successor.parent = current;

        assert(successor.g_cost > 0);
        assert(successor.f_cost == computeFCost(mode, successor.g_cost, successor.h_cost));

        successor.validateInvariants();

        try successors.append(allocator, successor);
    }

    const successor_count = successors.items.len;
    assert(successor_count >= 2 and successor_count <= 4);

    return successors.toOwnedSlice(allocator);
}

pub fn reconstructPath(
    allocator: Allocator,
    goal_state: *const State,
    stats: *Statistics,
    closed_set: std.HashMap(*const State, void, StateHashContext, 80),
) !Solution {
    var path: std.ArrayList(*const State) = .empty;
    errdefer path.deinit(allocator);

    var current_state: ?*const State = goal_state;

    while (current_state) |state| {
        try path.insert(allocator, 0, state);
        current_state = state.parent;
    }

    assert(path.items.len > 0);
    assert(path.items[0].parent == null);
    assert(path.items[path.items.len - 1] == goal_state);

    stats.solution_length = path.items.len - 1;
    assert(stats.solution_length == goal_state.g_cost);

    return Solution{
        .path = try path.toOwnedSlice(allocator),
        .stats = stats.*,
        .allocator = allocator,
        .closed_set = closed_set,
    };
}

pub fn computeFCost(mode: SearchMode, g_cost: u32, h_cost: u32) u32 {
    return switch (mode) {
        .astar => g_cost + h_cost,
        .uniform_cost => g_cost,
        .greedy => h_cost,
    };
}

test "solve - already solved puzzle" {
    const allocator = std.testing.allocator;

    const tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };

    const initial = try State.initFromTiles(allocator, 3, &tiles);
    const goal = try State.initFromTiles(allocator, 3, &tiles);
    defer goal.deinit();

    var goal_lookup = try GoalLookup.init(allocator, goal);
    defer goal_lookup.deinit();

    const heuristic_fn = heuristics.manhattanDistance;

    var solution = (try solve(allocator, initial, goal, &goal_lookup, heuristic_fn, .astar)).?;
    defer solution.deinit();

    try std.testing.expectEqual(@as(usize, 0), solution.stats.solution_length);
    try std.testing.expectEqual(@as(usize, 1), solution.path.len);
    try std.testing.expect(solution.stats.states_selected > 0);
}

test "solve - one move away" {
    const allocator = std.testing.allocator;

    const goal_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const initial_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 0, 8 };

    const initial = try State.initFromTiles(allocator, 3, &initial_tiles);
    const goal = try State.initFromTiles(allocator, 3, &goal_tiles);
    defer goal.deinit();

    var goal_lookup = try GoalLookup.init(allocator, goal);
    defer goal_lookup.deinit();

    const heuristic_fn = heuristics.manhattanDistance;

    var solution = (try solve(allocator, initial, goal, &goal_lookup, heuristic_fn, .astar)).?;
    defer solution.deinit();

    try std.testing.expectEqual(@as(usize, 1), solution.stats.solution_length);
    try std.testing.expectEqual(@as(usize, 2), solution.path.len);

    try std.testing.expect(solution.path[0].eql(initial));
    try std.testing.expect(solution.path[1].eql(goal));
}

test "solve - two moves away" {
    const allocator = std.testing.allocator;

    const goal_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const initial_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 0, 7, 8 };

    const initial = try State.initFromTiles(allocator, 3, &initial_tiles);
    const goal = try State.initFromTiles(allocator, 3, &goal_tiles);
    defer goal.deinit();

    var goal_lookup = try GoalLookup.init(allocator, goal);
    defer goal_lookup.deinit();

    const heuristic_fn = heuristics.manhattanDistance;

    var solution = (try solve(allocator, initial, goal, &goal_lookup, heuristic_fn, .astar)).?;
    defer solution.deinit();

    try std.testing.expectEqual(@as(usize, 2), solution.stats.solution_length);
    try std.testing.expectEqual(@as(usize, 3), solution.path.len);
}

test "solve - tracks statistics correctly" {
    const allocator = std.testing.allocator;

    const goal_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const initial_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 0, 7, 8 };

    const initial = try State.initFromTiles(allocator, 3, &initial_tiles);
    const goal = try State.initFromTiles(allocator, 3, &goal_tiles);
    defer goal.deinit();

    var goal_lookup = try GoalLookup.init(allocator, goal);
    defer goal_lookup.deinit();

    const heuristic_fn = heuristics.manhattanDistance;

    var solution = (try solve(allocator, initial, goal, &goal_lookup, heuristic_fn, .astar)).?;
    defer solution.deinit();

    try std.testing.expect(solution.stats.states_selected > 0);
    try std.testing.expect(solution.stats.max_states_in_memory > 0);
    try std.testing.expectEqual(@as(usize, 2), solution.stats.solution_length);
}

test "solve - uniform cost search (h=0) still solves optimally" {
    const allocator = std.testing.allocator;

    const goal_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const initial_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 0, 8 };

    const initial = try State.initFromTiles(allocator, 3, &initial_tiles);
    const goal = try State.initFromTiles(allocator, 3, &goal_tiles);
    defer goal.deinit();

    var goal_lookup = try GoalLookup.init(allocator, goal);
    defer goal_lookup.deinit();

    var solution = (try solve(allocator, initial, goal, &goal_lookup, heuristics.manhattanDistance, .uniform_cost)).?;
    defer solution.deinit();

    try std.testing.expectEqual(@as(usize, 1), solution.stats.solution_length);
    try std.testing.expectEqual(@as(usize, 2), solution.path.len);
}

test "solve - greedy best-first search finds a solution" {
    const allocator = std.testing.allocator;

    const goal_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const initial_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 0, 8 };

    const initial = try State.initFromTiles(allocator, 3, &initial_tiles);
    const goal = try State.initFromTiles(allocator, 3, &goal_tiles);
    defer goal.deinit();

    var goal_lookup = try GoalLookup.init(allocator, goal);
    defer goal_lookup.deinit();

    var solution = (try solve(allocator, initial, goal, &goal_lookup, heuristics.manhattanDistance, .greedy)).?;
    defer solution.deinit();

    try std.testing.expectEqual(@as(usize, 1), solution.stats.solution_length);
    try std.testing.expectEqual(@as(usize, 2), solution.path.len);
}

test "generateSuccessors - corner position has 2 successors" {
    const allocator = std.testing.allocator;

    const tiles = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8 };
    const state = try State.initFromTiles(allocator, 3, &tiles);
    defer state.deinit();

    const goal = try State.initFromTiles(allocator, 3, &tiles);
    defer goal.deinit();

    var goal_lookup = try GoalLookup.init(allocator, goal);
    defer goal_lookup.deinit();

    const successors = try generateSuccessors(
        allocator,
        state,
        &goal_lookup,
        heuristics.manhattanDistance,
        .astar,
    );
    defer {
        for (successors) |s| s.deinit();
        allocator.free(successors);
    }

    try std.testing.expectEqual(@as(usize, 2), successors.len);
}

test "generateSuccessors - edge position has 3 successors" {
    const allocator = std.testing.allocator;

    const tiles = [_]u8{ 1, 0, 2, 3, 4, 5, 6, 7, 8 };
    const state = try State.initFromTiles(allocator, 3, &tiles);
    defer state.deinit();

    const goal = try State.initFromTiles(allocator, 3, &tiles);
    defer goal.deinit();

    var goal_lookup = try GoalLookup.init(allocator, goal);
    defer goal_lookup.deinit();

    const successors = try generateSuccessors(
        allocator,
        state,
        &goal_lookup,
        heuristics.manhattanDistance,
        .astar,
    );
    defer {
        for (successors) |s| s.deinit();
        allocator.free(successors);
    }

    try std.testing.expectEqual(@as(usize, 3), successors.len);
}

test "generateSuccessors - center position has 4 successors" {
    const allocator = std.testing.allocator;

    const tiles = [_]u8{ 1, 2, 3, 4, 0, 5, 6, 7, 8 };
    const state = try State.initFromTiles(allocator, 3, &tiles);
    defer state.deinit();

    const goal = try State.initFromTiles(allocator, 3, &tiles);
    defer goal.deinit();

    var goal_lookup = try GoalLookup.init(allocator, goal);
    defer goal_lookup.deinit();

    const successors = try generateSuccessors(
        allocator,
        state,
        &goal_lookup,
        heuristics.manhattanDistance,
        .astar,
    );
    defer {
        for (successors) |s| s.deinit();
        allocator.free(successors);
    }

    try std.testing.expectEqual(@as(usize, 4), successors.len);
}

test "generateSuccessors - all successors have incremented g_cost" {
    const allocator = std.testing.allocator;

    const tiles = [_]u8{ 1, 2, 3, 4, 0, 5, 6, 7, 8 };
    const state = try State.initFromTiles(allocator, 3, &tiles);
    defer state.deinit();

    state.g_cost = 5;

    const goal = try State.initFromTiles(allocator, 3, &tiles);
    defer goal.deinit();

    var goal_lookup = try GoalLookup.init(allocator, goal);
    defer goal_lookup.deinit();

    const successors = try generateSuccessors(
        allocator,
        state,
        &goal_lookup,
        heuristics.manhattanDistance,
        .astar,
    );
    defer {
        for (successors) |s| s.deinit();
        allocator.free(successors);
    }

    for (successors) |successor| {
        try std.testing.expectEqual(@as(u32, 6), successor.g_cost);
        try std.testing.expectEqual(state, successor.parent.?);
    }
}

test "reconstructPath - builds correct path" {
    const allocator = std.testing.allocator;

    const tiles1 = [_]u8{ 1, 2, 3, 4, 5, 6, 0, 7, 8 };
    const state1 = try State.initFromTiles(allocator, 3, &tiles1);
    defer state1.deinit();
    state1.g_cost = 0;
    state1.parent = null;

    const tiles2 = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 0, 8 };
    const state2 = try State.initFromTiles(allocator, 3, &tiles2);
    defer state2.deinit();
    state2.g_cost = 1;
    state2.parent = state1;

    const tiles3 = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const state3 = try State.initFromTiles(allocator, 3, &tiles3);
    defer state3.deinit();
    state3.g_cost = 2;
    state3.parent = state2;

    var stats = Statistics.init();
    var closed_set = std.HashMap(*const State, void, StateHashContext, 80).init(allocator);
    errdefer closed_set.deinit();

    var solution = try reconstructPath(allocator, state3, &stats, closed_set);
    defer solution.deinit();

    try std.testing.expectEqual(@as(usize, 3), solution.path.len);
    try std.testing.expectEqual(@as(usize, 2), solution.stats.solution_length);

    try std.testing.expectEqual(state1, solution.path[0]);
    try std.testing.expectEqual(state2, solution.path[1]);
    try std.testing.expectEqual(state3, solution.path[2]);
}
