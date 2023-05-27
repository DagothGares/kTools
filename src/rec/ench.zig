const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const ENAM = @import("shared.zig").ENAM;

const ENDT = extern struct {
    enchantment_type: u32 align(1) = 0,
    cost: u32 align(1) = 0,
    charge: u32 align(1) = 0,
    flags: u32 align(1) = 0,
};

deleted: bool,
ENDT: ENDT = .{},
ENAM: ?[]ENAM = null,

const ENCH = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(ENCH),
    record: []const u8,
    start: u32,
    flag: u32,
) !void {
    var new_ENCH: ENCH = .{ .deleted = util.truncateRecordFlag(flag) & 0x1 != 0 };
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
            .DELE => new_ENCH.deleted = true,
            .NAME => NAME = subrecord.payload,
            .ENDT => new_ENCH.ENDT = try util.getLittle(ENDT, subrecord.payload),
            .ENAM => try new_ENAM.append(allocator, try util.getLittle(ENAM, subrecord.payload)),
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    if (record_map.get(NAME)) |ench| if (ench.ENAM) |enam| allocator.free(enam);

    if (new_ENAM.items.len > 0) new_ENCH.ENAM = try new_ENAM.toOwnedSlice(allocator);
    errdefer if (new_ENCH.ENAM) |enam| allocator.free(enam);

    return record_map.put(allocator, NAME, new_ENCH);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(ENCH),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
