const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const LKDT = @import("shared.zig").__DT;

flag: u2,
LKDT: LKDT = .{},
MODL: ?[]const u8 = null,
FNAM: ?[]const u8 = null,
ITEX: ?[]const u8 = null,
SCRI: ?[]const u8 = null,

const LOCK = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(LOCK),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_LOCK: LOCK = .{ .flag = util.truncateRecordFlag(flag) };
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
            .DELE => new_LOCK.flag |= 0x1,
            .NAME => NAME = subrecord.payload,
            .LKDT => new_LOCK.LKDT = try util.getLittle(LKDT, subrecord.payload),
            inline .MODL, .FNAM, .ITEX, .SCRI => |known| {
                @field(new_LOCK, @tagName(known)) = subrecord.payload;
            },
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    return record_map.put(allocator, NAME, new_LOCK);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(LOCK),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
