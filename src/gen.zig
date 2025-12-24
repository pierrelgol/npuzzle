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
                for (0..padding) |_| {
                    _ = try writer.write(" ");
                }
                _ = try writer.write(value_str);
            }
            _ = try writer.write("\n");
        }
    }
};

pub fn fuzzGenerate(allocator: Allocator, input: []const u8) !Puzzle {
    if (input.len < 5) return error.InsufficientFuzzInput;

    const size = @as(usize, @intCast(3 + (input[0] % 3)));

    const solvable: bool = switch (input[1] % 3) {
        0 => false,
        1 => true,
        else => (input[1] & 1) == 1,
    };

    const iterations_raw = @as(u16, input[2]) | (@as(u16, input[3]) << 8);
    const iterations = @min(@as(usize, iterations_raw), 10000);

    var seed: u64 = 0;
    const seed_bytes = if (input.len > 4) input[4..] else input[0..4];
    for (seed_bytes, 0..) |byte, i| {
        seed ^= @as(u64, byte) << @intCast((i % 8) * 8);
    }

    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();

    var puzzle = try Puzzle.init(allocator, size);
    errdefer puzzle.deinit();

    puzzle.generateSnail();
    puzzle.shuffle(iterations, rng);
    puzzle.ensureSolvability(solvable);
    puzzle.is_solvable = solvable;

    return puzzle;
}

pub fn fuzzGenerateSimple(allocator: Allocator, seed_bytes: []const u8) !Puzzle {
    if (seed_bytes.len == 0) return error.InsufficientFuzzInput;

    var seed: u64 = 0;
    for (seed_bytes) |byte| {
        seed = std.math.rotl(u64, seed, 5);
        seed ^= @as(u64, byte);
        seed = seed *% 0x9e3779b97f4a7c15;
    }

    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();

    const size = 3 + (rng.uintLessThan(usize, 3));
    const solvable = rng.boolean();
    const iterations = 100 + rng.uintLessThan(usize, 1000);

    var puzzle = try Puzzle.init(allocator, size);
    errdefer puzzle.deinit();

    puzzle.generateSnail();
    puzzle.shuffle(iterations, rng);
    puzzle.ensureSolvability(solvable);
    puzzle.is_solvable = solvable;

    return puzzle;
}

fn parseArgs(allocator: Allocator) !Options {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) return GeneratorError.MissingArgument;

    var opts = Options{ .size = 0 };
    var size_set = false;
    var solvable_flag = false;
    var unsolvable_flag = false;

    var i: usize = 1;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printUsage();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--solvable")) {
            solvable_flag = true;
        } else if (std.mem.eql(u8, arg, "-u") or std.mem.eql(u8, arg, "--unsolvable")) {
            unsolvable_flag = true;
        } else if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--iterations")) {
            i += 1;
            if (i >= args.len) return GeneratorError.MissingArgument;
            opts.iterations = std.fmt.parseInt(usize, args[i], 10) catch return GeneratorError.InvalidNumber;
        } else {
            if (!size_set) {
                opts.size = std.fmt.parseInt(usize, arg, 10) catch return GeneratorError.InvalidNumber;
                size_set = true;
            } else {
                return GeneratorError.ConflictingOptions;
            }
        }
        i += 1;
    }

    if (!size_set) return GeneratorError.MissingArgument;
    if (solvable_flag and unsolvable_flag) return GeneratorError.ConflictingOptions;
    if (opts.size < 3) return GeneratorError.InvalidSize;

    if (solvable_flag) opts.solvable = true;
    if (unsolvable_flag) opts.solvable = false;

    return opts;
}

fn printUsage() noreturn {
    const usage =
        \\usage: npuzzle-gen [-h] [-s] [-u] [-i ITERATIONS] size
        \\
        \\positional arguments:
        \\  size                   Size of the puzzle's side. Must be >= 3.
        \\
        \\options:
        \\  -h, --help             Show this help message and exit
        \\  -s, --solvable         Force generation of a solvable puzzle
        \\  -u, --unsolvable       Force generation of an unsolvable puzzle
        \\  -i, --iterations <N>   Number of shuffle iterations (default: 10000)
        \\
    ;
    std.debug.print("{s}", .{usage});
    std.process.exit(1);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const opts = parseArgs(allocator) catch |err| {
        switch (err) {
            GeneratorError.ConflictingOptions => std.debug.print("Error: Cannot be both solvable and unsolvable\n", .{}),
            GeneratorError.InvalidSize => std.debug.print("Error: Size must be >= 3\n", .{}),
            GeneratorError.MissingArgument => std.debug.print("Error: Missing required argument\n", .{}),
            GeneratorError.InvalidNumber => std.debug.print("Error: Invalid number format\n", .{}),
            else => std.debug.print("Error: {s}\n", .{@errorName(err)}),
        }
        printUsage();
    };

    var prng = std.Random.DefaultPrng.init(std.crypto.random.int(u64));
    const rng = prng.random();

    const is_solvable = opts.solvable orelse rng.boolean();

    var puzzle = try Puzzle.init(allocator, opts.size);
    defer puzzle.deinit();

    puzzle.generateSnail();
    puzzle.shuffle(opts.iterations, rng);
    puzzle.ensureSolvability(is_solvable);

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout: *Io.Writer = &stdout_writer.interface;

    try puzzle.print(stdout, is_solvable);
}
