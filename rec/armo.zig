const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const AODT = extern struct {
    armor_type: u32 align(1),
    weight: f32 align(1),
    value: u32 align(1),
    durability: u32 align(1),
    enchant_points: u32 align(1),
    armor_rating: u32 align(1),
};

const INDX = @import("shared.zig").INDX;

pub const ARMO = struct {
    flag: u2,
    MODL: []const u8 = undefined,
    FNAM: []const u8 = undefined,
    AODT: AODT = undefined,
    SCRI: ?[]const u8 = null,
    ITEX: ?[]const u8 = null,
    ENAM: ?[]const u8 = null, // passive ENAM
    INDX: ?[]INDX = null,
};

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(ARMO),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_ARMO: ARMO = .{ .flag = util.truncateRecordFlag(flag) };
    var NAME: []const u8 = undefined;

    var meta: struct {
        NAME: bool = false,
        MODL: bool = false,
        FNAM: bool = false,
        AODT: bool = false,
    } = .{};

    var new_INDX: std.ArrayListUnmanaged(INDX) = .{};
    defer new_INDX.deinit(allocator);

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_ARMO.flag |= 0x1,
            .NAME => {
                if (meta.NAME) return error.SubrecordRedeclared;
                meta.NAME = true;

                NAME = subrecord.payload;
            },
            inline .MODL, .FNAM => |known| {
                const tag = @tagName(known);
                if (@field(meta, tag)) return error.SubrecordRedeclared;
                @field(meta, tag) = true;

                @field(new_ARMO, tag) = subrecord.payload;
            },
            .AODT => {
                if (meta.AODT) return error.SubrecordRedeclared;
                meta.AODT = true;

                new_ARMO.AODT = util.getLittle(AODT, subrecord.payload);
            },
            .INDX => {
                std.debug.assert(subrecord.payload.len == 1);
                var indx: INDX = .{ .index = subrecord.payload[0] };

                var last_pos: u64 = try iterator.stream.getPos();

                while (try iterator.next(logger, plugin_name, start)) |next_sub| {
                    switch (next_sub.tag) {
                        inline .BNAM, .CNAM => |known| {
                            const tag = @tagName(known);
                            if (@field(indx, tag) != null) continue;

                            @field(indx, tag) = next_sub.payload;
                        },
                        else => break,
                    }
                    last_pos = try iterator.stream.getPos();
                }

                try iterator.stream.seekTo(last_pos);

                try new_INDX.append(allocator, indx);
            },
            inline .SCRI, .ITEX, .ENAM => |known| {
                const tag = @tagName(known);
                if (@field(new_ARMO, tag) != null) return error.SubrecordRedeclared;

                @field(new_ARMO, tag) = subrecord.payload;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    inline for (std.meta.fields(@TypeOf(meta))) |field| {
        if (!@field(meta, field.name)) return error.MissingRequiredSubrecord;
    }

    if (record_map.get(NAME)) |armo| if (armo.INDX) |i| allocator.free(i);

    if (new_INDX.items.len > 0) new_ARMO.INDX = try new_INDX.toOwnedSlice(allocator);
    errdefer if (new_ARMO.INDX) |indx| allocator.free(indx);

    try record_map.put(allocator, NAME, new_ARMO);
}

inline fn writeIndx(
    allocator: std.mem.Allocator,
    json_stream: anytype,
    _: []const u8,
    value: anytype,
) util.callback_err_type!void {
    const armo = @as(*const ARMO, value); // un-erase the type

    try json_stream.objectField("INDX");
    if (armo.INDX) |indx_slice| {
        try json_stream.beginObject();
        for (indx_slice) |indx| {
            const as_str = try std.fmt.allocPrint(allocator, "{d}", .{indx.index});
            defer allocator.free(as_str);
            try json_stream.objectField(as_str);
            try util.emitField(
                allocator,
                json_stream,
                .{ .bnam = indx.BNAM, .cnam = indx.CNAM },
            );
        }
        try json_stream.endObject();
    } else try json_stream.emitNull();
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(ARMO),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{
        .{"INDX"},
    }, writeIndx);
}
