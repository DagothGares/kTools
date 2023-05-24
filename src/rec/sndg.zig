const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

flag: u2,
DATA: u32 = undefined,
CNAM: ?[]const u8 = null,
SNAM: ?[]const u8 = null,

const SNDG = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(SNDG),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_SNDG: SNDG = .{ .flag = util.truncateRecordFlag(flag) };
    var NAME: ?[]const u8 = null;

    var meta: struct {
        DATA: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_SNDG.flag |= 0x1,
            .NAME => {
                if (NAME != null) return error.SubrecordRedeclared;

                NAME = subrecord.payload;
            },
            .DATA => {
                if (meta.DATA) return error.SubrecordRedeclared;
                meta.DATA = true;

                new_SNDG.DATA = try util.getLittle(u32, subrecord.payload);
            },
            inline .CNAM, .SNAM => |known| {
                const tag = @tagName(known);
                if (@field(new_SNDG, tag) != null) return error.SubrecordRedeclared;

                @field(new_SNDG, tag) = subrecord.payload;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    if (NAME) |name| {
        inline for (std.meta.fields(@TypeOf(meta))) |field| {
            if (!@field(meta, field.name)) {
                if (new_SNDG.flag & 0x1 != 0) {
                    if (record_map.getPtr(name)) |existing| existing.flag |= 0x1;
                    return;
                }
                return error.MissingRequiredSubrecord;
            }
        }

        return record_map.put(allocator, name, new_SNDG);
    } else return error.MissingRequiredSubrecord;
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(SNDG),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
