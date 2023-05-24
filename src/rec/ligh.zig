const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const LHDT = extern struct {
    weight: f32 align(1),
    value: u32 align(1),
    time: i32 align(1),
    radius: u32 align(1),
    color: [4]u8 align(1),
    flags: u32 align(1),
};

flag: u2,
LHDT: LHDT = undefined,
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
    var NAME: ?[]const u8 = null;

    var meta: struct {
        LHDT: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_LIGH.flag |= 0x1,
            .NAME => {
                if (NAME != null) return error.SubrecordRedeclared;

                NAME = subrecord.payload;
            },
            .LHDT => {
                if (meta.LHDT) return error.SubrecordRedeclared;
                meta.LHDT = true;

                new_LIGH.LHDT = try util.getLittle(LHDT, subrecord.payload);
            },
            inline .MODL, .FNAM, .ITEX, .SNAM, .SCRI => |known| {
                const tag = @tagName(known);
                if (@field(new_LIGH, tag) != null) return error.SubrecordRedeclared;

                @field(new_LIGH, tag) = subrecord.payload;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    if (NAME) |name| {
        inline for (std.meta.fields(@TypeOf(meta))) |field| {
            if (!@field(meta, field.name)) {
                if (new_LIGH.flag & 0x1 != 0) {
                    if (record_map.getPtr(name)) |existing| existing.flag |= 0x1;
                    return;
                }
                return error.MissingRequiredSubrecord;
            }
        }

        return record_map.put(allocator, name, new_LIGH);
    } else return error.MissingRequiredSubrecord;
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
