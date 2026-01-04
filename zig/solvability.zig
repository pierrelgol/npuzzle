const std = @import("std");
const assert = std.debug.assert;
const state_mod = @import("state.zig");
const State = state_mod.State;

pub fn isSolvable(state: *const State, goal: *const State) bool {
    assert(state.size == goal.size);
    assert(state.size > 0);

    const state_inversions = countInversions(state);
    const goal_inversions = countInversions(goal);

    const is_odd_size = state.size % 2 == 1;

    if (is_odd_size) {
        const state_parity = state_inversions % 2;
        const goal_parity = goal_inversions % 2;
        return state_parity == goal_parity;
    }

    const state_empty_row = state.empty_pos / state.size;
    const goal_empty_row = goal.empty_pos / goal.size;
    const state_empty_row_from_bottom = state.size - 1 - state_empty_row;
    const goal_empty_row_from_bottom = state.size - 1 - goal_empty_row;

    const state_parity = (state_inversions + state_empty_row_from_bottom) % 2;
    const goal_parity = (goal_inversions + goal_empty_row_from_bottom) % 2;

    return state_parity == goal_parity;
}

pub fn countInversions(state: *const State) usize {
    assert(state.size > 0);

    var count: usize = 0;

    for (state.tiles, 0..) |tile1, i| {
        if (tile1 == 0) continue;

        for (state.tiles[i + 1 ..]) |tile2| {
            if (tile2 == 0) continue;
            if (tile1 > tile2) {
                count += 1;
            }
        }
    }
    return count;
}

pub fn validatePuzzle(state: *const State) !void {
    const total_tiles = state.size * state.size;
    const max_tiles = state_mod.MAX_SIZE * state_mod.MAX_SIZE;

    if (total_tiles > max_tiles) {
        return error.InvalidSize;
    }

    var tile_seen = std.mem.zeroes([256]bool);

    for (state.tiles) |tile| {
        if (tile >= total_tiles) {
            return error.InvalidTileValue;
        }

        if (tile_seen[tile]) {
            return error.DuplicateTile;
        }

        tile_seen[tile] = true;
    }

    for (0..total_tiles) |expected_tile| {
        if (!tile_seen[expected_tile]) {
            return error.MissingTile;
        }
    }
}

test "countInversions - solved state has 0 inversions" {
    const allocator = std.testing.allocator;
    const tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const state = try State.initFromTiles(allocator, 3, &tiles);
    defer state.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), countInversions(state));
}

test "countInversions - one inversion" {
    const allocator = std.testing.allocator;
    const tiles = [_]u8{ 2, 1, 3, 4, 5, 6, 7, 8, 0 };
    const state = try State.initFromTiles(allocator, 3, &tiles);
    defer state.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), countInversions(state));
}

test "countInversions - multiple inversions" {
    const allocator = std.testing.allocator;
    const tiles = [_]u8{ 3, 2, 1, 4, 5, 6, 7, 8, 0 };
    const state = try State.initFromTiles(allocator, 3, &tiles);
    defer state.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), countInversions(state));
}

test "countInversions - completely reversed" {
    const allocator = std.testing.allocator;
    const tiles = [_]u8{ 8, 7, 6, 5, 4, 3, 2, 1, 0 };
    const state = try State.initFromTiles(allocator, 3, &tiles);
    defer state.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 28), countInversions(state));
}

test "countInversions - empty tile doesn't affect inversions" {
    const allocator = std.testing.allocator;
    const tiles1 = [_]u8{ 2, 1, 3, 4, 5, 6, 7, 8, 0 };
    const tiles2 = [_]u8{ 0, 2, 1, 3, 4, 5, 6, 7, 8 };

    const state1 = try State.initFromTiles(allocator, 3, &tiles1);
    defer state1.deinit(allocator);

    const state2 = try State.initFromTiles(allocator, 3, &tiles2);
    defer state2.deinit(allocator);

    try std.testing.expectEqual(countInversions(state1), countInversions(state2));
}

test "isSolvable - 3x3 solved state is solvable" {
    const allocator = std.testing.allocator;
    const tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const state = try State.initFromTiles(allocator, 3, &tiles);
    defer state.deinit(allocator);

    try std.testing.expect(isSolvable(state, state));
}

test "isSolvable - 3x3 solvable puzzle" {
    const allocator = std.testing.allocator;
    const goal_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const goal = try State.initFromTiles(allocator, 3, &goal_tiles);
    defer goal.deinit(allocator);

    const state_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 0, 7, 8 };
    const state = try State.initFromTiles(allocator, 3, &state_tiles);
    defer state.deinit(allocator);

    try std.testing.expect(isSolvable(state, goal));
}

