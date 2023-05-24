const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const FADT = extern struct {
    const rank = extern struct {
        attribute_mods: [2]u32 align(1),
        skill_mods: [2]u32 align(1),
        react_mod: u32 align(1),
    };
    attributes: [2]u32 align(1),
    ranks: [10]rank align(1),
    skills: [7]i32 align(1),
    flags: u32 align(1),
};

const ANAM = struct {
    faction: []const u8,
    reaction: i32,
};

deleted: bool,
FNAM: []const u8 = undefined,
FADT: FADT = undefined,
RNAM: ?[][]const u8 = null,
ANAM: ?[]ANAM = null,

const FACT = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(FACT),
    record: []const u8,
    start: u32,
    flag: u32,
) !void {
    var new_FACT: FACT = .{ .deleted = util.truncateRecordFlag(flag) & 0x1 != 0 };
    var NAME: ?[]const u8 = null;

    var meta: struct {
        FNAM: bool = false,
        FADT: bool = false,
    } = .{};

    var new_RNAM: std.ArrayListUnmanaged([]const u8) = .{};
    defer new_RNAM.deinit(allocator);
    var new_ANAM: std.StringArrayHashMapUnmanaged(i32) = .{};
    defer new_ANAM.deinit(allocator);

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_FACT.deleted = true,
            .NAME => {
                if (NAME != null) return error.SubrecordRedeclared;

                NAME = subrecord.payload;
            },
            .FNAM => {
                if (meta.FNAM) return error.SubrecordRedeclared;
                meta.FNAM = true;

                new_FACT.FNAM = subrecord.payload;
            },
            .FADT => {
                if (meta.FADT) return error.SubrecordRedeclared;
                meta.FADT = true;

                new_FACT.FADT = try util.getLittle(FADT, subrecord.payload);
            },
            .RNAM => try new_RNAM.append(allocator, subrecord.payload),
            .ANAM => {
                const should_be_INTV = try iterator.next(logger, plugin_name, start) orelse
                    return error.MissingRequiredSubrecord;
                if (should_be_INTV.tag != .INTV) return error.MissingRequiredSubrecord;

                if (new_ANAM.get(subrecord.payload) == null) {
                    try new_ANAM.put(
                        allocator,
                        subrecord.payload,
                        try util.getLittle(i32, should_be_INTV.payload),
                    );
                }
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    if (NAME) |name| {
        inline for (std.meta.fields(@TypeOf(meta))) |field| {
            if (!@field(meta, field.name)) {
                if (new_FACT.deleted) {
                    if (record_map.getPtr(name)) |existing| existing.deleted = true;
                    return;
                }
                return error.MissingRequiredSubrecord;
            }
        }

        if (record_map.get(name)) |fact| {
            if (fact.RNAM) |rnam| allocator.free(rnam);
            if (fact.ANAM) |anam| allocator.free(anam);
        }

        if (new_RNAM.items.len > 0) new_FACT.RNAM = try new_RNAM.toOwnedSlice(allocator);
        errdefer if (new_FACT.RNAM) |rnam| allocator.free(rnam);

        if (new_ANAM.count() > 0) {
            new_FACT.ANAM = try allocator.alloc(ANAM, new_ANAM.count());
            for (new_FACT.ANAM.?, new_ANAM.keys(), new_ANAM.values()) |*anam, k, v| {
                anam.* = .{ .faction = k, .reaction = v };
            }
        }
        errdefer if (new_FACT.ANAM) |anam| allocator.free(anam);

        return record_map.put(allocator, name, new_FACT);
    } else return error.MissingRequiredSubrecord;
}

inline fn writeAnam(
    json_stream: anytype,
    _: []const u8,
    value: anytype,
) util.callback_err_type!void {
    const fact = @as(*const FACT, value);

    try json_stream.objectField("ANAM");
    if (fact.ANAM) |anam_slice| {
        try json_stream.beginObject();
        for (anam_slice) |anam| {
            try json_stream.objectField(anam.faction);
            try util.emitField(json_stream, anam.reaction);
        }
        try json_stream.endObject();
    } else try json_stream.emitNull();
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(FACT),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{
        .{"ANAM"},
    }, writeAnam);
}
