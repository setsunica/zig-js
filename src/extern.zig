const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const js = @import("main.zig");

// This is the API that must be provided by the host environment. For
// testing we mock it out so that we can test a well-behaved system.
pub usingnamespace if (!builtin.is_test) struct {
    extern "zig-js" fn valueGet(id: u64, n: usize, len: usize) u64;
    extern "zig-js" fn valueSet(id: u64, n: usize, len: usize, value: u64) void;
    extern "zig-js" fn valueObjectCreate() u64;
    extern "zig-js" fn valueStringCreate(addr: [*]const u8, len: u64) u64;
    extern "zig-js" fn valueStringLen(id: u64) u64;
    extern "zig-js" fn valueStringCopy(id: u64, addr: *u8, max: u64) void;
    extern "zig-js" fn valueDeinit(id: u64) void;
} else struct {
    const alloc = std.testing.allocator;

    /// This is what we store in our array list so that we can manage
    /// memory correctly even in tests.
    const StoredValue = union(enum) {
        string: []const u8,
        object: std.StringHashMapUnmanaged(u64),

        pub fn deinit(self: StoredValue) void {
            switch (self) {
                .string => |v| alloc.free(v),
                .object => |v| {
                    var it = v.iterator();
                    while (it.next()) |entry| {
                        alloc.free(entry.key_ptr.*);
                    }

                    // It doesn't matter that we copy this becaus we
                    // should never reuse values.
                    var copy = v;
                    copy.deinit(alloc);
                },
            }
        }
    };

    /// Mimics the JS style values array except we never reuse IDs
    /// since we're testing and don't plan on overflowing 32-bits.
    var values: std.ArrayListUnmanaged(StoredValue) = .{};

    pub fn deinit() void {
        // Note: we don't deinit the value items here so we can test
        // that we deinit properly in our tests.

        values.deinit(alloc);
        values = .{};
    }

    pub fn valueGet(id: u64, addr: [*]const u8, len: u64) u64 {
        const obj = &values.items[id].object;
        const key = addr[0..len];
        return obj.get(key) orelse @bitCast(u64, js.Ref.null);
    }

    pub fn valueSet(id: u64, addr: [*]const u8, len: u64, value: u64) void {
        const obj = &values.items[id].object;
        const key = alloc.dupe(u8, addr[0..len]) catch unreachable;
        obj.put(alloc, key, value) catch unreachable;
    }

    pub fn valueObjectCreate() u64 {
        values.append(alloc, .{ .object = .{} }) catch unreachable;
        const ref: js.Ref = .{ .type_id = .object, .id = @intCast(u32, values.items.len - 1) };
        return @bitCast(u64, ref);
    }

    pub fn valueStringCreate(addr: [*]const u8, len: u64) u64 {
        // Copy the value
        const copy = alloc.dupe(u8, addr[0..len]) catch unreachable;

        // Write it
        values.append(alloc, .{ .string = copy }) catch unreachable;

        // Create the ref
        const ref: js.Ref = .{ .type_id = .string, .id = @intCast(u32, values.items.len - 1) };
        return @bitCast(u64, ref);
    }

    pub fn valueStringLen(id: u64) u64 {
        return values.items[id].string.len;
    }

    pub fn valueStringCopy(id: u64, addr: [*]u8, max: u64) void {
        std.mem.copy(u8, addr[0..max], values.items[id].string);
    }

    pub fn valueDeinit(id: u64) void {
        values.items[id].deinit();
    }
};