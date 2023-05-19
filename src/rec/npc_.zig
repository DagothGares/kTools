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
    level: u16 align(1),
    attributes: [8]u8 align(1),
    skills: [27]u8 align(1),
    _garbage: u8 align(1),
    health: u16 align(1),
    magicka: u16 align(1),
    fatigue: u16 align(1),
    disposition: u8 align(1),
    reputation: u8 align(1),
    rank: u8 align(1),
    _garbage2: u8 align(1),
    gold: u32 align(1),
};

flag: u2,
FLAG: u32 = undefined,
RNAM: []const u8 = undefined,
CNAM: []const u8 = undefined,
ANAM: []const u8 = undefined,
BNAM: []const u8 = undefined,
KNAM: []const u8 = undefined,
NPDT: union { short: NPDT_12, long: NPDT_52 } = undefined,
MODL: ?[]const u8 = null,
FNAM: ?[]const u8 = null,
SCRI: ?[]const u8 = null,
AIDT: ?AIDT = null,
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
    var NAME: []const u8 = undefined;

    var meta: struct {
        NAME: bool = false,
        FLAG: bool = false,
        RNAM: bool = false,
        CNAM: bool = false,
        ANAM: bool = false,
        BNAM: bool = false,
        KNAM: bool = false,
        NPDT: bool = false,
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
            .DELE => new_NPC.flag |= 0x1,
            .NAME => {
                if (meta.NAME) return error.SubrecordRedeclared;
                meta.NAME = true;

                NAME = subrecord.payload;
            },
            .FLAG => {
                if (meta.FLAG) return error.SubrecordRedeclared;
                meta.FLAG = true;

                new_NPC.FLAG = util.getLittle(u32, subrecord.payload);
            },
            .NPDT => {
                if (meta.NPDT) return error.SubrecordRedeclared;
                meta.NPDT = true;

                switch (subrecord.payload.len) {
                    12 => new_NPC.NPDT = .{ .short = util.getLittle(NPDT_12, subrecord.payload) },
                    52 => new_NPC.NPDT = .{ .long = util.getLittle(NPDT_52, subrecord.payload) },
                    else => return error.NPDT_WrongSize,
                }
            },
            inline .RNAM, .CNAM, .ANAM, .BNAM, .KNAM => |known| {
                const tag = @tagName(known);
                if (@field(meta, tag)) return error.SubrecordRedeclared;
                @field(meta, tag) = true;

                @field(new_NPC, tag) = subrecord.payload;
            },
            .AIDT => {
                if (new_NPC.AIDT != null) return error.SubrecordRedeclared;

                new_NPC.AIDT = util.getLittle(AIDT, subrecord.payload);
            },
            inline .MODL, .FNAM, .SCRI => |known| {
                const tag = @tagName(known);
                if (@field(new_NPC, tag) != null) return error.SubrecordRedeclared;

                @field(new_NPC, tag) = subrecord.payload;
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

    if (new_NPCO.items.len > 0) new_NPC.NPCO = try new_NPCO.toOwnedSlice(allocator);
    errdefer if (new_NPC.NPCO) |npco| allocator.free(npco);

    if (new_NPCS.items.len > 0) new_NPC.NPCS = try new_NPCS.toOwnedSlice(allocator);
    errdefer if (new_NPC.NPCS) |npcs| allocator.free(npcs);

    if (new_DODT.items.len > 0) new_NPC.DODT = try new_DODT.toOwnedSlice(allocator);
    errdefer if (new_NPC.DODT) |dodt| allocator.free(dodt);

    if (new_AI.items.len > 0) new_NPC.AI__ = try new_AI.toOwnedSlice(allocator);
    errdefer if (new_NPC.AI__) |ai__| allocator.free(ai__);

    try record_map.put(allocator, NAME, new_NPC);
}

inline fn writeNpdtAi(
    json_stream: anytype,
    _: []const u8,
    value: anytype,
) util.callback_err_type!void {
    const npc = @as(*const NPC_, value);
    const ignored = std.ComptimeStringMap(void, .{ .{"_garbage"}, .{"attributes"}, .{"skills"} });

    try json_stream.objectField("NPDT");
    if (npc.FLAG & 0x10 != 0) try util.emitField(json_stream, npc.NPDT.short) else {
        const long = &npc.NPDT.long;
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
    try json_stream.beginArray();
    if (npc.AI__) |ai_list| {
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
    record_map: std.StringArrayHashMapUnmanaged(NPC_),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    // TODO: possibly output NPCOs as an Object instead of an Array
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 10, .{
        .{"NPDT"},
        .{"AI__"},
    }, writeNpdtAi);
}
