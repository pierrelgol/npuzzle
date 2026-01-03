const std = @import("std");
const solver = @import("solver.zig");
const State = @import("state.zig").State;
const GoalLookup = @import("heuristics.zig").GoalLookup;
const HeuristicFn = @import("heuristics.zig").HeuristicFn;
const SearchMode = solver.SearchMode;
const Statistics = solver.Statistics;
const StateHashContext = solver.StateHashContext;
const computeFCost = solver.computeFCost;
const generateSuccessors = solver.generateSuccessors;
const reconstructPath = solver.reconstructPath;

pub fn solveParallel(
    allocator: std.mem.Allocator,
    initial: *State,
    goal: *const State,
    goal_lookup: *const GoalLookup,
    heuristic_fn: HeuristicFn,
    mode: SearchMode,
    thread_count: usize,
) !?solver.Solution {
    if (thread_count <= 1) {
        return solver.solve(allocator, initial, goal, goal_lookup, heuristic_fn, mode);
    }

    var shared_state = try Shared.init(allocator, thread_count);
    defer shared_state.deinit();

    const pooled_initial = try shared_state.queues[0].memory_pool.create(shared_state.queues[0].arena.allocator());
    const pooled_tiles = try shared_state.queues[0].arena.allocator().alloc(u8, initial.size * initial.size);
    @memcpy(pooled_tiles, initial.tiles);
    pooled_initial.* = initial.*;
    pooled_initial.tiles = pooled_tiles;
    initial.deinit(allocator);

    pooled_initial.g_cost = 0;
    pooled_initial.h_cost = if (mode == .uniform_cost) 0 else heuristic_fn(pooled_initial, goal_lookup);
    pooled_initial.f_cost = computeFCost(mode, pooled_initial.g_cost, pooled_initial.h_cost);
    pooled_initial.parent = null;
    pooled_initial.validateInvariants();
    try shared_state.addToOpen(0, pooled_initial, 0);

    const worker_threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(worker_threads);

    for (worker_threads, 0..) |*thread, thread_index| {
        thread.* = try std.Thread.spawn(.{}, worker, .{
            &shared_state,
            goal,
            goal_lookup,
            heuristic_fn,
            mode,
            thread_index,
        });
    }

    for (worker_threads) |thread| thread.join();

    if (shared_state.best_state.load(.seq_cst)) |best_pooled_state| {
        var final_closed_set = std.HashMap(*const State, void, StateHashContext, 80).init(allocator);
        errdefer {
            var closed_iter = final_closed_set.keyIterator();
            while (closed_iter.next()) |state_ptr| {
                const state: *State = @constCast(state_ptr.*);
                state.deinit(allocator);
            }
            final_closed_set.deinit();
        }

        var pooled_path: std.ArrayList(*const State) = .empty;
        defer pooled_path.deinit(allocator);
        var current_state: ?*const State = best_pooled_state;
        while (current_state) |state| {
            try pooled_path.insert(allocator, 0, state);
            current_state = state.parent;
        }

        const final_path = try allocator.alloc(*const State, pooled_path.items.len);
        errdefer allocator.free(final_path);

        var previous_cloned_state: ?*State = null;
        for (pooled_path.items, 0..) |pooled_state, index| {
            const cloned_state = try pooled_state.clone(allocator);
            cloned_state.parent = previous_cloned_state;
            final_path[index] = cloned_state;
            try final_closed_set.put(cloned_state, {});
            previous_cloned_state = cloned_state;
        }

        return solver.Solution{
            .path = final_path,
            .stats = .{
                .states_selected = shared_state.states_selected.load(.seq_cst),
                .max_states_in_memory = shared_state.max_states.load(.seq_cst),
                .solution_length = final_path.len - 1,
            },
            .allocator = allocator,
            .closed_set = final_closed_set,
        };
    }

    return null;
}

const PriorityQueueNode = struct {
    state: *State,
    owner_index: usize,

    fn compareFn(context: void, a: PriorityQueueNode, b: PriorityQueueNode) std.math.Order {
        _ = context;
        if (a.state.f_cost < b.state.f_cost) return .lt;
        if (a.state.f_cost > b.state.f_cost) return .gt;
        if (a.state.h_cost < b.state.h_cost) return .lt;
        if (a.state.h_cost > b.state.h_cost) return .gt;
        return .eq;
    }
};

const ThreadQueue = struct {
    priority_queue: std.PriorityQueue(PriorityQueueNode, void, PriorityQueueNode.compareFn),
    mutex: std.Thread.Mutex = .{},
    open_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    arena: std.heap.ArenaAllocator,
    memory_pool: std.heap.MemoryPool(State),

    fn init(allocator: std.mem.Allocator) ThreadQueue {
        const arena = std.heap.ArenaAllocator.init(allocator);
        return .{
            .priority_queue = std.PriorityQueue(PriorityQueueNode, void, PriorityQueueNode.compareFn).init(allocator, {}),
            .arena = arena,
            .memory_pool = .{ .arena_state = .{}, .free_list = .{} },
        };
    }

    fn deinit(self: *ThreadQueue) void {
        self.priority_queue.deinit();
        self.memory_pool.deinit(self.arena.allocator());
        self.arena.deinit();
    }
};

