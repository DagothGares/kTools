//BODY flags (generic)
//    NAME indexes
//    MODL offsets
//    FNAM offsets
//    BYDT parts (u8)
//    BYDT flags {
//        vampire: bool
//        female: bool
//        playable: bool
//        partType: u2
//    } (u5 from [3]u8)

const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const BYDT = extern struct {
    body_part: u8 = 0,
    vampire: u8 = 0,
    flags: u8 = 0,
    part_type: u8 = 0,
};

deleted: bool,
BYDT: BYDT = .{},
MODL: ?[]const u8 = null,
FNAM: ?[]const u8 = null,

const BODY = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(BODY),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_BODY: BODY = .{ .deleted = util.truncateRecordFlag(flag) & 1 != 0 };
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
            .DELE => new_BODY.deleted = true,
            .NAME => NAME = subrecord.payload,
            inline .MODL, .FNAM => |known| @field(new_BODY, @tagName(known)) = subrecord.payload,
            .BYDT => new_BODY.BYDT = try util.getLittle(BYDT, subrecord.payload),
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    return record_map.put(allocator, NAME, new_BODY);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(BODY),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
