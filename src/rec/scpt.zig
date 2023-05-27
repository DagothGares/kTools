const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const SCHD = extern struct {
    num_shorts: u32 align(1) = 0,
    num_longs: u32 align(1) = 0,
    num_floats: u32 align(1) = 0,
    script_data_size: u32 align(1) = 0,
    local_var_size: u32 align(1) = 0,
};

deleted: bool,
SCHD: SCHD = .{},
// NOTE: should be split into a set of substrings at write time
SCVR: ?[]const u8 = null,
SCDT: ?[]const u8 = null,
SCTX: ?[]const u8 = null,

const SCPT = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(SCPT),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_SCPT: SCPT = .{ .deleted = util.truncateRecordFlag(flag) & 0x1 != 0 };
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
            .DELE => new_SCPT.deleted = true,
            .SCHD => {
                if (subrecord.payload.len < 52) return error.TooSmall;

                // For several reasons, it's a really good idea to do this instead of putting it
                // inside the SCHD struct.
                const end_index = std.mem.indexOf(u8, subrecord.payload[0..32], "\x00") orelse 32;
                NAME = subrecord.payload[0..end_index];
                new_SCPT.SCHD = util.getLittle(SCHD, subrecord.payload[32..]) catch unreachable;
            },
            inline .SCVR, .SCDT, .SCTX => |known| {
                @field(new_SCPT, @tagName(known)) = subrecord.payload;
            },
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    return record_map.put(allocator, NAME, new_SCPT);
}

inline fn writeVrDt(
    json_stream: anytype,
    _: []const u8,
    value: anytype,
) util.callback_err_type!void {
    const scpt = @as(*const SCPT, value);

    try json_stream.objectField("SCVR");
    if (scpt.SCVR) |scvr| {
        try json_stream.beginArray();
        var split = std.mem.split(u8, scvr[0 .. scvr.len - 1], "\x00");
        while (split.next()) |variable_name| {
            try json_stream.arrayElem();
            try util.emitAnsiJson(json_stream, variable_name);
        }
        try json_stream.endArray();
    } else try json_stream.emitNull();

    try json_stream.objectField("SCDT");
    if (scpt.SCDT) |scdt| {
        try std.json.stringify(scdt, .{ .string = .Array }, json_stream.stream);
        json_stream.state_index -= 1;
    } else try json_stream.emitNull();
}

// needs to output SCVR as an array of substrings, and SCDT as bytes
pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(SCPT),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{
        .{"SCVR"},
        .{"SCDT"},
    }, writeVrDt);
}
