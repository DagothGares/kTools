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
    version: f32 align(1) = 1.2,
    flags: u32 align(1) = 0,
    creator: [32]u8 align(1) = [_]u8{0} ** 32,
    file_description: [256]u8 align(1) = [_]u8{0} ** 256,
    // num_records is ignored because Morrowind doesn't even use it
};

HEDR: HEDR = .{},
masters: []u32 = &[_]u32{},

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

    var masters = try std.ArrayListUnmanaged(u32).initCapacity(allocator, 1);
    defer masters.deinit(allocator);
    masters.appendAssumeCapacity(plugin_index);

    var iterator: util.SubrecordIterator = .{
        .stream = std.io.fixedBufferStream(record),
        .pos_offset = 0,
    };

    while (iterator.next()) |subrecord| {
        const sub_tag = try util.parseSub(
            logger,
            subrecord.tag,
            subrecord.pos,
            plugin_name,
        ) orelse continue;

        switch (sub_tag) {
            .HEDR => new_TES3.HEDR = try util.getLittle(HEDR, subrecord.payload),
            .MAST => {
                const pos = iterator.stream.getPos() catch unreachable;
                const next = iterator.next();
                if (next == null or try util.parseSub(
                    logger,
                    next.?.tag,
                    next.?.pos,
                    plugin_name,
                ) orelse .DELE != .DATA) {
                    iterator.stream.seekTo(pos) catch unreachable;
                }

                const strip_pos = std.mem.indexOf(
                    u8,
                    subrecord.payload,
                    "\x00",
                ) orelse subrecord.payload.len;
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
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    new_TES3.masters = try masters.toOwnedSlice(allocator);

    return new_TES3;
}
