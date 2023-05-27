//BOOK flags (is_deleted, persistent, FNAM, SCRI, ITEX, TEXT, ENAM, is_scroll, has_skill)
//    NAME indexes
//    MODL offsets
//    BKDT weights (f32)
//    BKDT values (u32)
//    BKDT flags (bool(?) from u32)
//    BKDT skillIDs (i7 from i32)
//    BKDT enchantPts (u32)
//    FNAM offsets
//    SCRI offsets
//    ITEX offsets
//    TEXT offsets
//    ENAM offsets

const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const BKDT = extern struct {
    weight: f32 align(1) = 0,
    value: u32 align(1) = 0,
    flags: u32 align(1) = 0,
    skill_id: i32 align(1) = 0, // amusing side effect:
    enchant_points: u32 align(1) = 0,
};

flag: u2,
BKDT: BKDT = .{},
MODL: ?[]const u8 = null,
FNAM: ?[]const u8 = null,
SCRI: ?[]const u8 = null,
ITEX: ?[]const u8 = null,
TEXT: ?[]const u8 = null,
ENAM: ?[]const u8 = null,

const BOOK = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(BOOK),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_BOOK: BOOK = .{ .flag = util.truncateRecordFlag(flag) };
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
            .DELE => new_BOOK.flag |= 0x1,
            .NAME => NAME = subrecord.payload,
            .MODL => new_BOOK.MODL = subrecord.payload,
            .BKDT => new_BOOK.BKDT = try util.getLittle(BKDT, subrecord.payload),
            inline .FNAM, .SCRI, .ITEX, .TEXT, .ENAM => |known| {
                @field(new_BOOK, @tagName(known)) = subrecord.payload;
            },
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    return record_map.put(allocator, NAME, new_BOOK);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(BOOK),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