test "isSolvable - 3x3 unsolvable puzzle (odd inversion)" {
    const allocator = std.testing.allocator;
    const goal_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const goal = try State.initFromTiles(allocator, 3, &goal_tiles);
    defer goal.deinit(allocator);

    const state_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 8, 7, 0 };
    const state = try State.initFromTiles(allocator, 3, &state_tiles);
    defer state.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), countInversions(goal));
    try std.testing.expectEqual(@as(usize, 1), countInversions(state));
    try std.testing.expect(!isSolvable(state, goal));
}

test "isSolvable - 3x3 snail goal pattern solvable" {
    const allocator = std.testing.allocator;
    const goal_tiles = [_]u8{ 1, 2, 3, 8, 0, 4, 7, 6, 5 };
    const goal = try State.initFromTiles(allocator, 3, &goal_tiles);
    defer goal.deinit(allocator);

    const state_tiles = [_]u8{ 1, 2, 3, 8, 4, 0, 7, 6, 5 };
    const state = try State.initFromTiles(allocator, 3, &state_tiles);
    defer state.deinit(allocator);

    try std.testing.expect(isSolvable(state, goal));
}

test "isSolvable - 4x4 even puzzle solvable" {
    const allocator = std.testing.allocator;
    const goal_tiles = [_]u8{
        1,  2,  3,  4,
        5,  6,  7,  8,
        9,  10, 11, 12,
        13, 14, 15, 0,
    };
    const goal = try State.initFromTiles(allocator, 4, &goal_tiles);
    defer goal.deinit(allocator);

    const state_tiles = [_]u8{
        1,  2,  3,  4,
        5,  6,  7,  8,
        9,  10, 11, 12,
        13, 14, 0,  15,
    };
    const state = try State.initFromTiles(allocator, 4, &state_tiles);
    defer state.deinit(allocator);

    try std.testing.expect(isSolvable(state, goal));
}

test "isSolvable - 4x4 even puzzle unsolvable" {
    const allocator = std.testing.allocator;
    const goal_tiles = [_]u8{
        1,  2,  3,  4,
        5,  6,  7,  8,
        9,  10, 11, 12,
        13, 14, 15, 0,
    };
    const goal = try State.initFromTiles(allocator, 4, &goal_tiles);
    defer goal.deinit(allocator);

    const state_tiles = [_]u8{
        1,  2,  3,  4,
        5,  6,  7,  8,
        9,  10, 11, 12,
        13, 15, 14, 0,
    };
    const state = try State.initFromTiles(allocator, 4, &state_tiles);
    defer state.deinit(allocator);

    try std.testing.expect(!isSolvable(state, goal));
}

test "validatePuzzle - valid puzzle passes" {
    const allocator = std.testing.allocator;
    const tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const state = try State.initFromTiles(allocator, 3, &tiles);
    defer state.deinit(allocator);

    try validatePuzzle(state);
}

test "validatePuzzle - duplicate tile fails" {
    const allocator = std.testing.allocator;
    const tiles = [_]u8{ 1, 1, 3, 4, 5, 6, 7, 8, 0 };
    const state = try State.initFromTiles(allocator, 3, &tiles);
    defer state.deinit(allocator);

    try std.testing.expectError(error.DuplicateTile, validatePuzzle(state));
}

test "validatePuzzle - tile out of range fails" {
    const allocator = std.testing.allocator;
    const state = try State.init(allocator, 3);
    defer state.deinit(allocator);

    @memset(state.tiles, 0);
    state.tiles[0] = 99;

    try std.testing.expectError(error.InvalidTileValue, validatePuzzle(state));
}

test "validatePuzzle - missing tile fails" {
    const allocator = std.testing.allocator;
    const state = try State.init(allocator, 3);
    defer state.deinit(allocator);

    const tiles = [_]u8{ 0, 1, 2, 3, 4, 6, 7, 8, 8 };
    @memcpy(state.tiles, &tiles);

    try std.testing.expectError(error.DuplicateTile, validatePuzzle(state));
}

test "Solvability invariants - swapping tiles changes parity" {
    const allocator = std.testing.allocator;
    const goal_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const goal = try State.initFromTiles(allocator, 3, &goal_tiles);
    defer goal.deinit(allocator);

    const solvable_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const solvable_state = try State.initFromTiles(allocator, 3, &solvable_tiles);
    defer solvable_state.deinit(allocator);

    const unsolvable_tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 8, 7, 0 };
    const unsolvable_state = try State.initFromTiles(allocator, 3, &unsolvable_tiles);
    defer unsolvable_state.deinit(allocator);

    try std.testing.expect(isSolvable(solvable_state, goal));
    try std.testing.expect(!isSolvable(unsolvable_state, goal));
}
