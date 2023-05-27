const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const SKDT = extern struct {
    attribute: u32 align(1) = 0,
    specialization: u32 align(1) = 0,
    use_values: [4]f32 align(1) = [_]f32{0} ** 4,
};

deleted: bool,
SKDT: SKDT = .{},
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
    var INDX: u32 = 0;

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
            .DELE => new_SKIL.deleted = true,
            .INDX => INDX = try util.getLittle(u32, subrecord.payload),
            .SKDT => new_SKIL.SKDT = try util.getLittle(SKDT, subrecord.payload),
            .DESC => new_SKIL.DESC = subrecord.payload,
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    return record_map.put(allocator, INDX, new_SKIL);
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
