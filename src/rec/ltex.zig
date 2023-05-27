const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

deleted: bool,
INTV: u32 = 0,
DATA: ?[]const u8 = null,

const LTEX = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(LTEX),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_LTEX: LTEX = .{ .deleted = util.truncateRecordFlag(flag) & 0x1 != 0 };
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
            .DELE => new_LTEX.deleted = true,
            .NAME => NAME = subrecord.payload,
            .INTV => new_LTEX.INTV = try util.getLittle(u32, subrecord.payload),
            .DATA => new_LTEX.DATA = subrecord.payload,
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    return record_map.put(allocator, NAME, new_LTEX);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(LTEX),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
