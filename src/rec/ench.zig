const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const ENAM = @import("shared.zig").ENAM;

const ENDT = extern struct {
    enchantment_type: u32 align(1),
    cost: u32 align(1),
    charge: u32 align(1),
    flags: u32 align(1),
};

deleted: bool,
ENDT: ENDT = undefined,
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
    var NAME: []const u8 = undefined;

    var meta: struct {
        NAME: bool = false,
        ENDT: bool = false,
    } = .{};

    var new_ENAM: std.ArrayListUnmanaged(ENAM) = .{};
    defer new_ENAM.deinit(allocator);

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_ENCH.deleted = true,
            .NAME => {
                if (meta.NAME) return error.SubrecordRedeclared;
                meta.NAME = true;

                NAME = subrecord.payload;
            },
            .ENDT => {
                if (meta.ENDT) return error.SubrecordRedeclared;
                meta.ENDT = true;

                new_ENCH.ENDT = util.getLittle(ENDT, subrecord.payload);
            },
            .ENAM => try new_ENAM.append(allocator, util.getLittle(ENAM, subrecord.payload)),
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    inline for (std.meta.fields(@TypeOf(meta))) |field| {
        if (!@field(meta, field.name)) return error.MissingRequiredSubrecord;
    }

    if (record_map.get(NAME)) |ench| if (ench.ENAM) |enam| allocator.free(enam);

    if (new_ENAM.items.len > 0) new_ENCH.ENAM = try new_ENAM.toOwnedSlice(allocator);
    errdefer if (new_ENCH.ENAM) |enam| allocator.free(enam);

    try record_map.put(allocator, NAME, new_ENCH);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(ENCH),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