const SHARD_COUNT: usize = 16;

const ClosedShard = struct {
    map: std.HashMap(*const State, void, StateHashContext, 80),
    mutex: std.Thread.Mutex = .{},

    fn init(allocator: std.mem.Allocator) ClosedShard {
        return .{ .map = std.HashMap(*const State, void, StateHashContext, 80).init(allocator) };
    }

    fn deinit(self: *ClosedShard) void {
        self.map.deinit();
    }
};

const Shared = struct {
    allocator: std.mem.Allocator,
    queues: []ThreadQueue,
    closed_shards: [SHARD_COUNT]ClosedShard,
    closed_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    states_selected: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    max_states: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    best_cost: std.atomic.Value(u32) = std.atomic.Value(u32).init(std.math.maxInt(u32)),
    best_state: std.atomic.Value(?*const State) = std.atomic.Value(?*const State).init(null),
    min_f_values: []std.atomic.Value(u32),
    stop_flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    fn init(allocator: std.mem.Allocator, threads: usize) !Shared {
        const queues = try allocator.alloc(ThreadQueue, threads);
        for (queues) |*q| {
            q.* = ThreadQueue.init(allocator);
        }
        const min_f_values = try allocator.alloc(std.atomic.Value(u32), threads);
        for (min_f_values) |*v| v.* = std.atomic.Value(u32).init(std.math.maxInt(u32));

        return .{
            .allocator = allocator,
            .queues = queues,
            .closed_shards = .{ClosedShard.init(allocator)} ** SHARD_COUNT,
            .min_f_values = min_f_values,
        };
    }

    fn deinit(self: *Shared) void {
        for (self.queues) |*q| q.deinit();
        self.allocator.free(self.queues);
        self.allocator.free(self.min_f_values);
        for (&self.closed_shards) |*s| s.deinit();
    }

    fn addToOpen(self: *Shared, queue_index: usize, state: *State, owner_index: usize) !void {
        var queue = &self.queues[queue_index % self.queues.len];
        queue.mutex.lock();
        defer queue.mutex.unlock();
        try queue.priority_queue.add(.{ .state = state, .owner_index = owner_index });
        _ = queue.open_count.fetchAdd(1, .seq_cst);
        self.updateMaxMemory();
    }

    fn updateMaxMemory(self: *Shared) void {
        var total_open_states: usize = 0;
        for (self.queues) |*queue| {
            total_open_states += queue.open_count.load(.seq_cst);
        }
        const current_total_states = total_open_states + self.closed_count.load(.seq_cst);
        _ = self.max_states.fetchMax(current_total_states, .seq_cst);
    }

    fn releaseToPool(self: *Shared, owner_index: usize, state: *State) void {
        var queue = &self.queues[owner_index];
        queue.mutex.lock();
        queue.memory_pool.destroy(state);
        queue.mutex.unlock();
    }
};

