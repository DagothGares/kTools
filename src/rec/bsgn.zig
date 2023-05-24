//BSGN flags (generic, FNAM, NPCS, TNAM, DESC)
//    NAME indexes
//    FNAM offsets
//    TNAM offsets
//    DESC offsets
//    counts NPCS
//        offsets

const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

deleted: bool,
FNAM: []const u8 = undefined,
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
    var NAME: ?[]const u8 = null;

    var meta: struct {
        FNAM: bool = false,
    } = .{};

    var new_NPCS: std.ArrayListUnmanaged([]const u8) = .{};
    defer new_NPCS.deinit(allocator);

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_BSGN.deleted = true,
            .NAME => {
                if (NAME != null) return error.SubrecordRedeclared;

                NAME = subrecord.payload;
            },
            .FNAM => {
                if (meta.FNAM) return error.SubrecordRedeclared;
                meta.FNAM = true;

                new_BSGN.FNAM = subrecord.payload;
            },
            inline .TNAM, .DESC => |known| {
                const tag = @tagName(known);
                if (@field(new_BSGN, tag) != null) return error.SubrecordRedeclared;

                @field(new_BSGN, tag) = subrecord.payload;
            },
            .NPCS => {
                const end: usize = std.mem.indexOf(u8, subrecord.payload, "\x00") orelse
                    subrecord.payload.len; // strips end null byte, if there is one

                try new_NPCS.append(allocator, subrecord.payload[0..end]);
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    if (NAME) |name| {
        inline for (std.meta.fields(@TypeOf(meta))) |field| {
            if (!@field(meta, field.name)) {
                if (new_BSGN.deleted) {
                    if (record_map.getPtr(name)) |existing| existing.deleted = true;
                    return;
                }
                return error.MissingRequiredSubrecord;
            }
        }

        if (record_map.get(name)) |bsgn| if (bsgn.NPCS) |NPCS| allocator.free(NPCS);

        if (new_NPCS.items.len > 0) new_BSGN.NPCS = try new_NPCS.toOwnedSlice(allocator);
        errdefer if (new_BSGN.NPCS) |npcs| allocator.free(npcs);

        return record_map.put(allocator, name, new_BSGN);
    } else return error.MissingRequiredSubrecord;
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(BSGN),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
