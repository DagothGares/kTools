const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const RADT = extern struct {
    skill_bonuses: [7]extern struct {
        id: i32 align(1),
        modifier: i32 align(1),
    } align(1),
    attributes: [8][2]u32 align(1),
    height: [2]f32 align(1),
    weight: [2]f32 align(1),
    flags: u32 align(1),
};

pub const RACE = struct {
    deleted: bool,
    FNAM: []const u8 = undefined,
    RADT: RADT = undefined,
    DESC: ?[]const u8 = null,
    NPCS: ?[][]const u8 = null,
};

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(RACE),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_RACE: RACE = .{ .deleted = util.truncateRecordFlag(flag) & 0x1 != 0 };
    var NAME: []const u8 = undefined;

    var meta: struct {
        NAME: bool = false,
        FNAM: bool = false,
        RADT: bool = false,
    } = .{};

    var new_NPCS: std.ArrayListUnmanaged([]const u8) = .{};
    defer new_NPCS.deinit(allocator);

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_RACE.deleted = true,
            .NAME => {
                if (meta.NAME) return error.SubrecordRedeclared;
                meta.NAME = true;

                NAME = subrecord.payload;
            },
            .FNAM => {
                if (meta.FNAM) return error.SubrecordRedeclared;
                meta.FNAM = true;

                new_RACE.FNAM = subrecord.payload;
            },
            .RADT => {
                if (meta.RADT) return error.SubrecordRedeclared;
                meta.RADT = true;

                new_RACE.RADT = util.getLittle(RADT, subrecord.payload);
            },
            .DESC => {
                if (new_RACE.DESC != null) return error.SubrecordRedeclared;

                new_RACE.DESC = subrecord.payload;
            },
            .NPCS => try new_NPCS.append(allocator, subrecord.payload),
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    inline for (std.meta.fields(@TypeOf(meta))) |field| {
        if (!@field(meta, field.name)) return error.MissingRequiredSubrecord;
    }

    if (record_map.get(NAME)) |race| if (race.NPCS) |npcs| allocator.free(npcs);

    if (new_NPCS.items.len > 0) new_RACE.NPCS = try new_NPCS.toOwnedSlice(allocator);
    errdefer if (new_RACE.NPCS) |npcs| allocator.free(npcs);

    try record_map.put(allocator, NAME, new_RACE);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(RACE),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
