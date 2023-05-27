const std = @import("std");
const util = @import("../util.zig");
const shared = @import("shared.zig");

const subs = util.subs;

const AIDT = shared.AIDT;
const NPCO = shared.NPCO;
const DODT = shared.DODT;
const AI__ = shared.AI__;

const NPDT_12 = extern struct {
    level: u16 align(1),
    disposition: u8 align(1),
    reputation: u8 align(1),
    rank: u8 align(1),
    _garbage: [3]u8 align(1),
    gold: u32 align(1),
};

const NPDT_52 = extern struct {
    level: u16 align(1) = 0,
    attributes: [8]u8 align(1) = [_]u8{0} ** 8,
    skills: [27]u8 align(1) = [_]u8{0} ** 27,
    _garbage: u8 align(1) = 0,
    health: u16 align(1) = 0,
    magicka: u16 align(1) = 0,
    fatigue: u16 align(1) = 0,
    disposition: u8 align(1) = 0,
    reputation: u8 align(1) = 0,
    rank: u8 align(1) = 0,
    _garbage2: u8 align(1) = 0,
    gold: u32 align(1) = 0,
};

flag: u2,
FLAG: u32 = 0,
AIDT: AIDT = .{},
// TODO: verify
NPDT: union { short: NPDT_12, long: NPDT_52 } = .{ .long = .{} },
RNAM: ?[]const u8 = null,
CNAM: ?[]const u8 = null,
BNAM: ?[]const u8 = null,
ANAM: ?[]const u8 = null,
KNAM: ?[]const u8 = null,
MODL: ?[]const u8 = null,
FNAM: ?[]const u8 = null,
SCRI: ?[]const u8 = null,
NPCO: ?[]NPCO = null,
NPCS: ?[][]const u8 = null,
DODT: ?[]DODT = null,
AI__: ?[]AI__ = null,

const NPC_ = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(NPC_),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_NPC: NPC_ = .{ .flag = util.truncateRecordFlag(flag) };
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
            .DELE => new_NPC.flag |= 0x1,
            .NAME => NAME = subrecord.payload,
            .FLAG => new_NPC.FLAG = try util.getLittle(u32, subrecord.payload),
            .NPDT => switch (subrecord.payload.len) {
                1...11 => return error.TooSmall,
                12...51 => new_NPC.NPDT = .{
                    .short = util.getLittle(NPDT_12, subrecord.payload) catch unreachable,
                },
                else => new_NPC.NPDT = .{
                    .long = util.getLittle(NPDT_52, subrecord.payload) catch unreachable,
                },
            },
            .AIDT => new_NPC.AIDT = try util.getLittle(AIDT, subrecord.payload),
            inline .RNAM, .CNAM, .BNAM, .ANAM, .KNAM, .MODL, .FNAM, .SCRI => |known| {
                @field(new_NPC, @tagName(known)) = subrecord.payload;
            },
            .NPCO => {
                if (subrecord.payload.len < 36) return error.TooSmall;

                try new_NPCO.append(allocator, .{
                    .count = util.getLittle(i32, subrecord.payload) catch unreachable,
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

    if (new_NPCO.items.len > 0) new_NPC.NPCO = try new_NPCO.toOwnedSlice(allocator);
    errdefer if (new_NPC.NPCO) |npco| allocator.free(npco);

    if (new_NPCS.items.len > 0) new_NPC.NPCS = try new_NPCS.toOwnedSlice(allocator);
    errdefer if (new_NPC.NPCS) |npcs| allocator.free(npcs);

    if (new_DODT.items.len > 0) new_NPC.DODT = try new_DODT.toOwnedSlice(allocator);
    errdefer if (new_NPC.DODT) |dodt| allocator.free(dodt);

    if (new_AI.items.len > 0) new_NPC.AI__ = try new_AI.toOwnedSlice(allocator);
    errdefer if (new_NPC.AI__) |ai__| allocator.free(ai__);

    return record_map.put(allocator, NAME, new_NPC);
}

inline fn writeNpdtAi(
    json_stream: anytype,
    _: []const u8,
    value: anytype,
) util.callback_err_type!void {
    const npc = @as(*const NPC_, value);
    const ignored = std.ComptimeStringMap(void, .{ .{"_garbage"}, .{"attributes"}, .{"skills"} });

    try json_stream.objectField("NPDT");
    const npdt = npc.NPDT;
    if (npc.FLAG & 0x10 != 0) try util.emitField(json_stream, npdt.short) else {
        const long = &npdt.long;
        try json_stream.beginObject();
        inline for (std.meta.fields(NPDT_52)) |field| {
            if (comptime ignored.has(field.name)) continue;

            try json_stream.objectField(field.name);
            try util.emitField(json_stream, @field(long, field.name));
        }
        try json_stream.objectField("attributes");
        try std.json.stringify(long.attributes, .{ .string = .Array }, json_stream.stream);
        json_stream.state_index -= 1;
        try json_stream.objectField("skills");
        try std.json.stringify(long.skills, .{ .string = .Array }, json_stream.stream);
        json_stream.state_index -= 1;

        try json_stream.endObject();
    }

    try json_stream.objectField("AI_");
    if (npc.AI__) |ai_list| {
        try json_stream.beginArray();
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
        try json_stream.endArray();
    } else try json_stream.emitNull();
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(NPC_),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    // TODO: possibly output NPCOs as an Object instead of an Array
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 10, .{
        .{"NPDT"},
        .{"AI__"},
    }, writeNpdtAi);
}
