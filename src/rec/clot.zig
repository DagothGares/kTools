const std = @import("std");
const util = @import("../util.zig");

// TODO: figure out how to merge this impl with ARMO

const subs = util.subs;

const CTDT = extern struct {
    clothing_type: u32 align(1) = 0,
    weight: f32 align(1) = 0,
    value: u16 align(1) = 0,
    enchant_points: u16 align(1) = 0,
};

const INDX = @import("shared.zig").INDX;

flag: u2,
CTDT: CTDT = .{},
MODL: ?[]const u8 = null,
FNAM: ?[]const u8 = null,
SCRI: ?[]const u8 = null,
ITEX: ?[]const u8 = null,
ENAM: ?[]const u8 = null,
INDX: ?[]INDX = null,

const CLOT = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(CLOT),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_CLOT: CLOT = .{ .flag = util.truncateRecordFlag(flag) };
    var NAME: []const u8 = "";

    var new_INDX: std.ArrayListUnmanaged(INDX) = .{};
    defer new_INDX.deinit(allocator);

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
            .DELE => new_CLOT.flag |= 0x1,
            .NAME => NAME = subrecord.payload,
            .CTDT => new_CLOT.CTDT = try util.getLittle(CTDT, subrecord.payload),
            .INDX => {
                var indx: INDX = .{ .index = subrecord.payload[0] };

                var last_pos: u64 = try iterator.stream.getPos();
                while (iterator.next()) |next_sub| {
                    const next_tag = try util.parseSub(
                        logger,
                        next_sub.tag,
                        next_sub.pos,
                        plugin_name,
                    ) orelse {
                        // avoid warning twice for the same sub
                        last_pos = iterator.stream.getPos() catch unreachable;
                        break;
                    };

                    switch (next_tag) {
                        inline .BNAM, .CNAM => |known| {
                            @field(indx, @tagName(known)) = next_sub.payload;
                        },
                        else => break,
                    }
                    last_pos = iterator.stream.getPos() catch unreachable;
                }
                iterator.stream.seekTo(last_pos) catch unreachable;

                try new_INDX.append(allocator, indx);
            },
            inline .MODL, .FNAM, .SCRI, .ITEX, .ENAM => |known| {
                @field(new_CLOT, @tagName(known)) = subrecord.payload;
            },
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    if (record_map.get(NAME)) |clot| if (clot.INDX) |indx| allocator.free(indx);

    if (new_INDX.items.len > 0) new_CLOT.INDX = try new_INDX.toOwnedSlice(allocator);
    errdefer if (new_CLOT.INDX) |indx| allocator.free(indx);

    return record_map.put(allocator, NAME, new_CLOT);
}

inline fn writeIndx(
    json_stream: anytype,
    _: []const u8,
    value: anytype,
) util.callback_err_type!void {
    const clot = @as(*const CLOT, value); // un-erase the type

    try json_stream.objectField("INDX");
    if (clot.INDX) |indx_slice| {
        try json_stream.beginObject();
        for (indx_slice) |indx| {
            switch (json_stream.state[json_stream.state_index]) {
                .complete, .value, .array_start, .array => unreachable,
                inline .object, .object_start => |known| {
                    if (known == .object) try json_stream.stream.writeByte(',');
                    json_stream.state[json_stream.state_index] = .object;
                    json_stream.state_index += 1;
                    json_stream.state[json_stream.state_index] = .value;
                    try json_stream.whitespace.outputIndent(json_stream.stream);
                    try json_stream.stream.print("\"{d}\": ", .{indx.index});
                },
            }
            try util.emitField(json_stream, .{ .bnam = indx.BNAM, .cnam = indx.CNAM });
        }
        try json_stream.endObject();
    } else try json_stream.emitNull();
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(CLOT),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{
        .{"INDX"},
    }, writeIndx);
}
