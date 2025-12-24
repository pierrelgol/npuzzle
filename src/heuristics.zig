const std = @import("std");
const assert = std.debug.assert;
const State = @import("state.zig").State;
const Allocator = std.mem.Allocator;

pub const HeuristicFn = *const fn (*const State, *const GoalLookup) u32;

pub const HeuristicType = enum {
    manhattan,
    misplaced_tiles,
    linear_conflict,

    pub fn fromString(s: []const u8) ?HeuristicType {
        if (std.mem.eql(u8, s, "manhattan")) return .manhattan;
        if (std.mem.eql(u8, s, "misplaced")) return .misplaced_tiles;
        if (std.mem.eql(u8, s, "linear")) return .linear_conflict;
        return null;
    }
};

pub const GoalLookup = struct {
    row: []u8,
    col: []u8,
    size: usize,
    allocator: Allocator,

    pub fn init(allocator: Allocator, goal: *const State) !GoalLookup {
        assert(goal.size > 0);

        const row = try allocator.alloc(u8, goal.size * goal.size);
        errdefer allocator.free(row);
        const col = try allocator.alloc(u8, goal.size * goal.size);
        errdefer allocator.free(col);

        for (goal.tiles, 0..) |tile, pos| {
            row[tile] = @intCast(pos / goal.size);
            col[tile] = @intCast(pos % goal.size);
        }

        return GoalLookup{
            .row = row,
            .col = col,
            .size = goal.size,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GoalLookup) void {
        self.allocator.free(self.row);
        self.allocator.free(self.col);
    }

    pub inline fn getGoalCoords(self: *const GoalLookup, tile: u8) struct { row: usize, col: usize } {
        return .{
            .row = self.row[tile],
            .col = self.col[tile],
        };
    }

    pub inline fn getGoalPos(self: *const GoalLookup, tile: u8) usize {
        return @as(usize, self.row[tile]) * self.size + @as(usize, self.col[tile]);
    }
};

pub fn getHeuristic(htype: HeuristicType) HeuristicFn {
    return switch (htype) {
        .manhattan => manhattanDistance,
        .misplaced_tiles => misplacedTiles,
        .linear_conflict => linearConflict,
    };
}

pub fn manhattanDistance(state: *const State, goal_lookup: *const GoalLookup) u32 {
    assert(state.size == goal_lookup.size);

    var total: u32 = 0;
    var current_row: usize = 0;
    var current_col: usize = 0;

    for (state.tiles) |tile| {
        if (tile != 0) {
            const goal_row = goal_lookup.row[tile];
            const goal_col = goal_lookup.col[tile];

            const row_distance = if (current_row > goal_row) current_row - goal_row else goal_row - current_row;
            const col_distance = if (current_col > goal_col) current_col - goal_col else goal_col - current_col;
            total += @intCast(row_distance + col_distance);
        }

        current_col += 1;
        if (current_col == state.size) {
            current_col = 0;
            current_row += 1;
        }
    }

    return total;
}

pub fn misplacedTiles(state: *const State, goal_lookup: *const GoalLookup) u32 {
    assert(state.size == goal_lookup.size);

    var count: u32 = 0;
    var current_position: usize = 0;

    for (state.tiles) |tile| {
        if (tile != 0) {
            const goal_position = goal_lookup.getGoalPos(tile);
            if (current_position != goal_position) {
                count += 1;
            }
        }
        current_position += 1;
    }

    return count;
}

pub fn linearConflict(state: *const State, goal_lookup: *const GoalLookup) u32 {
    assert(state.size == goal_lookup.size);

    var total = manhattanDistance(state, goal_lookup);

    for (0..state.size) |row| {
        total += countRowConflicts(state, goal_lookup, row);
    }
    for (0..state.size) |col| {
        total += countColConflicts(state, goal_lookup, col);
    }

    return total;
}

fn countRowConflicts(state: *const State, goal_lookup: *const GoalLookup, row: usize) u32 {
    var conflicts: u32 = 0;

    for (0..state.size) |col1| {
        const pos1 = row * state.size + col1;
        const tile1 = state.tiles[pos1];
        if (tile1 == 0) continue;

        if (goal_lookup.row[tile1] != row) continue;

        for (col1 + 1..state.size) |col2| {
            const pos2 = row * state.size + col2;
            const tile2 = state.tiles[pos2];
            if (tile2 == 0) continue;

            if (goal_lookup.row[tile2] != row) continue;

            if (goal_lookup.col[tile1] > goal_lookup.col[tile2]) {
                conflicts += 2;
            }
        }
    }
    return conflicts;
}

fn countColConflicts(state: *const State, goal_lookup: *const GoalLookup, col: usize) u32 {
    var conflicts: u32 = 0;

    for (0..state.size) |row1| {
        const pos1 = row1 * state.size + col;
        const tile1 = state.tiles[pos1];
        if (tile1 == 0) continue;

        if (goal_lookup.col[tile1] != col) continue;

        for (row1 + 1..state.size) |row2| {
            const pos2 = row2 * state.size + col;
            const tile2 = state.tiles[pos2];
            if (tile2 == 0) continue;

            if (goal_lookup.col[tile2] != col) continue;

            if (goal_lookup.row[tile1] > goal_lookup.row[tile2]) {
                conflicts += 2;
            }
        }
    }
    return conflicts;
}

test "GoalLookup - basic initialization" {
    const allocator = std.testing.allocator;
    const tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const goal = try State.initFromTiles(allocator, 3, &tiles);
    defer goal.deinit();

    var lookup = try GoalLookup.init(allocator, goal);
    defer lookup.deinit();

    try std.testing.expectEqual(@as(usize, 3), lookup.size);
    try std.testing.expectEqual(@as(usize, 0), lookup.getGoalPos(1));
    try std.testing.expectEqual(@as(usize, 1), lookup.getGoalPos(2));
    try std.testing.expectEqual(@as(usize, 8), lookup.getGoalPos(0));
}

test "GoalLookup - snail pattern" {
    const allocator = std.testing.allocator;
    const tiles = [_]u8{ 1, 2, 3, 8, 0, 4, 7, 6, 5 };
    const goal = try State.initFromTiles(allocator, 3, &tiles);
    defer goal.deinit();

    var lookup = try GoalLookup.init(allocator, goal);
    defer lookup.deinit();

    try std.testing.expectEqual(@as(usize, 0), lookup.getGoalPos(1));
    try std.testing.expectEqual(@as(usize, 2), lookup.getGoalPos(3));
    try std.testing.expectEqual(@as(usize, 4), lookup.getGoalPos(0));
    try std.testing.expectEqual(@as(usize, 8), lookup.getGoalPos(5));
}

test "Manhattan distance - solved state is 0" {
    const allocator = std.testing.allocator;
    const tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const state = try State.initFromTiles(allocator, 3, &tiles);
    defer state.deinit();
    var lookup = try GoalLookup.init(allocator, state);
    defer lookup.deinit();

    try std.testing.expectEqual(@as(u32, 0), manhattanDistance(state, &lookup));
}

test "Manhattan distance - one move away" {
    const allocator = std.testing.allocator;
    const goal_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const curr_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 0, 8 };
    const goal = try State.initFromTiles(allocator, 3, &goal_tiles);
    defer goal.deinit();
    const state = try State.initFromTiles(allocator, 3, &curr_tiles);
    defer state.deinit();
    var lookup = try GoalLookup.init(allocator, goal);
    defer lookup.deinit();

    try std.testing.expectEqual(@as(u32, 1), manhattanDistance(state, &lookup));
}

