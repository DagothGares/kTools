const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const MCDT = extern struct {
    weight: f32 align(1),
    value: u32 align(1),
};

flag: u2,
MODL: []const u8 = undefined,
MCDT: MCDT = undefined,
FNAM: ?[]const u8 = null,
SCRI: ?[]const u8 = null,
ITEX: ?[]const u8 = null,

const MISC = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(MISC),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_MISC: MISC = .{ .flag = util.truncateRecordFlag(flag) };
    var NAME: ?[]const u8 = null;

    var meta: struct {
        MODL: bool = false,
        MCDT: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_MISC.flag |= 0x1,
            .NAME => {
                if (NAME != null) return error.SubrecordRedeclared;

                NAME = subrecord.payload;
            },
            .MODL => {
                if (meta.MODL) return error.SubrecordRedeclared;
                meta.MODL = true;

                new_MISC.MODL = subrecord.payload;
            },
            .MCDT => {
                if (meta.MCDT) return error.SubrecordRedeclared;
                meta.MCDT = true;

                new_MISC.MCDT = try util.getLittle(MCDT, subrecord.payload);
            },
            inline .FNAM, .SCRI, .ITEX => |known| {
                const tag = @tagName(known);
                if (@field(new_MISC, tag) != null) return error.SubrecordRedeclared;

                @field(new_MISC, tag) = subrecord.payload;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    if (NAME) |name| {
        inline for (std.meta.fields(@TypeOf(meta))) |field| {
            if (!@field(meta, field.name)) {
                if (new_MISC.flag & 0x1 != 0) {
                    if (record_map.getPtr(name)) |existing| existing.flag |= 0x1;
                    return;
                }
                return error.MissingRequiredSubrecord;
            }
        }

        return record_map.put(allocator, name, new_MISC);
    } else return error.MissingRequiredSubrecord;
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(MISC),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
