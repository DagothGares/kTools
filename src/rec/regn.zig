const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const WEAT = struct {
    clear: u8 = undefined,
    cloudy: u8 = undefined,
    foggy: u8 = undefined,
    overcast: u8 = undefined,
    rain: u8 = undefined,
    thunder: u8 = undefined,
    ash: u8 = undefined,
    blight: u8 = undefined,
    snow: u8 = 0,
    blizzard: u8 = 0,
};

const SNAM = extern struct {
    name: [32]u8 align(1),
    chance: u8 align(1),
};

deleted: bool,
FNAM: []const u8 = undefined,
CNAM: [4]u8 = undefined,
WEAT: WEAT = .{},
BNAM: ?[]const u8 = null,
SNAM: ?[]SNAM = null,

const REGN = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(REGN),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_REGN: REGN = .{ .deleted = util.truncateRecordFlag(flag) & 0x1 != 0 };
    var NAME: ?[]const u8 = null;

    var meta: struct {
        FNAM: bool = false,
        CNAM: bool = false,
        WEAT: bool = false,
    } = .{};

    var new_SNAM: std.ArrayListUnmanaged(SNAM) = .{};
    defer new_SNAM.deinit(allocator);

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_REGN.deleted = true,
            .NAME => {
                if (NAME != null) return error.SubrecordRedeclared;

                NAME = subrecord.payload;
            },
            .FNAM => {
                if (meta.FNAM) return error.SubrecordRedeclared;
                meta.FNAM = true;

                new_REGN.FNAM = subrecord.payload;
            },
            .CNAM => {
                if (meta.CNAM) return error.SubrecordRedeclared;
                meta.CNAM = true;
                if (subrecord.payload.len < 4) return error.TooSmall;

                new_REGN.CNAM = subrecord.payload[0..4].*;
            },
            .WEAT => {
                if (meta.WEAT) return error.SubrecordRedeclared;
                meta.WEAT = true;

                const len: usize = if (subrecord.payload.len > 10) 10 else subrecord.payload.len;
                if (len < 8) return error.TooSmall;

                std.mem.copyForwards(u8, @ptrCast(*[10]u8, &new_REGN.WEAT), subrecord.payload[0..len]);
            },
            .BNAM => {
                if (new_REGN.BNAM != null) return error.SubrecordRedeclared;

                new_REGN.BNAM = subrecord.payload;
            },
            .SNAM => try new_SNAM.append(allocator, try util.getLittle(SNAM, subrecord.payload)),
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    if (NAME) |name| {
        inline for (std.meta.fields(@TypeOf(meta))) |field| {
            if (!@field(meta, field.name)) {
                if (new_REGN.deleted) {
                    if (record_map.getPtr(name)) |existing| existing.deleted = true;
                    return;
                }
                return error.MissingRequiredSubrecord;
            }
        }

        if (record_map.get(name)) |weat| if (weat.SNAM) |snam| allocator.free(snam);

        if (new_SNAM.items.len > 0) new_REGN.SNAM = try new_SNAM.toOwnedSlice(allocator);
        errdefer if (new_REGN.SNAM) |snam| allocator.free(snam);

        return record_map.put(allocator, name, new_REGN);
    } else return error.MissingRequiredSubrecord;
}

inline fn writeCnam(
    json_stream: anytype,
    _: []const u8,
    value: anytype,
) util.callback_err_type!void {
    const cnam = @as(*const REGN, value).CNAM;

    try json_stream.objectField("CNAM");
    try std.json.stringify(cnam, .{ .string = .Array }, json_stream.stream);
    json_stream.state_index -= 1;
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(REGN),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{
        .{"CNAM"},
    }, writeCnam);
}
