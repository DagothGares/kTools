const std = @import("std");
const builtin = @import("builtin");
const util = @import("../util.zig");

const subs = util.subs;

const ENAM = @import("shared.zig").ENAM;

// Used to read structs via copying them
const ALDT = extern struct {
    weight: f32 align(1),
    value: u32 align(1),
    flags: u32 align(1),
};

flag: u2,
ALDT: ALDT = undefined,
MODL: ?[]const u8 = null,
TEXT: ?[]const u8 = null,
SCRI: ?[]const u8 = null,
FNAM: ?[]const u8 = null,
ENAM: ?[]ENAM = null,

const ALCH = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(ALCH),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_ALCH: ALCH = .{ .flag = util.truncateRecordFlag(flag) };
    errdefer if (new_ALCH.ENAM) |enam_ptr| allocator.free(enam_ptr);
    var NAME: ?[]const u8 = null;

    var meta: struct {
        ALDT: bool = false,
    } = .{};

    var new_ENAM: std.ArrayListUnmanaged(ENAM) = .{};
    defer new_ENAM.deinit(allocator);

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_ALCH.flag |= 0x1,
            .NAME => {
                if (NAME != null) return error.SubrecordRedeclared;

                NAME = subrecord.payload;
            },
            .ALDT => {
                if (meta.ALDT) return error.SubrecordRedeclared;
                meta.ALDT = true;

                new_ALCH.ALDT = try util.getLittle(ALDT, subrecord.payload);
            },
            inline .MODL, .TEXT, .SCRI, .FNAM => |known| {
                const tag = @tagName(known);
                if (@field(new_ALCH, tag) != null) return error.SubrecordRedeclared;

                @field(new_ALCH, tag) = subrecord.payload;
            },
            .ENAM => try new_ENAM.append(allocator, try util.getLittle(ENAM, subrecord.payload)),
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    if (NAME) |name| {
        inline for (std.meta.fields(@TypeOf(meta))) |field| {
            if (!@field(meta, field.name)) {
                if (new_ALCH.flag & 0x1 != 0) {
                    if (record_map.getPtr(name)) |existing| existing.flag |= 0x1;
                    return;
                }
                return error.MissingRequiredSubrecord;
            }
        }

        if (record_map.get(name)) |indx| if (indx.ENAM) |e| allocator.free(e);
        errdefer if (new_ALCH.ENAM) |enam| allocator.free(enam);

        return record_map.put(allocator, name, new_ALCH);
    } else return error.MissingRequiredSubrecord;
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(ALCH),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
