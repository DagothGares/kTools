const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const LHDT = extern struct {
    weight: f32 align(1) = 0,
    value: u32 align(1) = 0,
    time: i32 align(1) = 0,
    radius: u32 align(1) = 0,
    color: [4]u8 align(1) = [_]u8{0} ** 4,
    flags: u32 align(1) = 0,
};

flag: u2,
LHDT: LHDT = .{},
MODL: ?[]const u8 = null,
FNAM: ?[]const u8 = null,
ITEX: ?[]const u8 = null,
SNAM: ?[]const u8 = null,
SCRI: ?[]const u8 = null,

const LIGH = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(LIGH),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_LIGH: LIGH = .{ .flag = util.truncateRecordFlag(flag) };
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
            .DELE => new_LIGH.flag |= 0x1,
            .NAME => NAME = subrecord.payload,
            .LHDT => new_LIGH.LHDT = try util.getLittle(LHDT, subrecord.payload),
            inline .MODL, .FNAM, .ITEX, .SNAM, .SCRI => |known| {
                @field(new_LIGH, @tagName(known)) = subrecord.payload;
            },
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    return record_map.put(allocator, NAME, new_LIGH);
}

inline fn writeLhdt(
    json_stream: anytype,
    _: []const u8,
    value: anytype,
) util.callback_err_type!void {
    const lhdt = @as(*const LIGH, value).LHDT;

    try json_stream.objectField("LHDT");
    try json_stream.beginObject();
    inline for (std.meta.fields(LHDT)[1..]) |field| {
        if (comptime std.mem.eql(u8, field.name, "color")) continue;
        try json_stream.objectField(field.name);
        try util.emitField(json_stream, @field(lhdt, field.name));
    }
    try json_stream.objectField("color");
    try std.json.stringify(lhdt.color, .{ .string = .Array }, json_stream.stream);
    json_stream.state_index -= 1;

    try json_stream.endObject();
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(LIGH),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{
        .{"LHDT"},
    }, writeLhdt);
}
