const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const RIDT = @import("shared.zig").__DT;

flag: u2,
MODL: []const u8 = undefined,
RIDT: RIDT = undefined,
FNAM: ?[]const u8 = null,
ITEX: ?[]const u8 = null,
SCRI: ?[]const u8 = null,

const REPA = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(REPA),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_REPA: REPA = .{ .flag = util.truncateRecordFlag(flag) };
    var NAME: ?[]const u8 = null;

    var meta: struct {
        MODL: bool = false,
        RIDT: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_REPA.flag |= 0x1,
            .NAME => {
                if (NAME != null) return error.SubrecordRedeclared;

                NAME = subrecord.payload;
            },
            .MODL => {
                if (meta.MODL) return error.SubrecordRedeclared;
                meta.MODL = true;

                new_REPA.MODL = subrecord.payload;
            },
            .RIDT => {
                if (meta.RIDT) return error.SubrecordRedeclared;
                meta.RIDT = true;

                new_REPA.RIDT = try util.getLittle(RIDT, subrecord.payload);
            },
            inline .FNAM, .ITEX, .SCRI => |known| {
                const tag = @tagName(known);
                if (@field(new_REPA, tag) != null) return error.SubrecordRedeclared;

                @field(new_REPA, tag) = subrecord.payload;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    if (NAME) |name| {
        inline for (std.meta.fields(@TypeOf(meta))) |field| {
            if (!@field(meta, field.name)) {
                if (new_REPA.flag & 0x1 != 0) {
                    if (record_map.getPtr(name)) |existing| existing.flag |= 0x1;
                    return;
                }
                return error.MissingRequiredSubrecord;
            }
        }

        return record_map.put(allocator, name, new_REPA);
    } else return error.MissingRequiredSubrecord;
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(REPA),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
