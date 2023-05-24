const std = @import("std");
const util = @import("../util.zig");

// TODO: figure out how to merge this impl with ARMO

const subs = util.subs;

const CTDT = extern struct {
    clothing_type: u32 align(1),
    weight: f32 align(1),
    value: u16 align(1),
    enchant_points: u16 align(1),
};

const INDX = @import("shared.zig").INDX;

flag: u2,
MODL: []const u8 = undefined,
CTDT: CTDT = undefined,
FNAM: ?[]const u8 = null,
SCRI: ?[]const u8 = null,
ITEX: ?[]const u8 = null,
ENAM: ?[]const u8 = null,
INDX: ?[]INDX = null,

const CLOT = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(CLOT),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_CLOT: CLOT = .{ .flag = util.truncateRecordFlag(flag) };
    var NAME: ?[]const u8 = null;

    var meta: struct {
        MODL: bool = false,
        CTDT: bool = false,
    } = .{};

    var new_INDX: std.ArrayListUnmanaged(INDX) = .{};
    defer new_INDX.deinit(allocator);

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_CLOT.flag |= 0x1,
            .NAME => {
                if (NAME != null) return error.SubrecordRedeclared;

                NAME = subrecord.payload;
            },
            .MODL => {
                if (meta.MODL) return error.SubrecordRedeclared;
                meta.MODL = true;

                new_CLOT.MODL = subrecord.payload;
            },
            .CTDT => {
                if (meta.CTDT) return error.SubrecordRedeclared;
                meta.CTDT = true;

                new_CLOT.CTDT = try util.getLittle(CTDT, subrecord.payload);
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
            inline .FNAM, .SCRI, .ITEX, .ENAM => |known| {
                const tag = @tagName(known);
                if (@field(new_CLOT, tag) != null) return error.SubrecordRedeclared;

                @field(new_CLOT, tag) = subrecord.payload;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    if (NAME) |name| {
        inline for (std.meta.fields(@TypeOf(meta))) |field| {
            if (!@field(meta, field.name)) {
                if (new_CLOT.flag & 0x1 != 0) {
                    if (record_map.getPtr(name)) |existing| existing.flag |= 0x1;
                    return;
                }
                return error.MissingRequiredSubrecord;
            }
        }

        if (record_map.get(name)) |clot| if (clot.INDX) |indx| allocator.free(indx);

        if (new_INDX.items.len > 0) new_CLOT.INDX = try new_INDX.toOwnedSlice(allocator);
        errdefer if (new_CLOT.INDX) |indx| allocator.free(indx);

        return record_map.put(allocator, name, new_CLOT);
    } else return error.MissingRequiredSubrecord;
}

inline fn writeIndx(
    json_stream: anytype,
    _: []const u8,
    value: anytype,
) util.callback_err_type!void {
    const clot = @as(*const CLOT, value); // un-erase the type

    try json_stream.objectField("INDX");
    if (clot.INDX) |indx_slice| {
        try json_stream.beginObject();
        for (indx_slice) |indx| {
            switch (json_stream.state[json_stream.state_index]) {
                .complete, .value, .array_start, .array => unreachable,
                inline .object, .object_start => |known| {
                    if (known == .object) try json_stream.stream.writeByte(',');
                    json_stream.state[json_stream.state_index] = .object;
                    json_stream.state_index += 1;
                    json_stream.state[json_stream.state_index] = .value;
                    try json_stream.whitespace.outputIndent(json_stream.stream);
                    try json_stream.stream.print("\"{d}\": ", .{indx.index});
                },
            }
            try util.emitField(json_stream, .{ .bnam = indx.BNAM, .cnam = indx.CNAM });
        }
        try json_stream.endObject();
    } else try json_stream.emitNull();
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(CLOT),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{
        .{"INDX"},
    }, writeIndx);
}
