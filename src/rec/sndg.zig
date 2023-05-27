const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

flag: u2,
DATA: u32 = 0,
CNAM: ?[]const u8 = null,
SNAM: ?[]const u8 = null,

const SNDG = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(SNDG),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_SNDG: SNDG = .{ .flag = util.truncateRecordFlag(flag) };
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
            .DELE => new_SNDG.flag |= 0x1,
            .NAME => NAME = subrecord.payload,
            .DATA => new_SNDG.DATA = try util.getLittle(u32, subrecord.payload),
            inline .CNAM, .SNAM => |known| {
                @field(new_SNDG, @tagName(known)) = subrecord.payload;
            },
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    return record_map.put(allocator, NAME, new_SNDG);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(SNDG),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
