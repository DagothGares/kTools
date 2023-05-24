const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const AADT = extern struct {
    apparatus_type: u32 align(1),
    quality: f32 align(1),
    weight: f32 align(1),
    value: u32 align(1),
};

flag: u2,
MODL: []const u8 = undefined,
FNAM: []const u8 = undefined,
AADT: AADT = undefined,
SCRI: ?[]const u8 = null,
ITEX: ?[]const u8 = null,

const APPA = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(APPA),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_APPA: APPA = .{ .flag = util.truncateRecordFlag(flag) };
    var NAME: ?[]const u8 = null;

    var meta: struct {
        MODL: bool = false,
        FNAM: bool = false,
        AADT: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_APPA.flag |= 0x1,
            .NAME => {
                if (NAME != null) return error.SubrecordRedeclared;

                NAME = subrecord.payload;
            },
            inline .MODL, .FNAM => |known| {
                const tag = @tagName(known);
                if (@field(meta, tag)) return error.SubrecordRedeclared;
                @field(meta, tag) = true;

                @field(new_APPA, tag) = subrecord.payload;
            },
            .AADT => {
                if (meta.AADT) return error.SubrecordRedeclared;
                meta.AADT = true;

                new_APPA.AADT = util.getLittle(AADT, subrecord.payload);
            },
            inline .SCRI, .ITEX => |known| {
                const tag = @tagName(known);
                if (@field(new_APPA, tag) != null) return error.SubrecordRedeclared;

                @field(new_APPA, tag) = subrecord.payload;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    if (NAME) |name| {
        inline for (std.meta.fields(@TypeOf(meta))) |field| {
            if (!@field(meta, field.name)) {
                if (new_APPA.flag & 0x1 != 0) {
                    if (record_map.getPtr(name)) |existing| existing.flag |= 0x1;
                    return;
                }
                return error.MissingRequiredSubrecord;
            }
        }

        return record_map.put(allocator, name, new_APPA);
    } else return error.MissingRequiredSubrecord;
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(APPA),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
