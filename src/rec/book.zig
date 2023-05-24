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
    weight: f32 align(1),
    value: u32 align(1),
    flags: u32 align(1),
    skill_id: i32 align(1),
    enchant_points: u32 align(1),
};

flag: u2,
MODL: []const u8 = undefined,
BKDT: BKDT = undefined,
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
    var NAME: ?[]const u8 = null;

    var meta: struct {
        MODL: bool = false,
        BKDT: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_BOOK.flag |= 0x1,
            .NAME => {
                if (NAME != null) return error.SubrecordRedeclared;

                NAME = subrecord.payload;
            },
            .MODL => {
                if (meta.MODL) return error.SubrecordRedeclared;
                meta.MODL = true;

                new_BOOK.MODL = subrecord.payload;
            },
            .BKDT => {
                if (meta.BKDT) return error.SubrecordRedeclared;
                meta.BKDT = true;

                new_BOOK.BKDT = try util.getLittle(BKDT, subrecord.payload);
            },
            inline .FNAM, .SCRI, .ITEX, .TEXT, .ENAM => |known| {
                const tag = @tagName(known);
                if (@field(new_BOOK, tag) != null) return error.SubrecordRedeclared;

                @field(new_BOOK, tag) = subrecord.payload;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    if (NAME) |name| {
        inline for (std.meta.fields(@TypeOf(meta))) |field| {
            if (!@field(meta, field.name)) {
                if (new_BOOK.flag & 0x1 != 0) {
                    if (record_map.getPtr(name)) |existing| existing.flag |= 0x1;
                    return;
                }
                return error.MissingRequiredSubrecord;
            }
        }

        return record_map.put(allocator, name, new_BOOK);
    } else return error.MissingRequiredSubrecord;
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(BOOK),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
