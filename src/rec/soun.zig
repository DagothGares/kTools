const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const DATA = extern struct {
    volume: u8 align(1) = 0,
    min_range: u8 align(1) = 0,
    max_range: u8 align(1) = 0,
};

deleted: bool,
DATA: DATA = .{},
FNAM: ?[]const u8 = null,

const SOUN = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(SOUN),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_SOUN: SOUN = .{ .deleted = util.truncateRecordFlag(flag) & 0x1 != 0 };
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
            .DELE => new_SOUN.deleted = true,
            .NAME => NAME = subrecord.payload,
            .FNAM => new_SOUN.FNAM = subrecord.payload,
            .DATA => new_SOUN.DATA = try util.getLittle(DATA, subrecord.payload),
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    return record_map.put(allocator, NAME, new_SOUN);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(SOUN),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
