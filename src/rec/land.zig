const std = @import("std");
const builtin = @import("builtin");
const util = @import("../util.zig");

const subs = util.subs;

// junk ignored
const VHGT = extern struct {
    // needs to be converted from little endian
    offset: f32 align(1),
    height_data: [65][65]i8 align(1),
};

deleted: bool,
DATA: u32 = undefined,
VHGT: ?*align(1) const VHGT = null,
VNML: ?*align(1) const [65][65][3]i8 = null,
WNAM: ?*align(1) const [9][9]u8 = null,
VCLR: ?*align(1) const [65][65][3]u8 = null,
// needs to be converted from little endian
VTEX: ?*align(1) const [16][16]u16 = null,

const LAND = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.AutoArrayHashMapUnmanaged(u64, LAND),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_LAND: LAND = .{ .deleted = util.truncateRecordFlag(flag) & 0x1 != 0 };
    var INTV: u64 = undefined;

    var meta: struct {
        INTV: bool = false,
        DATA: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_LAND.deleted = true,
            .INTV => {
                if (meta.INTV) return error.SubrecordRedeclared;
                meta.INTV = true;

                INTV = @ptrCast(*align(4) const u64, &util.getLittle([2]i32, subrecord.payload)).*;
            },
            .DATA => {
                if (meta.DATA) return error.SubrecordRedeclared;
                meta.DATA = true;

                new_LAND.DATA = util.getLittle(u32, subrecord.payload);
            },
            .VHGT => {
                // vhgt is special because we strip 3 bytes of junk at the end
                if (new_LAND.VHGT != null) return error.SubrecordRedeclared;

                new_LAND.VHGT = @ptrCast(*align(1) const VHGT, subrecord.payload[0..4229]);
            },
            inline .VNML, .WNAM, .VCLR, .VTEX => |known| {
                const tag = @tagName(known);
                if (@field(new_LAND, tag) != null) return error.SubrecordRedeclared;

                const field_type = switch (known) {
                    .VNML => [65][65][3]i8,
                    .WNAM => [9][9]u8,
                    .VCLR => [65][65][3]u8,
                    .VTEX => [16][16]u16,
                    else => unreachable,
                };
                @field(new_LAND, tag) = @ptrCast(*align(1) const field_type, subrecord.payload);
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    inline for (std.meta.fields(@TypeOf(meta))) |field| {
        if (!@field(meta, field.name)) return error.MissingRequiredSubrecord;
    }

    try record_map.put(allocator, INTV, new_LAND);
}

pub fn writeAll(
    _: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.AutoArrayHashMapUnmanaged(u64, LAND),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    for (record_map.keys(), record_map.values()) |k, v| {
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

        try json_stream.objectField("DATA");
        try util.emitField(&json_stream, v.DATA);
        try json_stream.objectField("VHGT");
        if (v.VHGT) |vhgt| {
            try json_stream.beginObject();

            try json_stream.objectField("offset");
            if (comptime builtin.cpu.arch.endian() == .Little) {
                try util.emitField(&json_stream, vhgt.offset);
            } else {
                const big = util.castForeign(f32, &@bitCast([4]u8, vhgt.offset));
                try util.emitField(&json_stream, big);
            }

            try json_stream.objectField("height_data");
            try std.json.stringify(vhgt.height_data, .{}, json_stream.stream);
            json_stream.state_index -= 1;

            try json_stream.endObject();
        } else try json_stream.emitNull();

        inline for (std.meta.fields(LAND)[3..6]) |field| {
            try json_stream.objectField(field.name);
            if (@field(v, field.name)) |f| {
                // This probably does weird things; I can't be bothered to care for now.
                try std.json.stringify(f.*, .{ .string = .Array }, json_stream.stream);
                json_stream.state_index -= 1;
            } else try json_stream.emitNull();
        }

        try json_stream.objectField("VTEX");
        if (v.VTEX) |vtex| {
            if (comptime builtin.cpu.arch.endian() == .Little) {
                try std.json.stringify(vtex.*, .{}, json_stream.stream);
                json_stream.state_index -= 1;
            } else {
                json_stream.whitespace.indent = .{ .none = {} };
                try json_stream.beginArray();
                for (vtex.*) |tex| {
                    try json_stream.arrayElem();
                    try util.emitField(&json_stream, tex);
                }
                try json_stream.endArray();
                json_stream.whitespace.indent = .{ .space = 2 };
            }
        } else try json_stream.emitNull();

        try json_stream.endObject();
        try buffered_writer.flush();
    }
}
