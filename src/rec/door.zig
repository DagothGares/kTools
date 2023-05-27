const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

flag: u2,
MODL: ?[]const u8 = null,
FNAM: ?[]const u8 = null,
SCRI: ?[]const u8 = null,
SNAM: ?[]const u8 = null,
ANAM: ?[]const u8 = null,

const DOOR = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(DOOR),
    record: []const u8,
    start: u32,
    flag: u32,
) !void {
    var new_DOOR: DOOR = .{ .flag = util.truncateRecordFlag(flag) };
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
            .DELE => new_DOOR.flag |= 0x1,
            .NAME => NAME = subrecord.payload,
            inline .MODL, .FNAM, .SCRI, .SNAM, .ANAM => |known| {
                const tag = @tagName(known);
                if (@field(new_DOOR, tag) != null) return error.SubrecordRedeclared;

                @field(new_DOOR, tag) = subrecord.payload;
            },
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    return record_map.put(allocator, NAME, new_DOOR);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(DOOR),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
