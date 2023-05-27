const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const WEAT = struct {
    clear: u8 = 0,
    cloudy: u8 = 0,
    foggy: u8 = 0,
    overcast: u8 = 0,
    rain: u8 = 0,
    thunder: u8 = 0,
    ash: u8 = 0,
    blight: u8 = 0,
    snow: u8 = 0,
    blizzard: u8 = 0,
};

const SNAM = extern struct {
    name: [32]u8 align(1),
    chance: u8 align(1),
};

deleted: bool,
FNAM: ?[]const u8 = null,
CNAM: [4]u8 = [_]u8{0} ** 4,
WEAT: WEAT = .{},
BNAM: ?[]const u8 = null,
SNAM: ?[]SNAM = null,

const REGN = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(REGN),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_REGN: REGN = .{ .deleted = util.truncateRecordFlag(flag) & 0x1 != 0 };
    var NAME: []const u8 = "";

    var new_SNAM: std.ArrayListUnmanaged(SNAM) = .{};
    defer new_SNAM.deinit(allocator);

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
            .DELE => new_REGN.deleted = true,
            .NAME => NAME = subrecord.payload,
            .CNAM => {
                if (subrecord.payload.len < 4) return error.TooSmall;
                new_REGN.CNAM = subrecord.payload[0..4].*;
            },
            .WEAT => {
                const len: usize = if (subrecord.payload.len > 10) 10 else subrecord.payload.len;
                if (len < 8) return error.TooSmall;

                std.mem.copyForwards(u8, @ptrCast(*[10]u8, &new_REGN.WEAT), subrecord.payload[0..len]);
            },
            inline .FNAM, .BNAM => |known| {
                @field(new_REGN, @tagName(known)) = subrecord.payload;
            },
            .SNAM => try new_SNAM.append(allocator, try util.getLittle(SNAM, subrecord.payload)),
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    if (record_map.get(NAME)) |weat| if (weat.SNAM) |snam| allocator.free(snam);

    if (new_SNAM.items.len > 0) new_REGN.SNAM = try new_SNAM.toOwnedSlice(allocator);
    errdefer if (new_REGN.SNAM) |snam| allocator.free(snam);

    return record_map.put(allocator, NAME, new_REGN);
}

inline fn writeCnam(
    json_stream: anytype,
    _: []const u8,
    value: anytype,
) util.callback_err_type!void {
    const cnam = @as(*const REGN, value).CNAM;

    try json_stream.objectField("CNAM");
    try std.json.stringify(cnam, .{ .string = .Array }, json_stream.stream);
    json_stream.state_index -= 1;
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(REGN),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{
        .{"CNAM"},
    }, writeCnam);
}
