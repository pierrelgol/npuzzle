const std = @import("std");
const assert = std.debug.assert;
const state_mod = @import("state.zig");
const State = state_mod.State;
const solver = @import("solver.zig");
const Solution = solver.Solution;
const Statistics = solver.Statistics;
const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn parseInputFile(allocator: Allocator, io: Io, file_path: []const u8) !*State {
    const file_content = try Io.Dir.cwd().readFileAlloc(io, file_path, allocator, .limited(1024 * 1024));
    defer allocator.free(file_content);

    var size: ?usize = null;
    var tiles: std.ArrayList(u8) = .empty;
    defer tiles.deinit(allocator);

    var line_iter = std.mem.splitScalar(u8, file_content, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (size == null) {
            size = try std.fmt.parseInt(usize, trimmed, 10);
            if (size.? < 3 or size.? > state_mod.MAX_SIZE) return error.InvalidSize;
            try tiles.ensureTotalCapacity(allocator, size.? * size.?);
        } else {
            var iter = std.mem.tokenizeAny(u8, trimmed, " \t");
            while (iter.next()) |num_str| {
                const num = try std.fmt.parseInt(u8, num_str, 10);
                try tiles.append(allocator, num);
            }
        }
    }

    const s = size orelse return error.MissingSize;
    if (tiles.items.len != s * s) return error.InvalidDimensions;

    const state = try State.initFromTiles(allocator, s, tiles.items);
    state.validateInvariants();

    return state;
}

pub fn printState(writer: anytype, state: *const State) !void {
    const max_val = state.size * state.size - 1;
    const width = std.fmt.count("{d}", .{max_val});

    for (0..state.size) |row| {
        for (0..state.size) |col| {
            const tile = state.tiles[row * state.size + col];

            if (col > 0) try writer.writeByte(' ');

            const tile_str = try std.fmt.allocPrint(
                state.allocator,
                "{d}",
                .{tile},
            );
            defer state.allocator.free(tile_str);

            const padding = width - tile_str.len;
            for (0..padding) |_| {
                try writer.writeByte(' ');
            }

            try writer.writeAll(tile_str);
        }
        try writer.writeByte('\n');
    }
}

pub fn printSolution(writer: anytype, solution: *const Solution) !void {
    const stats = solution.stats;

    try writer.print("Solution found!\n\n", .{});

    try writer.print("Time complexity: {d} states selected\n", .{stats.states_selected});
    try writer.print("Space complexity: {d} max states in memory\n", .{stats.max_states_in_memory});
    try writer.print("Solution length: {d} moves\n\n", .{stats.solution_length});

    try writer.print("Solution path:\n", .{});
    try writer.print("{s}\n", .{"=" ** 50});

    for (solution.path, 0..) |state, i| {
        try writer.print("\nStep {d}:\n", .{i});
        try printState(writer, state);
    }

    try writer.print("\n{s}\n", .{"=" ** 50});
}

pub fn printUnsolvable(writer: anytype) !void {
    try writer.print("This puzzle is unsolvable.\n", .{});
}

pub fn printStatistics(writer: anytype, stats: *const Statistics) !void {
    try writer.print("Time complexity: {d}\n", .{stats.states_selected});
    try writer.print("Space complexity: {d}\n", .{stats.max_states_in_memory});
    try writer.print("Solution length: {d}\n", .{stats.solution_length});
}

test "parseInputFile - valid file" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    var dir = tmp_dir.dir;
    defer tmp_dir.cleanup();

    const content =
        \\# Test puzzle
        \\3
        \\1 2 3
        \\4 5 6
        \\7 8 0
    ;

    try dir.writeFile(.{ .sub_path = "test.txt", .data = content });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp_dir.dir.realpath("test.txt", &path_buf);

    const state = try parseInputFile(allocator, path);
    defer state.deinit();

    try std.testing.expectEqual(@as(usize, 3), state.size);
    try std.testing.expectEqual(@as(usize, 8), state.empty_pos);
    try std.testing.expectEqual(@as(u8, 1), state.tiles[0]);
    try std.testing.expectEqual(@as(u8, 0), state.tiles[8]);
}

test "parseInputFile - with comments and whitespace" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    var dir = tmp_dir.dir;
    defer tmp_dir.cleanup();

    const content =
        \\# This is a comment
        \\# Another comment
        \\3
        \\  1  2  3
        \\# Comment in the middle
        \\  4  5  6
        \\  7  8  0
        \\
    ;

    try dir.writeFile(.{ .sub_path = "test.txt", .data = content });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp_dir.dir.realpath("test.txt", &path_buf);

    const state = try parseInputFile(allocator, path);
    defer state.deinit();

    try std.testing.expectEqual(@as(usize, 3), state.size);
    try std.testing.expectEqual(@as(u8, 1), state.tiles[0]);
}

