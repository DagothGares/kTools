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
DATA: u32 = undefined,
NNAM: u8 = undefined,
// INDX ignored

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
    var NAME: []const u8 = undefined;

    var meta: struct {
        NAME: bool = false,
        DATA: bool = false,
        NNAM: bool = false,
    } = .{};

    var new_NAM: std.ArrayListUnmanaged(_NAM) = .{};
    defer new_NAM.deinit(allocator);

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_LEV.deleted = true,
            .NAME => {
                if (meta.NAME) return error.SubrecordRedeclared;
                meta.NAME = true;

                NAME = subrecord.payload;
            },
            .DATA => {
                if (meta.DATA) return error.SubrecordRedeclared;
                meta.DATA = true;

                new_LEV.DATA = util.getLittle(u32, subrecord.payload);
            },
            .NNAM => {
                if (meta.NNAM) return error.SubrecordRedeclared;
                meta.NNAM = true;

                new_LEV.NNAM = subrecord.payload[0];
            },
            if (lev == .LEVC) .CNAM else .INAM => {
                var _nam: _NAM = .{ .name = subrecord.payload };

                const should_be_INTV = try iterator.next(logger, plugin_name, start) orelse
                    return error.MissingRequiredSubrecord;
                if (should_be_INTV.tag != .INTV) return error.MissingRequiredSubrecord;
                _nam.pc_level = util.getLittle(u16, should_be_INTV.payload);

                try new_NAM.append(allocator, _nam);
            },
            .INDX => {},
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    inline for (std.meta.fields(@TypeOf(meta))) |field| {
        if (!@field(meta, field.name)) return error.MissingRequiredSubrecord;
    }

    if (record_map.get(NAME)) |lev_| if (lev_._NAM) |_nam| allocator.free(_nam);

    if (new_NAM.items.len > 0) new_LEV._NAM = try new_NAM.toOwnedSlice(allocator);
    errdefer if (new_LEV._NAM) |_nam| allocator.free(_nam);

    try record_map.put(allocator, NAME, new_LEV);
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
        const translated_key = try util.getValidFilename(allocator, k);
        defer allocator.free(translated_key);
        var sub_key = translated_key;

        try (if (v.lev_ == .LEVC) levc_writer else levi_writer).writer().print(
            "\"{s}\",",
            .{translated_key[0 .. translated_key.len - 5]},
        );

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
