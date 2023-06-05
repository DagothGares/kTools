const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const _NAM = struct {
    name: []const u8,
    pc_level: u16 = undefined,
};

pub const lev_type = enum { LEVC, LEVI };

// LEVC and LEVI are basically the same, except one uses CNAM and the other uses INAM
lev_: lev_type,
deleted: bool,
DATA: u32 = 0,
NNAM: u8 = 0,
// TODO: make this a StringArrayHashMap that marks weights for the given levels
_NAM: ?[]_NAM = null,

const LEV_ = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(LEV_),
    record: []const u8,
    start: u64,
    flag: u32,
    comptime lev: lev_type,
) !void {
    var new_LEV: LEV_ = .{ .lev_ = lev, .deleted = util.truncateRecordFlag(flag) & 0x1 != 0 };
    var NAME: []const u8 = "";

    var new_NAM: std.ArrayListUnmanaged(_NAM) = .{};
    defer new_NAM.deinit(allocator);

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
            .DELE => new_LEV.deleted = true,
            .NAME => NAME = subrecord.payload,
            .DATA => new_LEV.DATA = try util.getLittle(u32, subrecord.payload),
            .NNAM => new_LEV.NNAM = subrecord.payload[0],
            if (lev == .LEVC) .CNAM else .INAM => try new_NAM.append(allocator, .{
                .name = subrecord.payload,
                .pc_level = blk: {
                    const pos = iterator.stream.getPos() catch unreachable;
                    const next = iterator.next() orelse break :blk 0;
                    if (try util.parseSub(
                        logger,
                        next.tag,
                        next.pos,
                        plugin_name,
                    ) orelse .DELE != .INTV) {
                        iterator.stream.seekTo(pos) catch unreachable;
                        break :blk 0;
                    }

                    break :blk try util.getLittle(u16, next.payload);
                },
            }),
            .INDX => {},
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    if (record_map.get(NAME)) |lev_| if (lev_._NAM) |_nam| allocator.free(_nam);

    if (new_NAM.items.len > 0) new_LEV._NAM = try new_NAM.toOwnedSlice(allocator);
    errdefer if (new_LEV._NAM) |_nam| allocator.free(_nam);

    return record_map.put(allocator, NAME, new_LEV);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    c_dir: std.fs.Dir,
    i_dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(LEV_),
    levc_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
    levi_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    for (record_map.keys(), record_map.values()) |k, v| {
        const translated_key = try util.getValidFilename(
            allocator,
            if (v.lev_ == .LEVC) levc_writer else levi_writer,
            k,
        );
        defer allocator.free(translated_key);
        var sub_key = translated_key;

        var sub_dir = if (v.lev_ == .LEVC) c_dir else i_dir;
        const new_dir = try util.getPath(&sub_key, &sub_dir);
        defer if (new_dir) sub_dir.close();

        const out_file = try sub_dir.createFile(sub_key, .{});
        defer out_file.close();

        var buffered_writer = std.io.bufferedWriter(out_file.writer());
        var writer = buffered_writer.writer();

        var json_stream = std.json.writeStream(writer, 6);
        json_stream.whitespace.indent = .{ .space = 2 };

        try json_stream.beginObject();
        inline for (std.meta.fields(LEV_)[1..4]) |field| {
            try json_stream.objectField(field.name);
            try util.emitField(&json_stream, @field(v, field.name));
        }

        try json_stream.objectField(if (v.lev_ == .LEVC) "CNAM" else "INAM");
        try util.emitField(&json_stream, v._NAM);

        try json_stream.endObject();
        try buffered_writer.flush();
    }
}
