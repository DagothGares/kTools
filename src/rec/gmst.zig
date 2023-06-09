const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const __TV = union {
    FL: f32,
    IN: i32,
    ST: []const u8,
};

deleted: bool,
__TV: __TV = undefined,

const GMST = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(GMST),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_GMST: GMST = .{ .deleted = util.truncateRecordFlag(flag) & 1 != 0 };
    var NAME: []const u8 = "";

    var tv: ?__TV = null;

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
            .DELE => new_GMST.deleted = true,
            .NAME => NAME = subrecord.payload,
            inline .FLTV, .INTV, .STRV => |known| {
                const tag = switch (known) {
                    .FLTV => "FL",
                    .INTV => "IN",
                    .STRV => "ST",
                    else => unreachable,
                };
                const content = switch (known) {
                    .FLTV => try util.getLittle(f32, subrecord.payload),
                    .INTV => try util.getLittle(i32, subrecord.payload),
                    .STRV => subrecord.payload,
                    else => unreachable,
                };

                tv = @unionInit(@TypeOf(new_GMST.__TV), tag, content);
            },
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    if (tv == null) switch (NAME[0]) {
        'f' => new_GMST.__TV = .{ .FL = 0 },
        'i' => new_GMST.__TV = .{ .IN = 0 },
        's' => new_GMST.__TV = .{ .ST = "" },
        else => return error.Invalid_GMST_Tag,
    } else new_GMST.__TV = tv.?;

    return record_map.put(allocator, NAME, new_GMST);
}

inline fn writeTv(
    json_stream: anytype,
    key: []const u8,
    value: anytype,
) util.callback_err_type!void {
    const gmst = @as(*const GMST, value);

    switch (key[0]) {
        'f' => {
            try json_stream.objectField("FLTV");
            try util.emitField(json_stream, gmst.__TV.FL);
        },
        'i' => {
            try json_stream.objectField("INTV");
            try util.emitField(json_stream, gmst.__TV.IN);
        },
        's' => {
            try json_stream.objectField("STRV");
            try util.emitField(json_stream, gmst.__TV.ST);
        },
        else => unreachable,
    }
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(GMST),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{
        .{"__TV"},
    }, writeTv);
}
