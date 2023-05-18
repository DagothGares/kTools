const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const PathPoint = extern struct {
    position: [3]i32 align(1),
    flags: u8 align(1),
    connection_count: u8 align(1),
    _garbage: u16 align(1),
};

const DATA = extern struct {
    grid: [2]i32 align(1),
    flags: u16 align(1),
    path_point_count: u16 align(1),
};

pub const pgrd_data = struct {
    interior: std.StringArrayHashMapUnmanaged(PGRD) = .{},
    exterior: std.AutoArrayHashMapUnmanaged(u64, PGRD) = .{},

    const Self = @This();

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        for (self.interior.values()) |pgrd| {
            if (pgrd.PGRP) |pgrp| allocator.free(pgrp);
            if (pgrd.PGRC) |pgrc| allocator.free(pgrc);
        }
        for (self.exterior.values()) |pgrd| {
            if (pgrd.PGRP) |pgrp| allocator.free(pgrp);
            if (pgrd.PGRC) |pgrc| allocator.free(pgrc);
        }
        self.interior.deinit(allocator);
        self.exterior.deinit(allocator);
    }
};

pub const PGRD = struct {
    deleted: bool,
    DATA: DATA = undefined,
    NAME: ?[]const u8 = null,
    PGRP: ?[]PathPoint = null,
    PGRC: ?[]u32 = null,
};

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *pgrd_data,
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_PGRD: PGRD = .{ .deleted = util.truncateRecordFlag(flag) & 0x1 != 0 };
    errdefer {
        if (new_PGRD.PGRP) |pgrp| allocator.free(pgrp);
        if (new_PGRD.PGRC) |pgrc| allocator.free(pgrc);
    }

    var meta: struct {
        NAME: bool = false,
        DATA: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_PGRD.deleted = true,
            .NAME => {
                if (meta.NAME) return error.SubrecordRedeclared;
                meta.NAME = true;

                // I think these can be empty when they're tied to unnamed exteriors...
                if (subrecord.payload[0] != 0) new_PGRD.NAME = subrecord.payload;
            },
            .DATA => {
                if (meta.DATA) return error.SubrecordRedeclared;
                meta.DATA = true;

                new_PGRD.DATA = util.getLittle(DATA, subrecord.payload);
            },
            inline .PGRP, .PGRC => |known| {
                const field_type = switch (known) {
                    .PGRP => PathPoint,
                    .PGRC => u32,
                    else => unreachable,
                };
                const tag = @tagName(known);
                if (@field(new_PGRD, tag) != null) return error.SubrecordRedeclared;

                const size = @sizeOf(field_type);

                @field(new_PGRD, tag) = try allocator.alloc(
                    field_type,
                    try std.math.divExact(usize, subrecord.payload.len, size),
                );

                var index: usize = 0;
                for (@field(new_PGRD, tag).?) |*pgr_| {
                    pgr_.* = util.getLittle(field_type, subrecord.payload[index .. index + size]);
                    index += size;
                }
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    inline for (std.meta.fields(@TypeOf(meta))) |field| {
        if (!@field(meta, field.name)) return error.MissingRequiredSubrecord;
    }

    // flag check is to verify true 0
    // TODO: maybe tie PGRD to CELL/LAND records instead?
    const as_u64 = @bitCast(u64, new_PGRD.DATA.grid);
    if (as_u64 == 0 and new_PGRD.DATA.flags != 16384) {
        const NAME = new_PGRD.NAME.?;

        if (record_map.interior.get(NAME)) |pgrd| {
            if (pgrd.PGRP) |pgrp| allocator.free(pgrp);
            if (pgrd.PGRC) |pgrc| allocator.free(pgrc);
        }

        try record_map.interior.put(allocator, NAME, new_PGRD);
    } else {
        if (record_map.exterior.get(as_u64)) |pgrd| {
            if (pgrd.PGRP) |pgrp| allocator.free(pgrp);
            if (pgrd.PGRC) |pgrc| allocator.free(pgrc);
        }

        try record_map.exterior.put(allocator, as_u64, new_PGRD);
    }
}

inline fn writePgrc(
    _: std.mem.Allocator,
    json_stream: anytype,
    _: []const u8,
    value: anytype,
) util.callback_err_type!void {
    const pgrd = @as(*const PGRD, value);

    try json_stream.objectField("PGRC");
    if (pgrd.PGRC) |pgrc| {
        try std.json.stringify(pgrc, .{}, json_stream.stream);
        json_stream.state_index -= 1;
    } else try json_stream.emitNull();
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: pgrd_data,
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    try util.writeAllGeneric(allocator, dir, record_map.interior, list_writer, 6, .{
        .{"PGRC"},
    }, writePgrc);

    for (record_map.exterior.keys(), record_map.exterior.values()) |k, v| {
        // we can represent one 32-bit signed integer in 11 bytes including the sign, so we need an
        // extra 5 for ".json" and 2 for the ", " between them.
        var key_buffer: [29]u8 = undefined;
        const key = blk: {
            var key_stream = std.io.fixedBufferStream(&key_buffer);
            var key_writer = key_stream.writer();
            const as_grid = @bitCast([2]i32, k);
            key_writer.print("{d}, {d}.json", .{ as_grid[0], as_grid[1] }) catch unreachable;
            break :blk key_stream.getWritten();
        };

        try list_writer.writer().print("\"{s}\",", .{key[0 .. key.len - 5]});

        const out_file = try dir.createFile(key, .{});
        defer out_file.close();

        var buffered_writer = std.io.bufferedWriter(out_file.writer());
        var writer = buffered_writer.writer();

        var json_stream = std.json.writeStream(writer, 6);
        json_stream.whitespace.indent = .{ .space = 2 };

        try json_stream.beginObject();
        try json_stream.objectField("deleted");
        try json_stream.emitBool(v.deleted);

        inline for (std.meta.fields(PGRD)[1..4]) |field| {
            try json_stream.objectField(field.name);
            try util.emitField(allocator, &json_stream, @field(v, field.name));
        }

        try json_stream.objectField("PGRC");
        if (v.PGRC) |pgrc| {
            try std.json.stringify(pgrc, .{}, json_stream.stream);
            json_stream.state_index -= 1;
        } else try json_stream.emitNull();

        try json_stream.endObject();
        try buffered_writer.flush();
    }
}
