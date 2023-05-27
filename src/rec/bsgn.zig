const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

deleted: bool,
FNAM: ?[]const u8 = null,
TNAM: ?[]const u8 = null,
DESC: ?[]const u8 = null,
NPCS: ?[][]const u8 = null,

const BSGN = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(BSGN),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_BSGN: BSGN = .{ .deleted = util.truncateRecordFlag(flag) & 1 != 0 };
    var NAME: []const u8 = "";

    var new_NPCS: std.ArrayListUnmanaged([]const u8) = .{};
    defer new_NPCS.deinit(allocator);

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
            .DELE => new_BSGN.deleted = true,
            .NAME => NAME = subrecord.payload,
            inline .FNAM, .TNAM, .DESC => |known| {
                @field(new_BSGN, @tagName(known)) = subrecord.payload;
            },
            .NPCS => {
                const end: usize = std.mem.indexOf(u8, subrecord.payload, "\x00") orelse
                    subrecord.payload.len; // strips end null byte, if there is one

                try new_NPCS.append(allocator, subrecord.payload[0..end]);
            },
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    if (record_map.get(NAME)) |bsgn| if (bsgn.NPCS) |NPCS| allocator.free(NPCS);

    if (new_NPCS.items.len > 0) new_BSGN.NPCS = try new_NPCS.toOwnedSlice(allocator);
    errdefer if (new_BSGN.NPCS) |npcs| allocator.free(npcs);

    return record_map.put(allocator, NAME, new_BSGN);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(BSGN),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
