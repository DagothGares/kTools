const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const RADT = extern struct {
    skill_bonuses: [7]extern struct {
        id: i32 align(1) = 0,
        modifier: i32 align(1) = 0,
    } align(1) = .{.{}} ** 7,
    attributes: [8][2]u32 align(1) = [_][2]u32{.{ 0, 0 }} ** 8,
    height: [2]f32 align(1) = [_]f32{0} ** 2,
    weight: [2]f32 align(1) = [_]f32{0} ** 2,
    flags: u32 align(1) = 0,
};

deleted: bool,
RADT: RADT = .{},
FNAM: ?[]const u8 = null,
DESC: ?[]const u8 = null,
NPCS: ?[][]const u8 = null,

const RACE = @This();

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
            .DELE => new_RACE.deleted = true,
            .NAME => NAME = subrecord.payload,
            .RADT => new_RACE.RADT = try util.getLittle(RADT, subrecord.payload),
            inline .FNAM, .DESC => |known| {
                @field(new_RACE, @tagName(known)) = subrecord.payload;
            },
            .NPCS => try new_NPCS.append(allocator, subrecord.payload),
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    if (record_map.get(NAME)) |race| if (race.NPCS) |npcs| allocator.free(npcs);

    if (new_NPCS.items.len > 0) new_RACE.NPCS = try new_NPCS.toOwnedSlice(allocator);
    errdefer if (new_RACE.NPCS) |npcs| allocator.free(npcs);

    return record_map.put(allocator, NAME, new_RACE);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(RACE),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
