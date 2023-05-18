const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

pub const ACTI = struct {
    flag: u2,
    MODL: []const u8 = undefined,
    FNAM: []const u8 = undefined,
    SCRI: ?[]const u8 = null,
};

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(ACTI),
    record: []const u8,
    start: u32,
    flag: u32,
) !void {
    var new_ACTI: ACTI = .{ .flag = util.truncateRecordFlag(flag) };
    var NAME: []const u8 = undefined;

    var meta: struct {
        NAME: bool = false,
        MODL: bool = false,
        FNAM: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_ACTI.flag |= 0x1,
            .NAME => {
                if (meta.NAME) return error.SubrecordRedeclared;
                meta.NAME = true;

                NAME = subrecord.payload;
            },
            inline .MODL, .FNAM => |known| {
                const tag = @tagName(known);
                if (@field(meta, tag)) return error.SubrecordRedeclared;
                @field(meta, tag) = true;

                @field(new_ACTI, tag) = subrecord.payload;
            },
            .SCRI => {
                if (new_ACTI.SCRI != null) return error.SubrecordRedeclared;

                new_ACTI.SCRI = subrecord.payload;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    inline for (std.meta.fields(@TypeOf(meta))) |field| {
        if (!@field(meta, field.name)) return error.MissingRequiredSubrecord;
    }

    try record_map.put(allocator, NAME, new_ACTI);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(ACTI),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
