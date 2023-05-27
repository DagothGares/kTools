const std = @import("std");
const builtin = @import("builtin");
const util = @import("../util.zig");

const subs = util.subs;

const ENAM = @import("shared.zig").ENAM;

const ALDT = extern struct {
    weight: f32 align(1) = 0,
    value: u32 align(1) = 0,
    flags: u32 align(1) = 0,
};

flag: u2,
ALDT: ALDT = .{},
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
    var NAME: []const u8 = "";

    var new_ENAM: std.ArrayListUnmanaged(ENAM) = .{};
    defer new_ENAM.deinit(allocator);

    var iterator: util.SubrecordIterator = .{
        .stream = std.io.fixedBufferStream(record),
        .pos_offset = start,
    };

    while (iterator.next()) |subrecord| {
        const sub_tag = try util.parseSub(
            logger,
            subrecord.tag,
            subrecord.pos,
            plugin_name,
        ) orelse continue;

        switch (sub_tag) {
            .DELE => new_ALCH.flag |= 0x1,
            .NAME => NAME = subrecord.payload,
            .ALDT => new_ALCH.ALDT = try util.getLittle(ALDT, subrecord.payload),
            inline .MODL, .TEXT, .SCRI, .FNAM => |known| {
                @field(new_ALCH, @tagName(known)) = subrecord.payload;
            },
            .ENAM => try new_ENAM.append(allocator, try util.getLittle(ENAM, subrecord.payload)),
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    if (record_map.get(NAME)) |indx| if (indx.ENAM) |e| allocator.free(e);
    errdefer if (new_ALCH.ENAM) |enam| allocator.free(enam);

    return record_map.put(allocator, NAME, new_ALCH);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(ALCH),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
