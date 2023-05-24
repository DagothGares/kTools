const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const DATA = extern struct {
    volume: u8 align(1),
    min_range: u8 align(1),
    max_range: u8 align(1),
};

deleted: bool,
FNAM: []const u8 = undefined,
DATA: DATA = undefined,

const SOUN = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(SOUN),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_SOUN: SOUN = .{ .deleted = util.truncateRecordFlag(flag) & 0x1 != 0 };
    var NAME: ?[]const u8 = null;

    var meta: struct {
        FNAM: bool = false,
        DATA: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_SOUN.deleted = true,
            .NAME => {
                if (NAME != null) return error.SubrecordRedeclared;

                NAME = subrecord.payload;
            },
            .FNAM => {
                if (meta.FNAM) return error.SubrecordRedeclared;
                meta.FNAM = true;

                new_SOUN.FNAM = subrecord.payload;
            },
            .DATA => {
                if (meta.DATA) return error.SubrecordRedeclared;
                meta.DATA = true;

                new_SOUN.DATA = try util.getLittle(DATA, subrecord.payload);
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    if (NAME) |name| {
        inline for (std.meta.fields(@TypeOf(meta))) |field| {
            if (!@field(meta, field.name)) {
                if (new_SOUN.deleted) {
                    if (record_map.getPtr(name)) |existing| existing.deleted = true;
                    return;
                }
                return error.MissingRequiredSubrecord;
            }
        }

        return record_map.put(allocator, name, new_SOUN);
    } else return error.MissingRequiredSubrecord;
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(SOUN),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
