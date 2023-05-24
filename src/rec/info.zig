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

// bottom bit is the deletion flag, top 2 are an enum for QSTN/QSTF/QSTR/null
flag: u3 = 0,
PNAM: []const u8 = undefined,
NNAM: []const u8 = undefined,
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
    var INAM: ?[]const u8 = null;

    var new_SCVR: std.ArrayListUnmanaged(SCVR) = .{};
    defer new_SCVR.deinit(allocator);

    var meta: struct {
        PNAM: bool = false,
        NNAM: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_INFO.flag |= 0x1,
            .INAM => {
                if (INAM != null) return error.SubrecordRedeclared;

                INAM = subrecord.payload;
            },
            inline .PNAM, .NNAM => |known| {
                const tag = @tagName(known);
                if (@field(meta, tag)) return error.SubrecordRedeclared;
                @field(meta, tag) = true;

                @field(new_INFO, tag) = subrecord.payload;
            },
            .DATA => {
                if (new_INFO.DATA != null) return error.SubrecordRedeclared;

                new_INFO.DATA = util.getLittle(DATA, subrecord.payload[4..11]);
            },
            .FNAM => {
                if (new_INFO.FNAM != null) return error.SubrecordRedeclared;

                // bethesda-ism; they used a value to represent null when they could have just...
                // made it null, since it's a string (or not included it at all)
                if (!(subrecord.payload.len == 5 and
                    std.ascii.eqlIgnoreCase(subrecord.payload, "FFFF")))
                {
                    new_INFO.FNAM = subrecord.payload;
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
                if (new_INFO.flag > 0x1) return error.SubrecordRedeclared;

                const setting = switch (known) {
                    .QSTN => 0x1,
                    .QSTF => 0x2,
                    .QSTR => 0x3,
                    else => unreachable,
                };
                new_INFO.flag |= setting << 1;
            },
            inline .ONAM, .RNAM, .CNAM, .ANAM, .DNAM, .SNAM, .NAME, .BNAM => |known| {
                const tag = @tagName(known);
                if (@field(new_INFO, tag) != null) return error.SubrecordRedeclared;

                @field(new_INFO, tag) = subrecord.payload;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    if (INAM) |inam| {
        inline for (std.meta.fields(@TypeOf(meta))) |field| {
            if (!@field(meta, field.name)) {
                if (new_INFO.flag & 0x1 != 0) {
                    if (record_map.getPtr(inam)) |existing| existing.flag |= 0x1;
                    return;
                }
                return error.MissingRequiredSubrecord;
            }
        }

        if (record_map.get(inam)) |info| if (info.SCVR) |scvr| allocator.free(scvr);

        if (new_SCVR.items.len > 0) new_INFO.SCVR = try new_SCVR.toOwnedSlice(allocator);

        return record_map.put(allocator, inam, new_INFO);
    } else return error.MissingRequiredSubrecord;
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