test "Misplaced tiles - counts correctly" {
    const allocator = std.testing.allocator;
    const goal_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const curr_tiles = [_]u8{ 1, 2, 3, 4, 0, 6, 7, 5, 8 };
    const goal = try State.initFromTiles(allocator, 3, &goal_tiles);
    defer goal.deinit();
    const state = try State.initFromTiles(allocator, 3, &curr_tiles);
    defer state.deinit();
    var lookup = try GoalLookup.init(allocator, goal);
    defer lookup.deinit();

    try std.testing.expectEqual(@as(u32, 2), misplacedTiles(state, &lookup));
}

test "Linear conflict - detects row conflicts" {
    const allocator = std.testing.allocator;
    const goal_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const curr_tiles = [_]u8{ 2, 1, 3, 4, 5, 6, 7, 8, 0 };
    const goal = try State.initFromTiles(allocator, 3, &goal_tiles);
    defer goal.deinit();
    const state = try State.initFromTiles(allocator, 3, &curr_tiles);
    defer state.deinit();
    var lookup = try GoalLookup.init(allocator, goal);
    defer lookup.deinit();

    try std.testing.expectEqual(@as(u32, 4), linearConflict(state, &lookup));
}

test "HeuristicType.fromString" {
    try std.testing.expectEqual(HeuristicType.manhattan, HeuristicType.fromString("manhattan").?);
    try std.testing.expectEqual(HeuristicType.misplaced_tiles, HeuristicType.fromString("misplaced").?);
    try std.testing.expectEqual(HeuristicType.linear_conflict, HeuristicType.fromString("linear").?);
    try std.testing.expect(HeuristicType.fromString("invalid") == null);
}