test "parseInputFile - 4x4 puzzle" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    var dir = tmp_dir.dir;
    defer tmp_dir.cleanup();

    const content =
        \\4
        \\1 2 3 4
        \\5 6 7 8
        \\9 10 11 12
        \\13 14 15 0
    ;

    try dir.writeFile(.{ .sub_path = "test.txt", .data = content });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp_dir.dir.realpath("test.txt", &path_buf);

    const state = try parseInputFile(allocator, path);
    defer state.deinit();

    try std.testing.expectEqual(@as(usize, 4), state.size);
    try std.testing.expectEqual(@as(usize, 16), state.tiles.len);
    try std.testing.expectEqual(@as(usize, 15), state.empty_pos);
}

test "parseInputFile - invalid dimensions" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    var dir = tmp_dir.dir;
    defer tmp_dir.cleanup();

    const content =
        \\3
        \\1 2 3
        \\4 5 6
        \\7 8
    ;

    try dir.writeFile(.{ .sub_path = "test.txt", .data = content });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp_dir.dir.realpath("test.txt", &path_buf);

    try std.testing.expectError(error.InvalidDimensions, parseInputFile(allocator, path));
}

test "parseInputFile - no empty tile" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    var dir = tmp_dir.dir;
    defer tmp_dir.cleanup();

    const content =
        \\3
        \\1 2 3
        \\4 5 6
        \\7 8 9
    ;

    try dir.writeFile(.{ .sub_path = "test.txt", .data = content });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp_dir.dir.realpath("test.txt", &path_buf);

    try std.testing.expectError(error.NoEmptyTile, parseInputFile(allocator, path));
}

test "parseInputFile - size too small" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    var dir = tmp_dir.dir;
    defer tmp_dir.cleanup();

    const content =
        \\2
        \\1 2
        \\3 0
    ;

    try dir.writeFile(.{ .sub_path = "test.txt", .data = content });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp_dir.dir.realpath("test.txt", &path_buf);

    try std.testing.expectError(error.InvalidSize, parseInputFile(allocator, path));
}

const ArrayListWriter = struct {
    list: *std.ArrayListUnmanaged(u8),
    allocator: Allocator,

    fn writeAll(self: *ArrayListWriter, bytes: []const u8) !void {
        try self.list.appendSlice(self.allocator, bytes);
    }

    fn writeByte(self: *ArrayListWriter, byte: u8) !void {
        try self.list.append(self.allocator, byte);
    }

    fn print(self: *ArrayListWriter, comptime fmt: []const u8, args: anytype) !void {
        var buf: [1024]u8 = undefined;
        const rendered = try std.fmt.bufPrint(&buf, fmt, args);
        try self.writeAll(rendered);
    }
};

test "printState - formats correctly" {
    const allocator = std.testing.allocator;

    const tiles = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 0 };
    const state = try State.initFromTiles(allocator, 3, &tiles);
    defer state.deinit();

    var output: std.ArrayListUnmanaged(u8) = .{};
    defer output.deinit(allocator);

    var writer = ArrayListWriter{ .list = &output, .allocator = allocator };

    try printState(&writer, state);

    const expected =
        \\1 2 3
        \\4 5 6
        \\7 8 0
        \\
    ;

    try std.testing.expectEqualStrings(expected, output.items);
}

test "printState - aligns numbers correctly" {
    const allocator = std.testing.allocator;

    const tiles = [_]u8{
        1,  2,  3,  4,
        5,  6,  7,  8,
        9,  10, 11, 12,
        13, 14, 15, 0,
    };
    const state = try State.initFromTiles(allocator, 4, &tiles);
    defer state.deinit();

    var output: std.ArrayListUnmanaged(u8) = .{};
    defer output.deinit(allocator);

    var writer = ArrayListWriter{ .list = &output, .allocator = allocator };

    try printState(&writer, state);

    var lines = std.mem.splitScalar(u8, output.items, '\n');
    var line_count: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        line_count += 1;
    }

    try std.testing.expectEqual(@as(usize, 4), line_count);
}

test "printStatistics - formats correctly" {
    const allocator = std.testing.allocator;

    const stats = Statistics{
        .states_selected = 42,
        .max_states_in_memory = 15,
        .solution_length = 7,
    };

    var output: std.ArrayListUnmanaged(u8) = .{};
    defer output.deinit(allocator);

    var writer = ArrayListWriter{ .list = &output, .allocator = allocator };

    try printStatistics(&writer, &stats);

    try std.testing.expect(std.mem.indexOf(u8, output.items, "Time complexity: 42") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "Space complexity: 15") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "Solution length: 7") != null);
}

test "printUnsolvable - prints message" {
    const allocator = std.testing.allocator;

    var output: std.ArrayListUnmanaged(u8) = .{};
    defer output.deinit(allocator);

    var writer = ArrayListWriter{ .list = &output, .allocator = allocator };

    try printUnsolvable(&writer);

    try std.testing.expect(std.mem.indexOf(u8, output.items, "unsolvable") != null);
}
