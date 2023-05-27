const std = @import("std");
const util = @import("../util.zig");
const shared = @import("shared.zig");

const subs = util.subs;

const AIDT = shared.AIDT;
const NPCO = shared.NPCO;
const DODT = shared.DODT;
const AI__ = shared.AI__;

const NPDT = extern struct {
    creature_type: u32 align(1) = 0,
    level: u32 align(1) = 0,
    attributes: [8]u32 align(1) = [_]u32{0} ** 8,
    health: u32 align(1) = 0,
    magicka: u32 align(1) = 0,
    fatigue: u32 align(1) = 0,
    soul_strength: u32 align(1) = 0,
    combat_skill: u32 align(1) = 0,
    magic_skill: u32 align(1) = 0,
    stealth_skill: u32 align(1) = 0,
    attacks: [3][2]u32 align(1) = [_][2]u32{.{ 0, 0 }} ** 3,
    gold: u32 align(1) = 0,
};

flag: u2,
FLAG: u32 = 0,
XSCL: f32 = 1,
NPDT: NPDT = .{},
AIDT: AIDT = .{},
MODL: ?[]const u8 = null,
CNAM: ?[]const u8 = null,
FNAM: ?[]const u8 = null,
SCRI: ?[]const u8 = null,
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
    var NAME: []const u8 = "";

    var new_NPCO: std.ArrayListUnmanaged(NPCO) = .{};
    defer new_NPCO.deinit(allocator);
    var new_NPCS: std.ArrayListUnmanaged([]const u8) = .{};
    defer new_NPCS.deinit(allocator);
    var new_DODT: std.ArrayListUnmanaged(DODT) = .{};
    defer new_DODT.deinit(allocator);
    var new_AI: std.ArrayListUnmanaged(AI__) = .{};
    defer new_AI.deinit(allocator);

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
            .DELE => new_CREA.flag |= 0x1,
            .NAME => NAME = subrecord.payload,
            inline .FLAG, .NPDT, .AIDT => |known| {
                const field_type = switch (known) {
                    .FLAG => u32,
                    .NPDT => NPDT,
                    .AIDT => AIDT,
                    else => unreachable,
                };

                const tag = @tagName(known);
                @field(new_CREA, tag) = try util.getLittle(field_type, subrecord.payload);
            },
            inline .MODL, .CNAM, .FNAM, .SCRI => |known| {
                @field(new_CREA, @tagName(known)) = subrecord.payload;
            },
            .XSCL => new_CREA.XSCL = try util.getLittle(f32, subrecord.payload),
            .NPCO => {
                if (subrecord.payload.len < 36) return error.TooSmall;

                try new_NPCO.append(allocator, .{
                    .count = util.getLittle(i32, subrecord.payload[0..4]) catch unreachable,
                    .name = subrecord.payload[4..],
                });
            },
            .NPCS => try new_NPCS.append(allocator, subrecord.payload),
            .DODT => try new_DODT.append(allocator, .{
                .destination = try util.getLittle([6]f32, subrecord.payload),
                .DNAM = blk: {
                    const pos = iterator.stream.getPos() catch unreachable;
                    const next = iterator.next() orelse break :blk null;
                    if (try util.parseSub(
                        logger,
                        next.tag,
                        next.pos,
                        plugin_name,
                    ) orelse .DELE != .DNAM) {
                        iterator.stream.seekTo(pos) catch unreachable;
                        break :blk null;
                    }
                    break :blk next.payload;
                },
            }),
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

                try new_AI.append(allocator, @unionInit(AI__, tag, try util.getLittle(
                    package_type,
                    subrecord.payload,
                )));
            },
            inline .AI_E, .AI_F => |known| {
                const tag = switch (known) {
                    .AI_E => "E",
                    .AI_F => "F",
                    else => unreachable,
                };
                var ai_ef = @unionInit(AI__, tag, .{ .core = try util.getLittle(
                    AI__.ef_package,
                    subrecord.payload,
                ) });

                const pos = iterator.stream.getPos() catch unreachable;
                const next = iterator.next();

                if (next != null and try util.parseSub(
                    logger,
                    next.?.tag,
                    next.?.pos,
                    plugin_name,
                ) orelse .DELE == .CNDT) {
                    @field(ai_ef, tag).CNDT = next.?.payload;
                } else iterator.stream.seekTo(pos) catch unreachable;

                try new_AI.append(allocator, ai_ef);
            },
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
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

    return record_map.put(allocator, NAME, new_CREA);
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
                    try json_stream.objectField("ai_type");
                    try json_stream.emitString("W");
                    inline for (std.meta.fields(@TypeOf(w))[0..3]) |field| {
                        try json_stream.objectField(field.name);
                        try util.emitField(json_stream, @field(w, field.name));
                    }
                    try json_stream.objectField("idles");
                    try std.json.stringify(w.idles, .{ .string = .Array }, json_stream.stream);
                    json_stream.state_index -= 1;
                    try json_stream.endObject();
                },
                inline else => |ai| {
                    try json_stream.beginObject();
                    try json_stream.objectField("ai_type");
                    try json_stream.emitString(@tagName(ai_union));
                    inline for (std.meta.fields(@TypeOf(ai))) |field| {
                        try json_stream.objectField(field.name);
                        try util.emitField(json_stream, @field(ai, field.name));
                    }
                    try json_stream.endObject();
                },
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
