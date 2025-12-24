const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const MAX_SIZE: usize = 16;

pub const State = struct {
    tiles_storage: [MAX_SIZE * MAX_SIZE]u8,
    tiles: []u8,
    size: usize,
    empty_pos: usize,
    g_cost: u32,
    h_cost: u32,
    f_cost: u32,
    parent: ?*const State,
    allocator: Allocator,

    pub fn init(allocator: Allocator, size: usize) !*State {
        assert(size > 0);
        if (size > MAX_SIZE) return error.InvalidSize;

        const state = try allocator.create(State);
        errdefer allocator.destroy(state);

        state.* = .{
            .tiles_storage = undefined,
            .tiles = undefined,
            .size = size,
            .empty_pos = 0,
            .g_cost = 0,
            .h_cost = 0,
            .f_cost = 0,
            .parent = null,
            .allocator = allocator,
        };

        @memset(&state.tiles_storage, 0);
        state.tiles = state.tiles_storage[0 .. size * size];

        return state;
    }

    pub fn initFromTiles(allocator: Allocator, size: usize, tiles: []const u8) !*State {
        assert(size > 0);
        if (size > MAX_SIZE) return error.InvalidSize;
        assert(tiles.len == size * size);

        const state = try init(allocator, size);
        errdefer state.deinit();

        @memcpy(state.tiles, tiles);

        state.empty_pos = std.mem.indexOfScalar(u8, state.tiles, 0) orelse return error.NoEmptyTile;

        state.validateInvariants();
        return state;
    }

    pub fn validateInvariants(self: *const State) void {
        assert(self.size > 0);
        assert(self.tiles.len == self.size * self.size);
        assert(self.empty_pos < self.tiles.len);
        assert(self.tiles[self.empty_pos] == 0);
        for (self.tiles) |tile| assert(tile < self.size * self.size);
    }

    pub fn deinit(self: *State) void {
        self.allocator.destroy(self);
    }

    pub fn clone(self: *const State) !*State {
        const new_state = try init(self.allocator, self.size);
        errdefer new_state.deinit();

        @memcpy(new_state.tiles, self.tiles);
        new_state.empty_pos = self.empty_pos;
        new_state.g_cost = self.g_cost;
        new_state.h_cost = self.h_cost;
        new_state.f_cost = self.f_cost;
        new_state.parent = self.parent;

        new_state.validateInvariants();
        return new_state;
    }

    pub fn hash(self: *const State) u64 {
        return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(self.tiles));
    }

    pub fn eql(self: *const State, other: *const State) bool {
        if (self.size != other.size) return false;
        if (self.empty_pos != other.empty_pos) return false;
        return std.mem.eql(u8, self.tiles, other.tiles);
    }

    pub inline fn setCosts(self: *State, g: u32, h: u32) void {
        self.g_cost = g;
        self.h_cost = h;
        self.f_cost = g + h;
    }

    pub inline fn getCoords(self: *const State, pos: usize) struct { row: usize, col: usize } {
        return .{
            .row = pos / self.size,
            .col = pos % self.size,
        };
    }

    pub inline fn getPos(self: *const State, row: usize, col: usize) usize {
        return row * self.size + col;
    }
};

test "State.init - basic initialization" {
    const allocator = std.testing.allocator;

    const state = try State.init(allocator, 3);
    defer state.deinit();

    try std.testing.expectEqual(@as(usize, 3), state.size);
    try std.testing.expectEqual(@as(usize, 9), state.tiles.len);
    try std.testing.expectEqual(@as(u32, 0), state.g_cost);
    try std.testing.expectEqual(@as(u32, 0), state.h_cost);
    try std.testing.expectEqual(@as(u32, 0), state.f_cost);
    try std.testing.expect(state.parent == null);
}

test "State.initFromTiles - valid puzzle" {
    const allocator = std.testing.allocator;

    const tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const state = try State.initFromTiles(allocator, 3, &tiles);
    defer state.deinit();

    try std.testing.expectEqual(@as(usize, 3), state.size);
    try std.testing.expectEqual(@as(usize, 8), state.empty_pos);
    try std.testing.expectEqualSlices(u8, &tiles, state.tiles);
    state.validateInvariants();
}

test "State.initFromTiles - no empty tile returns error" {
    const allocator = std.testing.allocator;
    const tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    try std.testing.expectError(error.NoEmptyTile, State.initFromTiles(allocator, 3, &tiles));
}

test "State.clone - creates independent copy" {
    const allocator = std.testing.allocator;

    const tiles = [_]u8{ 1, 2, 3, 4, 0, 5, 6, 7, 8 };
    const state = try State.initFromTiles(allocator, 3, &tiles);
    defer state.deinit();

    state.setCosts(5, 10);

    const cloned = try state.clone();
    defer cloned.deinit();

    try std.testing.expectEqual(state.size, cloned.size);
    try std.testing.expectEqual(state.empty_pos, cloned.empty_pos);
    try std.testing.expectEqualSlices(u8, state.tiles, cloned.tiles);
    try std.testing.expectEqual(state.g_cost, cloned.g_cost);
    try std.testing.expectEqual(state.h_cost, cloned.h_cost);
    try std.testing.expectEqual(state.f_cost, cloned.f_cost);
    try std.testing.expect(state.tiles.ptr != cloned.tiles.ptr);

    cloned.tiles[0] = 99;
    try std.testing.expectEqual(@as(u8, 1), state.tiles[0]);
    try std.testing.expectEqual(@as(u8, 99), cloned.tiles[0]);
}

