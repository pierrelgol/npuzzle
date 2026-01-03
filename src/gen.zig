const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const GeneratorError = error{
    InvalidSize,
    ConflictingOptions,
    MissingArgument,
    InvalidNumber,
};

const Options = struct {
    size: usize,
    solvable: ?bool = null,
    iterations: usize = 10000,
};

pub const Puzzle = struct {
    grid: []u8,
    size: usize,
    allocator: Allocator,
    is_solvable: bool = false,

    pub fn init(allocator: Allocator, size: usize) !Puzzle {
        const grid = try allocator.alloc(u8, size * size);
        @memset(grid, 255);
        return Puzzle{
            .grid = grid,
            .size = size,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Puzzle) void {
        self.allocator.free(self.grid);
    }

    pub fn generateSnail(self: *Puzzle) void {
        var current_value: u8 = 1;
        var x: isize = 0;
        var y: isize = 0;
        var direction_x: isize = 1;
        var direction_y: isize = 0;
        const size_as_isize = @as(isize, @intCast(self.size));
        const max_tile_value = @as(u8, @intCast(self.size * self.size));

        while (true) {
            const index = @as(usize, @intCast(x + y * size_as_isize));
            self.grid[index] = current_value;

            if (current_value == 0) break;

            current_value += 1;
            if (current_value == max_tile_value) {
                current_value = 0;
            }

            const next_x = x + direction_x;
            const next_y = y + direction_y;

            const is_out_of_bounds = next_x < 0 or next_x >= size_as_isize or next_y < 0 or next_y >= size_as_isize;
            const is_cell_filled = if (!is_out_of_bounds) blk: {
                const next_index = @as(usize, @intCast(next_x + next_y * size_as_isize));
                break :blk self.grid[next_index] != 255;
            } else false;

            const should_turn = is_out_of_bounds or is_cell_filled;

            if (should_turn) {
                const temp = direction_x;
                direction_x = -direction_y;
                direction_y = temp;
            }

            x += direction_x;
            y += direction_y;
        }
    }

    pub fn shuffle(self: *Puzzle, iterations: usize, rng: std.Random) void {
        for (0..iterations) |_| {
            self.swapEmptyTile(rng);
        }
    }

    fn swapEmptyTile(self: *Puzzle, rng: std.Random) void {
        const empty_position = std.mem.indexOfScalar(u8, self.grid, 0) orelse return;
        var valid_moves: [4]usize = undefined;
        var valid_move_count: usize = 0;

        const empty_row = empty_position / self.size;
        const empty_col = empty_position % self.size;

        if (empty_col > 0) {
            valid_moves[valid_move_count] = empty_position - 1;
            valid_move_count += 1;
        }
        if (empty_col < self.size - 1) {
            valid_moves[valid_move_count] = empty_position + 1;
            valid_move_count += 1;
        }
        if (empty_row > 0) {
            valid_moves[valid_move_count] = empty_position - self.size;
            valid_move_count += 1;
        }
        if (empty_row < self.size - 1) {
            valid_moves[valid_move_count] = empty_position + self.size;
            valid_move_count += 1;
        }

        if (valid_move_count > 0) {
            const target_position = valid_moves[rng.uintLessThan(usize, valid_move_count)];
            std.mem.swap(u8, &self.grid[empty_position], &self.grid[target_position]);
        }
    }

    pub fn ensureSolvability(self: *Puzzle, should_be_solvable: bool) void {
        if (should_be_solvable) return;

        const last_index = self.grid.len - 1;
        const empty_at_start = self.grid[0] == 0 or self.grid[1] == 0;

        if (empty_at_start) {
            std.mem.swap(u8, &self.grid[last_index], &self.grid[last_index - 1]);
        } else {
            std.mem.swap(u8, &self.grid[0], &self.grid[1]);
        }
    }

    pub fn print(self: Puzzle, writer: *Io.Writer, solvable: bool) !void {
        var buf: [256]u8 = undefined;

        try writer.print("# This puzzle is {s}\n", .{if (solvable) "solvable" else "unsolvable"});

        try writer.print("{d}\n", .{self.size});

        const max_value = self.size * self.size;
        const field_width = std.fmt.count("{d}", .{max_value});

        for (0..self.size) |row| {
            for (0..self.size) |col| {
                const value = self.grid[col + row * self.size];
                if (col > 0) _ = try writer.write(" ");

                const value_str = try std.fmt.bufPrint(&buf, "{d}", .{value});
                const padding = if (field_width > value_str.len) field_width - value_str.len else 0;
                _ = try writer.splatByte(' ', padding);
                _ = try writer.write(value_str);
            }
            _ = try writer.write("\n");
        }
        try writer.flush();
    }
};
