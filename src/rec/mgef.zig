const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const MEDT = extern struct {
    school: u32 align(1),
    base_cost: f32 align(1),
    flags: u32 align(1),
    rgb: [3]u32 align(1),
    speed_mult: f32 align(1),
    size_mult: f32 align(1),
    size_cap: f32 align(1),
};

deleted: bool,
MEDT: MEDT = undefined,
ITEX: ?[]const u8 = null,
PTEX: ?[]const u8 = null,
BSND: ?[]const u8 = null,
CSND: ?[]const u8 = null,
HSND: ?[]const u8 = null,
ASND: ?[]const u8 = null,
CVFX: ?[]const u8 = null,
BVFX: ?[]const u8 = null,
HVFX: ?[]const u8 = null,
AVFX: ?[]const u8 = null,
DESC: ?[]const u8 = null,

const MGEF = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.AutoArrayHashMapUnmanaged(u32, MGEF),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_MGEF: MGEF = .{ .deleted = util.truncateRecordFlag(flag) & 0x1 != 0 };
    var INDX: ?u32 = null;

    var meta: struct {
        MEDT: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_MGEF.deleted = true,
            .INDX => {
                if (INDX != null) return error.SubrecordRedeclared;

                INDX = try util.getLittle(u32, subrecord.payload);
            },
            .MEDT => {
                if (meta.MEDT) return error.SubrecordRedeclared;
                meta.MEDT = true;

                new_MGEF.MEDT = try util.getLittle(MEDT, subrecord.payload);
            },
            // zig fmt: off
            inline .ITEX, .PTEX, .BSND, .CSND, .HSND, .ASND, .CVFX, .BVFX, .HVFX, .AVFX,
            .DESC => |known| {
                // zig fmt: on
                const tag = @tagName(known);
                if (@field(new_MGEF, tag) != null) return error.SubrecordRedeclared;

                @field(new_MGEF, tag) = subrecord.payload;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    if (INDX) |indx| {
        inline for (std.meta.fields(@TypeOf(meta))) |field| {
            if (!@field(meta, field.name)) {
                if (new_MGEF.deleted) {
                    if (record_map.getPtr(indx)) |existing| existing.deleted = true;
                    return;
                }
                return error.MissingRequiredSubrecord;
            }
        }

        return record_map.put(allocator, indx, new_MGEF);
    } else return error.MissingRequiredSubrecord;
}

pub fn writeAll(
    _: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.AutoArrayHashMapUnmanaged(u32, MGEF),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    for (record_map.keys(), record_map.values()) |k, v| {
        // TODO: write a test case for this
        var key_buffer: [15]u8 = undefined; // 2^32 is 10 characters, .json is 5
        const key = blk: {
            var key_stream = std.io.fixedBufferStream(&key_buffer);
            var key_writer = key_stream.writer();
            key_writer.print("{d}.json", .{k}) catch unreachable;
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

        inline for (std.meta.fields(MGEF)[1..]) |field| {
            try json_stream.objectField(field.name);
            try util.emitField(&json_stream, @field(v, field.name));
        }

        try json_stream.endObject();
        try buffered_writer.flush();
    }
}
