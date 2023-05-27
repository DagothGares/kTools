const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const INFO = @import("info.zig");

deleted: bool,
DATA: u8 = 0,
// TODO: this should probably just be a linked list instead
INFO: std.StringArrayHashMapUnmanaged(INFO) = .{},

const DIAL = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(DIAL),
    record: []const u8,
    start: u64,
    flag: u32,
) !*DIAL {
    var new_DIAL: DIAL = .{ .deleted = util.truncateRecordFlag(flag) & 0x1 != 0 };
    var NAME: []const u8 = "";

    var iterator: util.SubrecordIterator = .{
        .stream = std.io.fixedBufferStream(record),
        .pos_offset = start,
    };

    while (iterator.next()) |subrecord| {
        const sub_tag = try util.parseSub(
            logger,
            subrecord.tag,
            subrecord.pos,
            plugin_name,
        ) orelse continue;

        switch (sub_tag) {
            .DELE => new_DIAL.deleted = true,
            .NAME => NAME = subrecord.payload,
            .DATA => new_DIAL.DATA = subrecord.payload[0],
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    const dial = try record_map.getOrPut(allocator, NAME);
    const ptr = dial.value_ptr;

    ptr.deleted = new_DIAL.deleted;
    ptr.DATA = new_DIAL.DATA;
    if (!dial.found_existing) ptr.INFO = .{};

    return ptr;
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(DIAL),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 10, .{
        .{"INFO"},
    }, INFO.writeAll);
}
