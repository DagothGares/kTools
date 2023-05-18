const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const PBDT = @import("shared.zig").__DT;

pub const PROB = struct {
    flag: u2,
    MODL: []const u8 = undefined,
    PBDT: PBDT = undefined,
    FNAM: ?[]const u8 = null,
    ITEX: ?[]const u8 = null,
    SCRI: ?[]const u8 = null,
};

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(PROB),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_PROB: PROB = .{ .flag = util.truncateRecordFlag(flag) };
    var NAME: []const u8 = undefined;

    var meta: struct {
        NAME: bool = false,
        MODL: bool = false,
        PBDT: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_PROB.flag |= 0x1,
            .NAME => {
                if (meta.NAME) return error.SubrecordRedeclared;
                meta.NAME = true;

                NAME = subrecord.payload;
            },
            .MODL => {
                if (meta.MODL) return error.subrecordRedeclared;
                meta.MODL = true;

                new_PROB.MODL = subrecord.payload;
            },
            .PBDT => {
                if (meta.PBDT) return error.SubrecordRedeclared;
                meta.PBDT = true;

                new_PROB.PBDT = util.getLittle(PBDT, subrecord.payload);
            },
            inline .FNAM, .ITEX, .SCRI => |known| {
                const tag = @tagName(known);
                if (@field(new_PROB, tag) != null) return error.SubrecordRedeclared;

                @field(new_PROB, tag) = subrecord.payload;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    inline for (std.meta.fields(@TypeOf(meta))) |field| {
        if (!@field(meta, field.name)) return error.MissingRequiredSubrecord;
    }

    try record_map.put(allocator, NAME, new_PROB);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(PROB),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
