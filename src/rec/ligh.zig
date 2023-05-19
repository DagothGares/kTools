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
MODL: []const u8 = undefined,
LHDT: LHDT = undefined,
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
    var NAME: []const u8 = undefined;

    var meta: struct {
        NAME: bool = false,
        MODL: bool = false,
        LHDT: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_LIGH.flag |= 0x1,
            .NAME => {
                if (meta.NAME) return error.SubrecordRedeclared;
                meta.NAME = true;

                NAME = subrecord.payload;
            },
            .MODL => {
                if (meta.MODL) return error.subrecordRedeclared;
                meta.MODL = true;

                new_LIGH.MODL = subrecord.payload;
            },
            .LHDT => {
                if (meta.LHDT) return error.SubrecordRedeclared;
                meta.LHDT = true;

                new_LIGH.LHDT = util.getLittle(LHDT, subrecord.payload);
            },
            inline .FNAM, .ITEX, .SNAM, .SCRI => |known| {
                const tag = @tagName(known);
                if (@field(new_LIGH, tag) != null) return error.SubrecordRedeclared;

                @field(new_LIGH, tag) = subrecord.payload;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    inline for (std.meta.fields(@TypeOf(meta))) |field| {
        if (!@field(meta, field.name)) return error.MissingRequiredSubrecord;
    }

    try record_map.put(allocator, NAME, new_LIGH);
}

inline fn writeLhdt(
    allocator: std.mem.Allocator,
    json_stream: anytype,
    _: []const u8,
    value: anytype,
) util.callback_err_type!void {
    const lhdt = @as(*const LIGH, value).LHDT;

    try json_stream.objectField("LHDT");
    try json_stream.beginObject();
    inline for (std.meta.fields(LHDT)[1..]) |field| {
        try json_stream.objectField(field.name);
        if (comptime std.mem.eql(u8, field.name, "color")) {
            try std.json.stringify(lhdt.color, .{ .string = .Array }, json_stream.stream);
            json_stream.state_index -= 1;
        } else try util.emitField(allocator, json_stream, @field(lhdt, field.name));
    }
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
