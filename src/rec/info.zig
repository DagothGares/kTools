const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const DIAL = @import("dial.zig");

/// first 4 bytes and the last byte are meaningless, and thus cut
const DATA = extern struct {
    value: u32 align(1), // can be a disposition value or a journal index
    rank: i8 align(1),
    gender: i8 align(1),
    player_rank: i8 align(1),
};

const SCVR = struct {
    index: [1]u8,
    scvr_type: [1]u8,
    details: [2]u8,
    operator: [1]u8,
    identifier: ?[]const u8,
    __TV: ?union(enum) { IN: u32, FL: f32 } = null,
};

pub const payload_type = struct {
    // bottom bit is the deletion flag, top 2 are an enum for QSTN/QSTF/QSTR/null
    flags: u3 = 0,
    PNAM: ?[]const u8 = null,
    NNAM: ?[]const u8 = null,
    DATA: ?DATA = null,
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
};

INAM: []const u8 = undefined,
payload: payload_type,

const INFO = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record: []const u8,
    start: u64,
    flag: u32,
) !INFO {
    var new_INFO: INFO = .{ .payload = .{ .flags = util.truncateRecordFlag(flag) & 0x1 } };

    var new_SCVR: std.ArrayListUnmanaged(SCVR) = .{};
    defer new_SCVR.deinit(allocator);

    var meta: struct {
        INAM: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_INFO.payload.flags |= 0x1,
            .INAM => {
                if (meta.INAM) return error.SubrecordRedeclared;
                meta.INAM = true;

                new_INFO.INAM = subrecord.payload;
            },
            .DATA => {
                if (new_INFO.payload.DATA != null) return error.SubrecordRedeclared;

                new_INFO.payload.DATA = util.getLittle(DATA, subrecord.payload[4..11]);
            },
            .FNAM => {
                if (new_INFO.payload.FNAM != null) return error.SubrecordRedeclared;

                // bethesda-ism; they used a value to represent null when they could have just...
                // made it null, since it's a string (or not included it at all)
                if (!(subrecord.payload.len == 5 and
                    std.ascii.eqlIgnoreCase(subrecord.payload, "FFFF")))
                {
                    new_INFO.payload.FNAM = subrecord.payload;
                }
            },
            .SCVR => {
                var scvr: SCVR = .{
                    .index = .{subrecord.payload[0]},
                    .scvr_type = .{subrecord.payload[1]},
                    .details = subrecord.payload[2..4].*,
                    .operator = .{subrecord.payload[4]},
                    .identifier = if (subrecord.payload.len > 5) subrecord.payload[5..] else null,
                };

                switch (scvr.details[0]) {
                    'f' => {
                        const should_be_FLTV = try iterator.next(logger, plugin_name, start) orelse
                            return error.MissingRequiredSubrecord;
                        if (should_be_FLTV.tag != .FLTV) return error.MissingRequiredSubrecord;
                        scvr.__TV = .{ .FL = util.getLittle(f32, should_be_FLTV.payload) };
                    },
                    'l' => {
                        const should_be_INTV = try iterator.next(logger, plugin_name, start) orelse
                            return error.MissingRequiredSubrecord;
                        if (should_be_INTV.tag != .INTV) return error.MissingRequiredSubrecord;
                        scvr.__TV = .{ .IN = util.getLittle(u32, should_be_INTV.payload) };
                    },
                    's' => {
                        const should_be_INTV = try iterator.next(logger, plugin_name, start) orelse
                            return error.MissingRequiredSubrecord;
                        if (should_be_INTV.tag != .INTV) return error.MissingRequiredSubrecord;
                        scvr.__TV = .{
                            .IN = @truncate(u16, util.getLittle(u32, should_be_INTV.payload)),
                        };
                    },
                    else => {
                        const maybe_TV = try iterator.next(logger, plugin_name, start);
                        if (maybe_TV) |tv| switch (tv.tag) {
                            .FLTV => scvr.__TV = .{ .FL = util.getLittle(f32, tv.payload) },
                            .INTV => scvr.__TV = .{ .IN = util.getLittle(u32, tv.payload) },
                            else => try iterator.stream.seekBy(
                                -1 * @intCast(isize, tv.payload.len + 16),
                            ),
                        };
                    },
                }

                try new_SCVR.append(allocator, scvr);
            },
            inline .QSTN, .QSTF, .QSTR => |known| {
                if (new_INFO.payload.flags > 0x1) return error.SubrecordRedeclared;

                const setting = switch (known) {
                    .QSTN => 0x1,
                    .QSTF => 0x2,
                    .QSTR => 0x3,
                    else => unreachable,
                };
                new_INFO.payload.flags |= setting << 1;
            },
            inline .PNAM,
            .NNAM,
            .ONAM,
            .RNAM,
            .CNAM,
            .ANAM,
            .DNAM,
            .SNAM,
            .NAME,
            .BNAM,
            => |known| {
                const tag = @tagName(known);
                if (@field(new_INFO.payload, tag) != null) return error.SubrecordRedeclared;

                @field(new_INFO.payload, tag) = subrecord.payload;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    inline for (std.meta.fields(@TypeOf(meta))) |field| {
        if (!@field(meta, field.name)) return error.MissingRequiredSubrecord;
    }

    if (new_SCVR.items.len > 0) new_INFO.payload.SCVR = try new_SCVR.toOwnedSlice(allocator);

    return new_INFO;
}

pub inline fn writeAll(
    allocator: std.mem.Allocator,
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
        try util.emitField(allocator, json_stream, v);
    }
    try json_stream.endObject();
}
