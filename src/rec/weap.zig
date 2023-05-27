const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const WPDT = extern struct {
    weight: f32 align(1) = 0,
    value: u32 align(1) = 0,
    weapon_type: u16 align(1) = 0,
    durability: u16 align(1) = 0,
    speed: f32 align(1) = 0,
    reach: f32 align(1) = 0,
    enchant_pts: u16 align(1) = 0,
    attacks: [3][2]u8 align(1) = [_][2]u8{.{ 0, 0 }} ** 3,
    flags: u32 align(1) = 0,
};

flag: u2,
MODL: ?[]const u8 = null,
WPDT: WPDT = .{},
FNAM: ?[]const u8 = null,
ITEX: ?[]const u8 = null,
ENAM: ?[]const u8 = null,
SCRI: ?[]const u8 = null,

const WEAP = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(WEAP),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_WEAP: WEAP = .{ .flag = util.truncateRecordFlag(flag) };
    var NAME: []const u8 = "";

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
            .DELE => new_WEAP.flag |= 0x1,
            .NAME => NAME = subrecord.payload,
            .WPDT => new_WEAP.WPDT = try util.getLittle(WPDT, subrecord.payload),
            inline .MODL, .FNAM, .ITEX, .ENAM, .SCRI => |known| {
                @field(new_WEAP, @tagName(known)) = subrecord.payload;
            },
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    return record_map.put(allocator, NAME, new_WEAP);
}

inline fn writeWpdt(
    json_stream: anytype,
    _: []const u8,
    value: anytype,
) util.callback_err_type!void {
    const wpdt = @as(*const WEAP, value).WPDT;

    try json_stream.objectField("WPDT");
    try json_stream.beginObject();
    inline for (std.meta.fields(WPDT)) |field| {
        if (comptime std.mem.eql(u8, field.name, "attacks")) continue;

        try json_stream.objectField(field.name);
        try util.emitField(json_stream, @field(wpdt, field.name));
    }

    try json_stream.objectField("attacks");
    try std.json.stringify(wpdt.attacks, .{ .string = .Array }, json_stream.stream);
    json_stream.state_index -= 1;

    try json_stream.endObject();
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(WEAP),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{
        .{"WPDT"},
    }, writeWpdt);
}
