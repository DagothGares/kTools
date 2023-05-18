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
    body_part: u8,
    vampire: u8,
    flags: u8,
    part_type: u8,
};

pub const BODY = struct {
    deleted: bool,
    MODL: []const u8 = undefined,
    FNAM: []const u8 = undefined,
    BYDT: BYDT = undefined,
};

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
    var NAME: []const u8 = undefined;

    var meta: struct {
        NAME: bool = false,
        MODL: bool = false,
        FNAM: bool = false,
        BYDT: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_BODY.deleted = true,
            .NAME => {
                if (meta.NAME) return error.SubrecordRedeclared;
                meta.NAME = true;

                NAME = subrecord.payload;
            },
            inline .MODL, .FNAM => |known| {
                const tag = @tagName(known);
                if (@field(meta, tag)) return error.SubrecordRedeclared;
                @field(meta, tag) = true;

                @field(new_BODY, tag) = subrecord.payload;
            },
            .BYDT => {
                if (meta.BYDT) return error.SubrecordRedeclared;
                meta.BYDT = true;

                new_BODY.BYDT = util.getLittle(BYDT, subrecord.payload);
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    inline for (std.meta.fields(@TypeOf(meta))) |field| {
        if (!@field(meta, field.name)) return error.MissingRequiredSubrecord;
    }

    try record_map.put(allocator, NAME, new_BODY);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(BODY),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
