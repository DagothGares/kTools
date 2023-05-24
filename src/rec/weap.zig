const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const WPDT = extern struct {
    weight: f32 align(1),
    value: u32 align(1),
    weapon_type: u16 align(1),
    durability: u16 align(1),
    speed: f32 align(1),
    reach: f32 align(1),
    enchant_pts: u16 align(1),
    attacks: [3][2]u8 align(1),
    flags: u32 align(1),
};

flag: u2,
MODL: []const u8 = undefined,
WPDT: WPDT = undefined,
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
    var NAME: ?[]const u8 = null;

    var meta: struct {
        MODL: bool = false,
        WPDT: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_WEAP.flag |= 0x1,
            .NAME => {
                if (NAME != null) return error.SubrecordRedeclared;

                NAME = subrecord.payload;
            },
            .MODL => {
                if (meta.MODL) return error.SubrecordRedeclared;
                meta.MODL = true;

                new_WEAP.MODL = subrecord.payload;
            },
            .WPDT => {
                if (meta.WPDT) return error.SubrecordRedeclared;
                meta.WPDT = true;

                new_WEAP.WPDT = util.getLittle(WPDT, subrecord.payload);
            },
            inline .FNAM, .ITEX, .ENAM, .SCRI => |known| {
                const tag = @tagName(known);
                if (@field(new_WEAP, tag) != null) return error.SubrecordRedeclared;

                @field(new_WEAP, tag) = subrecord.payload;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    if (NAME) |name| {
        inline for (std.meta.fields(@TypeOf(meta))) |field| {
            if (!@field(meta, field.name)) {
                if (new_WEAP.flag & 0x1 != 0) {
                    if (record_map.getPtr(name)) |existing| existing.flag |= 0x1;
                    return;
                }
                return error.MissingRequiredSubrecord;
            }
        }

        return record_map.put(allocator, name, new_WEAP);
    } else return error.MissingRequiredSubrecord;
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
