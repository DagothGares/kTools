const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const DIAL = @import("dial.zig");

/// first 4 bytes and the last byte are meaningless, and thus cut
const DATA = extern struct {
    value: u32 align(1) = 0, // can be a disposition value or a journal index
    rank: i8 align(1) = 0,
    gender: i8 align(1) = 0,
    player_rank: i8 align(1) = 0,
};

const __TV = union(enum) {
    IN: u32,
    FL: f32,
};

const SCVR = struct {
    index: [1]u8,
    scvr_type: [1]u8,
    details: [2]u8,
    operator: [1]u8,
    identifier: ?[]const u8,
    __TV: ?__TV = null,
};

// bottom bit is the deletion flag, top 2 are an enum for QSTN/QSTF/QSTR/null
flag: u3 = 0,
DATA: DATA = .{},
PNAM: []const u8 = "",
NNAM: []const u8 = "",
ONAM: ?[]const u8 = null,
RNAM: ?[]const u8 = null,
CNAM: ?[]const u8 = null,
FNAM: ?[]const u8 = null,
ANAM: ?[]const u8 = null,
DNAM: ?[]const u8 = null,
SNAM: ?[]const u8 = null,
NAME: ?[]const u8 = null,
BNAM: ?[]const u8 = null,
SCVR: ?[]SCVR = null,

const INFO = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(INFO),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_INFO: INFO = .{ .flag = util.truncateRecordFlag(flag) & 0x1 };
    var INAM: []const u8 = "";

    var new_SCVR: std.ArrayListUnmanaged(SCVR) = .{};
    defer new_SCVR.deinit(allocator);

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
            .DELE => new_INFO.flag |= 0x1,
            .INAM => INAM = subrecord.payload,
            .DATA => {
                if (subrecord.payload.len < 11) return error.TooSmall;
                new_INFO.DATA = util.getLittle(DATA, subrecord.payload[4..11]) catch unreachable;
            },
            .FNAM => {
                // bethesda-ism; they used a value to represent null when they could have just...
                // made it null, since it's a string (or not included it at all)
                // zig fmt: off
                if (!(subrecord.payload.len == 5 and
                    std.ascii.eqlIgnoreCase(subrecord.payload, "FFFF"))) {
                    // zig fmt: on
                    new_INFO.FNAM = subrecord.payload;
                }
            },
            .SCVR => {
                if (subrecord.payload.len < 5) return error.TooSmall;

                try new_SCVR.append(allocator, .{
                    .index = .{subrecord.payload[0]},
                    .scvr_type = .{subrecord.payload[1]},
                    .details = subrecord.payload[2..4].*,
                    .operator = .{subrecord.payload[4]},
                    .identifier = if (subrecord.payload.len > 5) subrecord.payload[5..] else null,
                    .__TV = blk: {
                        const pos = iterator.stream.getPos() catch unreachable;
                        const next = iterator.next() orelse break :blk null;
                        switch (try util.parseSub(
                            logger,
                            next.tag,
                            next.pos,
                            plugin_name,
                        ) orelse .DELE) {
                            .FLTV => break :blk .{
                                .FL = try util.getLittle(f32, next.payload),
                            },
                            .INTV => {
                                switch (subrecord.payload[2]) {
                                    's' => {
                                        const integer = try util.getLittle(u32, next.payload);
                                        break :blk .{
                                            .IN = if (integer <= std.math.maxInt(u16))
                                                @truncate(u16, integer)
                                            else
                                                0,
                                        };
                                    },
                                    else => break :blk .{
                                        .IN = try util.getLittle(u32, next.payload),
                                    },
                                }
                            },
                            else => {
                                iterator.stream.seekTo(pos) catch unreachable;
                                break :blk null;
                            },
                        }
                    },
                });
            },
            inline .QSTN, .QSTF, .QSTR => |known| {
                const setting = comptime switch (known) {
                    .QSTN => 1,
                    .QSTF => 2,
                    .QSTR => 3,
                    else => unreachable,
                } << 1;

                new_INFO.flag &= 0x1;
                new_INFO.flag |= setting;
            },
            // zig fmt: off
            inline .PNAM, .NNAM, .ONAM, .RNAM, .CNAM, .ANAM, .DNAM, .SNAM,
            .NAME, .BNAM => |known| {
                // zig fmt: on
                @field(new_INFO, @tagName(known)) = subrecord.payload;
            },
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    if (record_map.get(INAM)) |info| if (info.SCVR) |scvr| allocator.free(scvr);

    if (new_SCVR.items.len > 0) new_INFO.SCVR = try new_SCVR.toOwnedSlice(allocator);

    return record_map.put(allocator, INAM, new_INFO);
}

pub inline fn writeAll(
    json_stream: anytype,
    _: []const u8,
    value: anytype,
) util.callback_err_type!void {
    const dial = @as(*const DIAL, value);
    const info_map = &dial.INFO;

    try json_stream.objectField("INFO");
    try json_stream.beginObject();
    for (info_map.keys(), info_map.values()) |k, v| {
        try json_stream.objectField(k[0 .. k.len - 1]);
        try util.emitField(json_stream, v);
    }
    try json_stream.endObject();
}
