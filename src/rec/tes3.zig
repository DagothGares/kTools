//ACTI flags (deleted, persist-ref, SCRI)
//    NAME indexes (index of record name strings)
//    MODL offsets (byte offset in plugin)
//    FNAM offsets (byte offset in plugin)
//
//    SCRI offsets (byte offset in plugin)
//        (count determined by total number of flags with SCRI bit set)

const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const HEDR = extern struct {
    version: f32 align(1),
    flags: u32 align(1),
    creator: [32]u8 align(1),
    file_description: [256]u8 align(1),
    num_records: u32 align(1),
};

HEDR: HEDR,
masters: []u32,

const TES3 = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    plugin_index: u32,
    plugin_list: [][]const u8,
    record: []const u8,
) !TES3 {
    var new_TES3: TES3 = undefined;

    var meta: struct {
        HEDR: bool = false,
    } = .{};

    var masters = try std.ArrayListUnmanaged(u32).initCapacity(allocator, 1);
    defer masters.deinit(allocator);
    masters.appendAssumeCapacity(plugin_index);

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, 0)) |subrecord| {
        switch (subrecord.tag) {
            .HEDR => {
                if (meta.HEDR) return error.SubrecordRedeclared;
                meta.HEDR = true;

                new_TES3.HEDR = util.getLittle(HEDR, subrecord.payload);
            },
            .MAST => {
                const should_be_DATA = try iterator.next(logger, plugin_name, 0);
                if (should_be_DATA == null or should_be_DATA.?.tag != .DATA) {
                    return error.MissingRequiredSubrecord;
                }

                const strip_pos = std.mem.indexOf(u8, subrecord.payload, "\x00") orelse subrecord.payload.len;

                const substring = subrecord.payload[0..strip_pos];

                var found = false;
                for (plugin_list, 0..) |name, i| {
                    if (std.ascii.eqlIgnoreCase(substring, name)) {
                        try masters.append(allocator, @intCast(u32, i));
                        found = true;
                    }
                }
                if (!found) return error.MissingMaster;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    if (!meta.HEDR) return error.MissingRequiredSubrecord;

    new_TES3.masters = try masters.toOwnedSlice(allocator);

    return new_TES3;
}
