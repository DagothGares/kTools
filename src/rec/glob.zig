const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

deleted: bool,
FNAM: u8 = undefined, // TODO: determine what Morrowind chooses by default
FLTV: union { short: i16, long: i32, float: f32 } = undefined,

const GLOB = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(GLOB),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_GLOB: GLOB = .{ .deleted = util.truncateRecordFlag(flag) & 1 != 0 };
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
            .DELE => new_GLOB.deleted = true,
            .NAME => NAME = subrecord.payload,
            .FNAM => new_GLOB.FNAM = subrecord.payload[0],
            .FLTV => new_GLOB.FLTV = .{ .float = try util.getLittle(f32, subrecord.payload) },
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    switch (new_GLOB.FNAM) {
        's' => {
            const fltv = new_GLOB.FLTV.float;
            new_GLOB.FLTV = .{
                .short = if (fltv <= std.math.maxInt(i16)) @floatToInt(i16, fltv) else 0,
            };
        },
        'l' => {
            const fltv = new_GLOB.FLTV.float;
            new_GLOB.FLTV = .{
                .long = if (fltv <= std.math.maxInt(i32)) @floatToInt(i32, fltv) else 0,
            };
        },
        'f' => {},
        else => return error.Invalid_GLOB_FNAM,
    }

    return record_map.put(allocator, NAME, new_GLOB);
}

inline fn writeFields(
    json_stream: anytype,
    _: []const u8,
    value: anytype,
) util.callback_err_type!void {
    const glob = @as(*const GLOB, value);

    try json_stream.objectField("FNAM");
    try json_stream.emitString(@as(*const [1]u8, &glob.FNAM));

    try json_stream.objectField("FLTV");
    switch (glob.FNAM) {
        's' => try util.emitField(json_stream, glob.FLTV.short),
        'l' => try util.emitField(json_stream, glob.FLTV.long),
        'f' => try util.emitField(json_stream, glob.FLTV.float),
        else => unreachable,
    }
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(GLOB),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{
        .{"FNAM"},
        .{"FLTV"},
    }, writeFields);
}