test "State.hash - same tiles produce same hash" {
    const allocator = std.testing.allocator;

    const tiles = [_]u8{ 1, 2, 3, 4, 0, 5, 6, 7, 8 };

    const state1 = try State.initFromTiles(allocator, 3, &tiles);
    defer state1.deinit();

    const state2 = try State.initFromTiles(allocator, 3, &tiles);
    defer state2.deinit();

    try std.testing.expectEqual(state1.hash(), state2.hash());
}

test "State.hash - different tiles produce different hash" {
    const allocator = std.testing.allocator;

    const tiles1 = [_]u8{ 1, 2, 3, 4, 0, 5, 6, 7, 8 };
    const tiles2 = [_]u8{ 1, 2, 3, 4, 5, 0, 6, 7, 8 };

    const state1 = try State.initFromTiles(allocator, 3, &tiles1);
    defer state1.deinit();

    const state2 = try State.initFromTiles(allocator, 3, &tiles2);
    defer state2.deinit();

    try std.testing.expect(state1.hash() != state2.hash());
}

test "State.eql - identical states are equal" {
    const allocator = std.testing.allocator;
    const tiles = [_]u8{ 1, 2, 3, 4, 0, 5, 6, 7, 8 };

    const state1 = try State.initFromTiles(allocator, 3, &tiles);
    defer state1.deinit();

    const state2 = try State.initFromTiles(allocator, 3, &tiles);
    defer state2.deinit();

    try std.testing.expect(state1.eql(state2));
    try std.testing.expect(state2.eql(state1));
}

test "State.eql - different states are not equal" {
    const allocator = std.testing.allocator;

    const tiles1 = [_]u8{ 1, 2, 3, 4, 0, 5, 6, 7, 8 };
    const tiles2 = [_]u8{ 1, 2, 3, 4, 5, 0, 6, 7, 8 };

    const state1 = try State.initFromTiles(allocator, 3, &tiles1);
    defer state1.deinit();

    const state2 = try State.initFromTiles(allocator, 3, &tiles2);
    defer state2.deinit();

    try std.testing.expect(!state1.eql(state2));
}

test "State.setCosts - maintains f = g + h invariant" {
    const allocator = std.testing.allocator;

    const tiles = [_]u8{ 1, 2, 3, 4, 0, 5, 6, 7, 8 };
    const state = try State.initFromTiles(allocator, 3, &tiles);
    defer state.deinit();

    state.setCosts(10, 15);

    try std.testing.expectEqual(@as(u32, 10), state.g_cost);
    try std.testing.expectEqual(@as(u32, 15), state.h_cost);
    try std.testing.expectEqual(@as(u32, 25), state.f_cost);
    state.validateInvariants();
}

test "State.getCoords - correct coordinate conversion" {
    const allocator = std.testing.allocator;

    const state = try State.init(allocator, 3);
    defer state.deinit();

    const coords0 = state.getCoords(0);
    try std.testing.expectEqual(@as(usize, 0), coords0.row);
    try std.testing.expectEqual(@as(usize, 0), coords0.col);

    const coords4 = state.getCoords(4);
    try std.testing.expectEqual(@as(usize, 1), coords4.row);
    try std.testing.expectEqual(@as(usize, 1), coords4.col);

    const coords8 = state.getCoords(8);
    try std.testing.expectEqual(@as(usize, 2), coords8.row);
    try std.testing.expectEqual(@as(usize, 2), coords8.col);
}

test "State.getPos - correct position conversion" {
    const allocator = std.testing.allocator;

    const state = try State.init(allocator, 3);
    defer state.deinit();

    try std.testing.expectEqual(@as(usize, 0), state.getPos(0, 0));
    try std.testing.expectEqual(@as(usize, 4), state.getPos(1, 1));
    try std.testing.expectEqual(@as(usize, 8), state.getPos(2, 2));
    try std.testing.expectEqual(@as(usize, 5), state.getPos(1, 2));
}

test "State.getPos and getCoords - are inverse operations" {
    const allocator = std.testing.allocator;

    const state = try State.init(allocator, 3);
    defer state.deinit();

    for (0..9) |pos| {
        const coords = state.getCoords(pos);
        const reconstructed_pos = state.getPos(coords.row, coords.col);
        try std.testing.expectEqual(pos, reconstructed_pos);
    }
}

test "State.validateInvariants - validates correctly" {
    const allocator = std.testing.allocator;
    const tiles = [_]u8{ 1, 2, 3, 4, 0, 5, 6, 7, 8 };
    const state = try State.initFromTiles(allocator, 3, &tiles);
    defer state.deinit();
    state.validateInvariants();
}