fn worker(
    shared: *Shared,
    goal: *const State,
    goal_lookup: *const GoalLookup,
    heuristic_fn: HeuristicFn,
    mode: SearchMode,
    worker_index: usize,
) void {
    const thread_count = shared.queues.len;
    const STEAL_BATCH_SIZE = 16;
    var work_steal_buffer: [STEAL_BATCH_SIZE]PriorityQueueNode = undefined;

    while (!shared.stop_flag.load(.seq_cst)) {
        var maybe_node: ?PriorityQueueNode = null;

        {
            var my_queue = &shared.queues[worker_index];
            my_queue.mutex.lock();
            maybe_node = my_queue.priority_queue.removeOrNull();
            if (maybe_node) |node| {
                _ = my_queue.open_count.fetchSub(1, .seq_cst);
                shared.min_f_values[worker_index].store(node.state.f_cost, .seq_cst);
            } else {
                shared.min_f_values[worker_index].store(std.math.maxInt(u32), .seq_cst);
            }
            my_queue.mutex.unlock();
        }

        if (maybe_node == null) {
            for (0..thread_count) |offset| {
                const victim_index = (worker_index + 1 + offset) % thread_count;
                if (victim_index == worker_index) continue;

                var victim_queue = &shared.queues[victim_index];
                if (victim_queue.open_count.load(.acquire) == 0) continue;

                var stolen_count: usize = 0;
                if (victim_queue.mutex.tryLock()) {
                    while (stolen_count < STEAL_BATCH_SIZE) {
                        if (victim_queue.priority_queue.removeOrNull()) |node| {
                            _ = victim_queue.open_count.fetchSub(1, .seq_cst);
                            work_steal_buffer[stolen_count] = node;
                            stolen_count += 1;
                        } else {
                            break;
                        }
                    }
                    victim_queue.mutex.unlock();
                }

                if (stolen_count > 0) {
                    maybe_node = work_steal_buffer[0];
                    shared.min_f_values[worker_index].store(maybe_node.?.state.f_cost, .seq_cst);

                    if (stolen_count > 1) {
                        var my_queue = &shared.queues[worker_index];
                        my_queue.mutex.lock();
                        for (work_steal_buffer[1..stolen_count]) |stolen_node| {
                            my_queue.priority_queue.add(stolen_node) catch {
                                my_queue.mutex.unlock();
                                shared.releaseToPool(stolen_node.owner_index, stolen_node.state);
                                my_queue.mutex.lock();
                                continue;
                            };
                            _ = my_queue.open_count.fetchAdd(1, .seq_cst);
                        }
                        shared.updateMaxMemory();
                        my_queue.mutex.unlock();
                    }
                    break;
                }
            }
        }

        const node = maybe_node orelse {
            var all_queues_empty = true;
            for (shared.min_f_values) |*min_f_value| {
                if (min_f_value.load(.seq_cst) != std.math.maxInt(u32)) {
                    all_queues_empty = false;
                    break;
                }
            }
            if (all_queues_empty) break;
            _ = std.Thread.yield() catch {};
            continue;
        };

        _ = shared.states_selected.fetchAdd(1, .seq_cst);

        const current_best_cost = shared.best_cost.load(.seq_cst);
        if (current_best_cost != std.math.maxInt(u32) and node.state.f_cost >= current_best_cost) {
            shared.releaseToPool(node.owner_index, node.state);
            continue;
        }

        var should_skip = false;
        const shard_index = node.state.hash() % SHARD_COUNT;
        var shard = &shared.closed_shards[shard_index];
        shard.mutex.lock();
        if (shard.map.contains(node.state)) {
            should_skip = true;
        } else {
            shard.map.put(node.state, {}) catch {
                should_skip = true;
            };
            if (!should_skip) {
                _ = shared.closed_count.fetchAdd(1, .seq_cst);
            }
        }
        shard.mutex.unlock();

        if (should_skip) {
            shared.releaseToPool(node.owner_index, node.state);
            continue;
        }

        if (node.state.eql(goal)) {
            const goal_cost = node.state.g_cost;
            const previous_best = shared.best_cost.fetchMin(goal_cost, .seq_cst);
            if (goal_cost <= previous_best) {
                _ = shared.best_state.swap(node.state, .seq_cst);
            }
            shared.min_f_values[worker_index].store(std.math.maxInt(u32), .seq_cst);
            if (shared.best_cost.load(.seq_cst) == goal_cost) {
                shared.stop_flag.store(true, .seq_cst);
            }
            continue;
        }

        const successors = generateSuccessors(
            shared.allocator,
            node.state,
            goal_lookup,
            heuristic_fn,
            mode,
        ) catch {
            continue;
        };
        defer shared.allocator.free(successors);

        for (successors) |successor_base| {
            const current_best_cost2 = shared.best_cost.load(.seq_cst);
            if (current_best_cost2 != std.math.maxInt(u32) and successor_base.f_cost >= current_best_cost2) {
                successor_base.deinit(shared.allocator);
                continue;
            }

            const successor_shard_index = successor_base.hash() % SHARD_COUNT;
            var successor_shard = &shared.closed_shards[successor_shard_index];
            successor_shard.mutex.lock();
            const is_already_closed = successor_shard.map.contains(successor_base);
            successor_shard.mutex.unlock();

            if (is_already_closed) {
                successor_base.deinit(shared.allocator);
                continue;
            }

            var my_queue = &shared.queues[worker_index];
            my_queue.mutex.lock();
            const pooled_successor = my_queue.memory_pool.create(my_queue.arena.allocator()) catch {
                my_queue.mutex.unlock();
                successor_base.deinit(shared.allocator);
                continue;
            };
            const pooled_tiles = my_queue.arena.allocator().alloc(u8, successor_base.size * successor_base.size) catch {
                my_queue.memory_pool.destroy(pooled_successor);
                my_queue.mutex.unlock();
                successor_base.deinit(shared.allocator);
                continue;
            };
            @memcpy(pooled_tiles, successor_base.tiles);
            pooled_successor.* = successor_base.*;
            pooled_successor.tiles = pooled_tiles;
            successor_base.deinit(shared.allocator);

            my_queue.priority_queue.add(.{ .state = pooled_successor, .owner_index = worker_index }) catch {
                my_queue.memory_pool.destroy(pooled_successor);
                my_queue.mutex.unlock();
                continue;
            };
            _ = my_queue.open_count.fetchAdd(1, .seq_cst);
            shared.updateMaxMemory();
            my_queue.mutex.unlock();
        }
    }
}
