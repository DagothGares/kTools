const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

pub const DOOR = struct {
    flag: u2,
    MODL: []const u8 = undefined,
    FNAM: ?[]const u8 = null,
    SCRI: ?[]const u8 = null,
    SNAM: ?[]const u8 = null,
    ANAM: ?[]const u8 = null,
};

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
    var NAME: []const u8 = undefined;

    var meta: struct {
        NAME: bool = false,
        MODL: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_DOOR.flag |= 0x1,
            .NAME => {
                if (meta.NAME) return error.SubrecordRedeclared;
                meta.NAME = true;

                NAME = subrecord.payload;
            },
            .MODL => {
                if (meta.MODL) return error.SubrecordRedeclared;
                meta.MODL = true;

                new_DOOR.MODL = subrecord.payload;
            },
            inline .FNAM, .SCRI, .SNAM, .ANAM => |known| {
                const tag = @tagName(known);
                if (@field(new_DOOR, tag) != null) return error.SubrecordRedeclared;

                @field(new_DOOR, tag) = subrecord.payload;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    inline for (std.meta.fields(@TypeOf(meta))) |field| {
        if (!@field(meta, field.name)) return error.MissingRequiredSubrecord;
    }

    try record_map.put(allocator, NAME, new_DOOR);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(DOOR),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
