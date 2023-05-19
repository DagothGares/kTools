const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const SKDT = extern struct {
    attribute: u32 align(1),
    specialization: u32 align(1),
    use_values: [4]f32 align(1),
};

deleted: bool,
SKDT: SKDT = undefined,
DESC: ?[]const u8 = null,

const SKIL = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.AutoArrayHashMapUnmanaged(u32, SKIL),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_SKIL: SKIL = .{ .deleted = util.truncateRecordFlag(flag) & 0x1 != 0 };
    var INDX: u32 = undefined;

    var meta: struct {
        INDX: bool = false,
        SKDT: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_SKIL.deleted = true,
            .INDX => {
                if (meta.INDX) return error.SubrecordRedeclared;
                meta.INDX = true;

                INDX = util.getLittle(u32, subrecord.payload);
            },
            .SKDT => {
                if (meta.SKDT) return error.SubrecordRedeclared;
                meta.SKDT = true;

                new_SKIL.SKDT = util.getLittle(SKDT, subrecord.payload);
            },
            .DESC => {
                if (new_SKIL.DESC != null) return error.SubrecordRedeclared;

                new_SKIL.DESC = subrecord.payload;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    inline for (std.meta.fields(@TypeOf(meta))) |field| {
        if (!@field(meta, field.name)) return error.MissingRequiredSubrecord;
    }

    try record_map.put(allocator, INDX, new_SKIL);
}

// mostly copied and pasted from MGEF
pub fn writeAll(
    _: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.AutoArrayHashMapUnmanaged(u32, SKIL),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    for (record_map.keys(), record_map.values()) |k, v| {
        var key_buffer: [15]u8 = undefined;
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

        inline for (std.meta.fields(SKIL)[1..]) |field| {
            try json_stream.objectField(field.name);
            try util.emitField(&json_stream, @field(v, field.name));
        }

        try json_stream.endObject();
        try buffered_writer.flush();
    }
}
