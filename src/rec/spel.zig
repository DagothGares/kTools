const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const ENAM = @import("shared.zig").ENAM;

const SPDT = extern struct {
    spell_type: u32 align(1),
    cost: u32 align(1),
    flags: u32 align(1),
};

deleted: bool,
SPDT: SPDT = undefined,
FNAM: ?[]const u8 = null,
ENAM: ?[]ENAM = null,

const SPEL = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(SPEL),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_SPEL: SPEL = .{ .deleted = util.truncateRecordFlag(flag) & 0x1 != 0 };
    var NAME: ?[]const u8 = null;

    var meta: struct {
        SPDT: bool = false,
    } = .{};

    var new_ENAM: std.ArrayListUnmanaged(ENAM) = .{};
    defer new_ENAM.deinit(allocator);

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_SPEL.deleted = true,
            .NAME => {
                if (NAME != null) return error.SubrecordRedeclared;

                NAME = subrecord.payload;
            },
            .SPDT => {
                if (meta.SPDT) return error.SubrecordRedeclared;
                meta.SPDT = true;

                new_SPEL.SPDT = util.getLittle(SPDT, subrecord.payload);
            },
            .FNAM => {
                if (new_SPEL.FNAM != null) return error.SubrecordRedeclared;

                new_SPEL.FNAM = subrecord.payload;
            },
            .ENAM => try new_ENAM.append(allocator, util.getLittle(ENAM, subrecord.payload)),
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    if (NAME) |name| {
        inline for (std.meta.fields(@TypeOf(meta))) |field| {
            if (!@field(meta, field.name)) {
                if (new_SPEL.deleted) {
                    if (record_map.getPtr(name)) |existing| existing.deleted = true;
                    return;
                }
                return error.MissingRequiredSubrecord;
            }
        }

        if (record_map.get(name)) |spel| if (spel.ENAM) |enam| allocator.free(enam);

        if (new_ENAM.items.len > 0) new_SPEL.ENAM = try new_ENAM.toOwnedSlice(allocator);
        errdefer if (new_SPEL.ENAM) |enam| allocator.free(enam);

        return record_map.put(allocator, name, new_SPEL);
    } else return error.MissingRequiredSubrecord;
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(SPEL),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
