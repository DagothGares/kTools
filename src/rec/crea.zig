const std = @import("std");
const util = @import("../util.zig");
const shared = @import("shared.zig");

const subs = util.subs;

const AIDT = shared.AIDT;
const NPCO = shared.NPCO;
const DODT = shared.DODT;
const AI__ = shared.AI__;

const NPDT = extern struct {
    creature_type: u32 align(1),
    level: u32 align(1),
    attributes: [8]u32 align(1),
    health: u32 align(1),
    magicka: u32 align(1),
    fatigue: u32 align(1),
    soul_strength: u32 align(1),
    combat_skill: u32 align(1),
    magic_skill: u32 align(1),
    stealth_skill: u32 align(1),
    attacks: [3][2]u32 align(1),
    gold: u32 align(1),
};

flag: u2,
MODL: []const u8 = undefined,
FLAG: u32 = undefined,
NPDT: NPDT = undefined,
AIDT: AIDT = undefined,
CNAM: ?[]const u8 = null,
FNAM: ?[]const u8 = null,
SCRI: ?[]const u8 = null,
XSCL: ?f32 = null,
NPCO: ?[]NPCO = null,
NPCS: ?[][]const u8 = null,
DODT: ?[]DODT = null,
AI__: ?[]AI__ = null,

const CREA = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(CREA),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_CREA: CREA = .{ .flag = util.truncateRecordFlag(flag) };
    var NAME: []const u8 = undefined;

    var meta: struct {
        NAME: bool = false,
        MODL: bool = false,
        NPDT: bool = false,
        FLAG: bool = false,
        AIDT: bool = false,
    } = .{};

    var new_NPCO: std.ArrayListUnmanaged(NPCO) = .{};
    defer new_NPCO.deinit(allocator);
    var new_NPCS: std.ArrayListUnmanaged([]const u8) = .{};
    defer new_NPCS.deinit(allocator);
    var new_DODT: std.ArrayListUnmanaged(DODT) = .{};
    defer new_DODT.deinit(allocator);
    var new_AI: std.ArrayListUnmanaged(AI__) = .{};
    defer new_AI.deinit(allocator);

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_CREA.flag |= 0x1,
            .NAME => {
                if (meta.NAME) return error.SubrecordRedeclared;
                meta.NAME = true;

                NAME = subrecord.payload;
            },
            .MODL => {
                if (meta.MODL) return error.SubrecordRedeclared;
                meta.MODL = true;

                new_CREA.MODL = subrecord.payload;
            },
            inline .FLAG, .NPDT, .AIDT => |known| {
                const tag = @tagName(known);
                if (@field(meta, tag)) return error.SubrecordRedeclared;
                @field(meta, tag) = true;

                const field_type = switch (known) {
                    .FLAG => u32,
                    .NPDT => NPDT,
                    .AIDT => AIDT,
                    else => unreachable,
                };
                @field(new_CREA, tag) = util.getLittle(field_type, subrecord.payload);
            },
            inline .CNAM, .FNAM, .SCRI => |known| {
                const tag = @tagName(known);
                if (@field(new_CREA, tag) != null) return error.SubrecordRedeclared;

                @field(new_CREA, tag) = subrecord.payload;
            },
            .XSCL => {
                if (new_CREA.XSCL != null) return error.SubrecordRedeclared;

                new_CREA.XSCL = util.getLittle(f32, subrecord.payload);
            },
            .NPCO => try new_NPCO.append(allocator, .{
                .count = util.getLittle(i32, subrecord.payload[0..4]),
                .name = subrecord.payload[4..],
            }),
            .NPCS => try new_NPCS.append(allocator, subrecord.payload),
            .DODT => {
                var dodt: DODT = .{ .destination = util.getLittle([6]f32, subrecord.payload) };

                const pos = try iterator.stream.getPos();
                const maybe_dnam = try iterator.next(logger, plugin_name, start);
                if (maybe_dnam != null and maybe_dnam.?.tag == .DNAM) {
                    dodt.DNAM = maybe_dnam.?.payload;
                } else try iterator.stream.seekTo(pos);

                try new_DODT.append(allocator, dodt);
            },
            inline .AI_A, .AI_T, .AI_W => |known| {
                const tag = switch (known) {
                    .AI_A => "A",
                    .AI_T => "T",
                    .AI_W => "W",
                    else => unreachable,
                };
                const package_type = switch (known) {
                    .AI_A => AI__.a_package,
                    .AI_T => AI__.t_package,
                    .AI_W => AI__.w_package,
                    else => unreachable,
                };

                try new_AI.append(allocator, @unionInit(AI__, tag, util.getLittle(
                    package_type,
                    subrecord.payload[0..@sizeOf(package_type)],
                )));
            },
            inline .AI_E, .AI_F => |known| {
                const tag = switch (known) {
                    .AI_E => "E",
                    .AI_F => "F",
                    else => unreachable,
                };
                var ai_ef = @unionInit(AI__, tag, .{ .core = util.getLittle(
                    AI__.ef_package,
                    subrecord.payload[0..@sizeOf(AI__.ef_package)],
                ) });

                const pos = try iterator.stream.getPos();
                const maybe_cndt = try iterator.next(logger, plugin_name, start);
                if (maybe_cndt != null and maybe_cndt.?.tag == .CNDT) {
                    @field(ai_ef, tag).CNDT = maybe_cndt.?.payload;
                } else try iterator.stream.seekTo(pos);

                try new_AI.append(allocator, ai_ef);
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    inline for (std.meta.fields(@TypeOf(meta))) |field| {
        if (!@field(meta, field.name)) return error.MissingRequiredSubrecord;
    }

    if (record_map.get(NAME)) |crea| {
        if (crea.NPCO) |npco| allocator.free(npco);
        if (crea.NPCS) |npcs| allocator.free(npcs);
        if (crea.DODT) |dodt| allocator.free(dodt);
        if (crea.AI__) |ai__| allocator.free(ai__);
    }

    if (new_NPCO.items.len > 0) new_CREA.NPCO = try new_NPCO.toOwnedSlice(allocator);
    errdefer if (new_CREA.NPCO) |npco| allocator.free(npco);

    if (new_NPCS.items.len > 0) new_CREA.NPCS = try new_NPCS.toOwnedSlice(allocator);
    errdefer if (new_CREA.NPCS) |npcs| allocator.free(npcs);

    if (new_DODT.items.len > 0) new_CREA.DODT = try new_DODT.toOwnedSlice(allocator);
    errdefer if (new_CREA.DODT) |dodt| allocator.free(dodt);

    if (new_AI.items.len > 0) new_CREA.AI__ = try new_AI.toOwnedSlice(allocator);
    errdefer if (new_CREA.AI__) |ai__| allocator.free(ai__);

    try record_map.put(allocator, NAME, new_CREA);
}

inline fn writeAi(
    json_stream: anytype,
    _: []const u8,
    value: anytype,
) util.callback_err_type!void {
    const crea = @as(*const CREA, value);

    try json_stream.objectField("AI_");
    try json_stream.beginArray();
    if (crea.AI__) |ai_list| {
        for (ai_list) |ai_union| {
            try json_stream.arrayElem();
            switch (ai_union) {
                .W => |w| {
                    try json_stream.beginObject();
                    inline for (std.meta.fields(@TypeOf(w))[0..3]) |field| {
                        try json_stream.objectField(field.name);
                        try util.emitField(json_stream, @field(w, field.name));
                    }
                    try json_stream.objectField("idles");
                    try std.json.stringify(w.idles, .{ .string = .Array }, json_stream.stream);
                    json_stream.state_index -= 1;
                    try json_stream.endObject();
                },
                inline else => |ai| try util.emitField(json_stream, ai),
            }
        }
    }
    try json_stream.endArray();
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(CREA),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 7, .{
        .{"AI__"},
    }, writeAi);
}
