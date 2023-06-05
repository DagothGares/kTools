//CELL flags (is_deleted, NAME, RGNN, NAM5, AMBI, MVRF, FRMR, is_interior, has_water, illegal_sleep, ?, behave_like_exterior)
//    NAME counts (most exterior NAMEs are empty strings and ignored)
//        indexes
//    DATA flags (u8 from u32) (0x1, 0x2, 0x4, 0x40 (cell moved to by a MVRF?), 0x80)
//    DATA grid ([2]i32)
//    RGNN offsets
//    NAM5s (rgb, [3]u8)
//    WHGTs (f32)
//    AMBI ambients (rgb)
//    AMBI sunlights (rgb)
//    AMBI fogColors (rgb)
//    AMBI fogDensities (f32)
//    counts MVRF
//        IDs (u32) -- sorted to have CNAMs before CNDTs
//        CNAM offsets
//        CNDTs ([2]i32)
//    counts FRMR
//        flags (is_deleted, persists, XSCL, ANAM, BNAM, CNAM-INDX, XSOL, XCHG, INTV, NAM9, DODT, FLTV, KNAM, TNAM, DATA)
//        IDs (u32)
//        NAME offsets
//        XSCLs (f32)
//        ANAM offsets
//        BNAM offsets
//        CNAM offsets
//            INDXes (u32)
//        XSOL offsets
//        XCHGs (f32)
//        INTVs (u32/f32)
//        NAM9s (u32)
//        counts DODT
//            DODTs ([6]f32)
//            DNAM offsets (i32, can be -1 for undefined)
//        FLTVs (u32)
//        KNAM offsets
//        TNAM offsets
//        DATAs ([6]f32)

const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

// CELLs are a little weird: they can either use a NAME as their identifier, or they use
// 2-dimensional coordinates, depending on if they're interiors or not.

const DATA = extern struct {
    flags: u32 align(1) = 0,
    grid: [2]i32 align(1) = [_]i32{ 0, 0 },
};

const AMBI = extern struct {
    ambient: [4]u8 align(1) = [_]u8{ 0, 0, 0, 0 },
    sunlight: [4]u8 align(1) = [_]u8{ 0, 0, 0, 0 },
    fog_color: [4]u8 align(1) = [_]u8{ 0, 0, 0, 0 },
    fog_density: f32 align(1) = 0,
};

const CNAM = struct {
    faction_id: []const u8,
    rank: u32 = undefined,
};

const DODT = @import("shared.zig").DODT;

const MVRF = union(enum) {
    CNAM: []const u8,
    CNDT: [2]i32,
};

const FRMR = struct {
    moved: bool = false, // used to mark a FRMR as moved (and therefore can be ignored)
    flag: u4, // deleted, persistent, initially disabled, blocked
    NAME: []const u8 = "",
    XSCL: ?f32 = null,
    ANAM: ?[]const u8 = null,
    BNAM: ?[]const u8 = null,
    CNAM: ?CNAM = null,
    XSOL: ?[]const u8 = null,
    XCHG: ?f32 = null,
    INTV: ?u32 = null, // can also be float
    NAM9: ?u32 = null,
    DODT: ?[]DODT = null,
    FLTV: ?u32 = null,
    KNAM: ?[]const u8 = null,
    TNAM: ?[]const u8 = null,
    DATA: ?[6]f32 = null,
};

pub const CELL = struct {
    deleted: bool,
    DATA: DATA = .{},
    NAME: ?[]const u8 = null,
    RGNN: ?[]const u8 = null,
    WHGT: ?f32 = null,
    NAM5: ?[4]u8 = null,
    AMBI: ?AMBI = null,
};

// Headers are replaced in whole, not sure about FRMRs.
pub const cell_data = struct {
    const Headers = struct {
        interior: std.StringArrayHashMapUnmanaged(CELL) = .{},
        exterior: std.AutoArrayHashMapUnmanaged(u64, CELL) = .{},
    };
    const MVRFs = struct {
        interior: std.StringArrayHashMapUnmanaged(
            std.AutoArrayHashMapUnmanaged(u64, MVRF),
        ) = .{},
        exterior: std.AutoArrayHashMapUnmanaged(
            u64,
            std.AutoArrayHashMapUnmanaged(u64, MVRF),
        ) = .{},
    };
    const FRMRs = struct {
        interior: std.StringArrayHashMapUnmanaged(
            std.AutoArrayHashMapUnmanaged(u64, FRMR),
        ) = .{},
        exterior: std.AutoArrayHashMapUnmanaged(
            u64,
            std.AutoArrayHashMapUnmanaged(u64, FRMR),
        ) = .{},
    };
    header: Headers = .{},
    mvrf: MVRFs = .{},
    frmr: FRMRs = .{},

    const Self = @This();

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        for (self.mvrf.exterior.values()) |*hm| hm.deinit(allocator);
        for (self.mvrf.interior.values()) |*hm| hm.deinit(allocator);
        for (self.frmr.exterior.values()) |*hm| {
            for (hm.values()) |frmr| if (frmr.DODT) |dodt| allocator.free(dodt);
            hm.deinit(allocator);
        }
        for (self.frmr.interior.values()) |*hm| {
            for (hm.values()) |frmr| if (frmr.DODT) |dodt| allocator.free(dodt);
            hm.deinit(allocator);
        }
        inline for (std.meta.fields(Self)) |field| {
            @field(self, field.name).exterior.deinit(allocator);
            @field(self, field.name).interior.deinit(allocator);
        }
    }
};

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    masters: []u32,
    data: *cell_data,
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_header: CELL = .{ .deleted = util.truncateRecordFlag(flag) & 1 != 0 };

    var new_MVRF: std.AutoArrayHashMapUnmanaged(u64, MVRF) = .{};
    var transferred_MVRF = false;
    defer if (!transferred_MVRF) new_MVRF.deinit(allocator);

    var pending_deletions: std.AutoArrayHashMapUnmanaged(u64, void) = .{};
    defer pending_deletions.deinit(allocator);

    var new_FRMR: std.AutoArrayHashMapUnmanaged(u64, FRMR) = .{};
    var transferred_FRMR = false;
    defer {
        if (!transferred_FRMR) {
            for (new_FRMR.values()) |frmr| if (frmr.DODT) |d| allocator.free(d);
            new_FRMR.deinit(allocator);
        }
    }
    var persists = true;

    var iterator: util.SubrecordIterator = .{
        .stream = std.io.fixedBufferStream(record),
        .pos_offset = start,
    };

    // All fields other than NAME and DELE ignored until DATA is loaded
    while (iterator.next()) |subrecord| {
        const sub_tag = try util.parseSub(
            logger,
            subrecord.tag,
            subrecord.pos,
            plugin_name,
        ) orelse continue;

        switch (sub_tag) {
            .DELE => new_header.deleted = true,
            .NAME => {
                // Exteriors always have NAMEs, but they can sometimes be empty strings
                if (subrecord.payload[0] != 0) new_header.NAME = subrecord.payload;
            },
            .DATA => {
                new_header.DATA = try util.getLittle(DATA, subrecord.payload);
                break;
            },
            else => {},
        }
    }

    while (iterator.next()) |subrecord| {
        const sub_tag = try util.parseSub(
            logger,
            subrecord.tag,
            subrecord.pos,
            plugin_name,
        ) orelse continue;

        switch (sub_tag) {
            .RGNN => new_header.RGNN = subrecord.payload,
            .NAM5 => {
                if (subrecord.payload.len < 4) return error.TooSmall;
                new_header.NAM5 = subrecord.payload[0..4].*;
            },
            .WHGT => new_header.WHGT = try util.getLittle(f32, subrecord.payload),
            .AMBI => new_header.AMBI = try util.getLittle(AMBI, subrecord.payload),
            .MVRF => {
                var ref_index: u64 = try util.getLittle(u32, subrecord.payload);
                ref_index |= @as(u64, masters[subrecord.payload[3]]) << 32;

                var destination: ?MVRF = null;

                var deleted = false;
                var last_pos: u64 = iterator.stream.getPos() catch unreachable;

                while (iterator.next()) |next_sub| {
                    const next_tag = try util.parseSub(
                        logger,
                        next_sub.tag,
                        next_sub.pos,
                        plugin_name,
                    ) orelse {
                        last_pos = iterator.stream.getPos() catch unreachable;
                        break;
                    };

                    switch (next_tag) {
                        .DELE => deleted = true,
                        .CNAM => destination = .{ .CNAM = next_sub.payload },
                        .CNDT => destination = .{
                            .CNDT = try util.getLittle([2]i32, next_sub.payload),
                        },
                        else => break,
                    }
                    last_pos = iterator.stream.getPos() catch unreachable;
                }

                iterator.stream.seekTo(last_pos) catch unreachable;

                if (deleted) try pending_deletions.put(allocator, ref_index, {});
                if (destination) |dest| switch (dest) {
                    .CNAM => |cnam| try new_MVRF.put(allocator, ref_index, .{ .CNAM = cnam }),
                    .CNDT => |cndt| try new_MVRF.put(allocator, ref_index, .{ .CNDT = cndt }),
                };
            },
            .FRMR => {
                var ref_index: u64 = @truncate(u24, try util.getLittle(u32, subrecord.payload));
                ref_index |= @as(u64, masters[subrecord.payload[3]]) << 32;

                var frmr: FRMR = .{ .flag = @as(u2, @boolToInt(persists)) << 1 };

                var new_DODT: std.ArrayListUnmanaged(DODT) = .{};
                defer new_DODT.deinit(allocator);

                var has_name = false;

                var last_pos: u64 = try iterator.stream.getPos();
                while (iterator.next()) |next_sub| {
                    const next_tag = try util.parseSub(
                        logger,
                        next_sub.tag,
                        next_sub.pos,
                        plugin_name,
                    ) orelse {
                        iterator.stream.seekTo(last_pos) catch unreachable;
                        break;
                    };

                    switch (next_tag) {
                        .DELE => frmr.flag |= 0x1,
                        .ZNAM => frmr.flag |= 0x4,
                        .UNAM => frmr.flag |= 0x8,
                        .NAME => {
                            // Hilariously, having more than one NAME for a FRMR will cause
                            // Morrowind.exe/the CS to hang while loading.
                            // OpenMW, on the other hand, simply expects there to only be
                            // one NAME per FRMR.
                            if (has_name) continue;
                            has_name = true;

                            frmr.NAME = next_sub.payload;
                        },
                        .CNAM => frmr.CNAM = .{
                            .faction_id = next_sub.payload,
                            .rank = blk: {
                                const pos = iterator.stream.getPos() catch unreachable;
                                const next = iterator.next() orelse break :blk 0;

                                if (try util.parseSub(
                                    logger,
                                    next.tag,
                                    next.pos,
                                    plugin_name,
                                ) orelse .DELE != .INDX) {
                                    iterator.stream.seekTo(pos) catch unreachable;
                                    break :blk 0;
                                }

                                break :blk try util.getLittle(u32, next.payload);
                            },
                        },
                        .DODT => try new_DODT.append(allocator, .{
                            .destination = try util.getLittle([6]f32, next_sub.payload),
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
                        .DATA => frmr.DATA = try util.getLittle([6]f32, next_sub.payload),
                        inline .XSCL, .XCHG, .INTV, .NAM9, .FLTV => |known| {
                            const field_type = switch (known) {
                                .XSCL, .XCHG => f32,
                                .INTV, .NAM9, .FLTV => u32,
                                else => unreachable,
                            };

                            const tag = @tagName(known);
                            @field(frmr, tag) = try util.getLittle(field_type, next_sub.payload);
                        },
                        inline .ANAM, .BNAM, .XSOL, .KNAM, .TNAM => |known| {
                            @field(frmr, @tagName(known)) = next_sub.payload;
                        },
                        else => break,
                    }
                    last_pos = iterator.stream.getPos() catch unreachable;
                }

                iterator.stream.seekTo(last_pos) catch unreachable;

                try new_FRMR.put(allocator, ref_index, frmr);
            },
            .NAM0 => persists = false,
            .INTV => {}, // rogue INTVs in Morrowind.esm
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    const is_interior = new_header.DATA.flags & 0x1 != 0;
    if (is_interior) {
        if (new_header.NAME) |name| {
            try data.header.interior.put(allocator, name, new_header);

            const mvrf_map = try data.mvrf.interior.getOrPut(allocator, name);
            if (mvrf_map.found_existing) {
                const iter = new_MVRF.iterator();
                const existing_map = mvrf_map.value_ptr;
                for (iter.keys[0..iter.len], iter.values[0..iter.len]) |key, value| {
                    try existing_map.put(allocator, key, value);
                }
            } else {
                mvrf_map.value_ptr.* = new_MVRF;
                transferred_MVRF = true;
            }

            const frmr_map = try data.frmr.interior.getOrPut(allocator, name);
            if (frmr_map.found_existing) {
                const iter = new_FRMR.iterator();
                const existing_map = frmr_map.value_ptr;
                for (iter.keys[0..iter.len], iter.values[0..iter.len]) |key, value| {
                    const frmr = try existing_map.getOrPut(allocator, key);
                    if (frmr.found_existing) {
                        if (frmr.value_ptr.*.DODT) |dodt| allocator.free(dodt);
                        frmr.value_ptr.* = value;
                    } else frmr.value_ptr.* = value;
                }
            } else {
                frmr_map.value_ptr.* = new_FRMR;
                transferred_FRMR = true;
            }

            for (pending_deletions.keys()) |k| {
                if (frmr_map.value_ptr.getPtr(k)) |frmr| frmr.flag |= 0x1;
            }
        } else return error.MissingRequiredSubrecord;
    } else {
        const grid = @bitCast(u64, new_header.DATA.grid);
        try data.header.exterior.put(allocator, grid, new_header);

        const mvrf_map = try data.mvrf.exterior.getOrPut(allocator, grid);
        if (mvrf_map.found_existing) {
            const iter = new_MVRF.iterator();
            const existing_map = mvrf_map.value_ptr;
            for (iter.keys[0..iter.len], iter.values[0..iter.len]) |key, value| {
                try existing_map.put(allocator, key, value);
            }
        } else {
            mvrf_map.value_ptr.* = new_MVRF;
            transferred_MVRF = true;
        }

        const frmr_map = try data.frmr.exterior.getOrPut(allocator, grid);
        if (frmr_map.found_existing) {
            const iter = new_FRMR.iterator();
            const existing_map = frmr_map.value_ptr;
            for (iter.keys[0..iter.len], iter.values[0..iter.len]) |key, value| {
                const frmr = try existing_map.getOrPut(allocator, key);
                if (frmr.found_existing) {
                    if (frmr.value_ptr.*.DODT) |dodt| allocator.free(dodt);
                    frmr.value_ptr.* = value;
                } else frmr.value_ptr.* = value;
            }
        } else {
            frmr_map.value_ptr.* = new_FRMR;
            transferred_FRMR = true;
        }

        for (pending_deletions.keys()) |k| {
            if (frmr_map.value_ptr.getPtr(k)) |frmr| frmr.flag |= 0x1;
        }
    }
}

fn move_forms(
    allocator: std.mem.Allocator,
    forms: *std.AutoArrayHashMapUnmanaged(u64, FRMR),
    moves: std.AutoArrayHashMapUnmanaged(u64, MVRF),
    record_map: cell_data,
) !void {
    for (moves.keys(), moves.values()) |index, mvrf| {
        const form = forms.getEntry(index) orelse continue;
        // Wait, I can't do that! I need to free the data!
        //_ = forms.orderedRemove(index);
        switch (mvrf) {
            .CNAM => |cnam| {
                var new_forms: std.AutoArrayHashMapUnmanaged(u64, FRMR) =
                    record_map.frmr.interior.get(cnam) orelse continue;
                std.debug.assert(new_forms.get(index) == null);
                try new_forms.put(allocator, index, form.value_ptr.*);
            },
            .CNDT => |cndt| {
                var new_forms: std.AutoArrayHashMapUnmanaged(u64, FRMR) =
                    record_map.frmr.exterior.get(@bitCast(u64, cndt)) orelse continue;
                std.debug.assert(new_forms.get(index) == null);
                try new_forms.put(allocator, index, form.value_ptr.*);
            },
        }
        form.value_ptr.*.moved = true;
    }
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: cell_data,
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    // Alright, so this is kind of insane, but this is the point where we have to actually carry
    // out all move references and attach them to their proper cells.
    // Moves made to cells that don't exist are ignored.
    for (record_map.mvrf.interior.keys(), record_map.mvrf.interior.values()) |k, v| {
        var forms: std.AutoArrayHashMapUnmanaged(u64, FRMR) =
            record_map.frmr.interior.get(k) orelse continue;
        try move_forms(allocator, &forms, v, record_map);
    }
    for (record_map.mvrf.exterior.keys(), record_map.mvrf.exterior.values()) |k, v| {
        var forms: std.AutoArrayHashMapUnmanaged(u64, FRMR) =
            record_map.frmr.exterior.get(k) orelse continue;
        try move_forms(allocator, &forms, v, record_map);
    }

    // Because cell_data doesn't store mvrf and frmr information with the header, we can't use
    // util.writeAllGeneric for this, unfortunately.
    for (record_map.header.interior.keys(), record_map.header.interior.values()) |k, v| {
        const translated_key = try util.getValidFilename(allocator, list_writer, k);
        defer allocator.free(translated_key);
        var sub_key = translated_key;

        var sub_dir = dir;
        const new_dir = try util.getPath(&sub_key, &sub_dir);
        defer if (new_dir) sub_dir.close();
        const out_file = try sub_dir.createFile(sub_key, .{});
        defer out_file.close();

        var buffered_writer = std.io.bufferedWriter(out_file.writer());
        var json_stream = std.json.writeStream(buffered_writer.writer(), 16);
        json_stream.whitespace.indent = .{ .space = 2 };

        try json_stream.beginObject();
        try json_stream.objectField("deleted");
        try json_stream.emitBool(v.deleted);

        inline for (std.meta.fields(CELL)[1..5]) |field| {
            try json_stream.objectField(field.name);
            try util.emitField(&json_stream, @field(v, field.name));
        }

        try json_stream.objectField("NAM5");
        if (v.NAM5) |nam5| {
            try std.json.stringify(nam5, .{ .string = .Array }, json_stream.stream);
            json_stream.state_index -= 1;
        } else try json_stream.emitNull();

        try json_stream.objectField("AMBI");
        if (v.AMBI) |ambi| {
            try json_stream.beginObject();

            try json_stream.objectField("ambient");
            try std.json.stringify(ambi.ambient, .{ .string = .Array }, json_stream.stream);
            json_stream.state_index -= 1;
            try json_stream.objectField("sunlight");
            try std.json.stringify(ambi.sunlight, .{ .string = .Array }, json_stream.stream);
            json_stream.state_index -= 1;
            try json_stream.objectField("fog_color");
            try std.json.stringify(ambi.fog_color, .{ .string = .Array }, json_stream.stream);
            json_stream.state_index -= 1;
            try json_stream.objectField("fog_density");
            try util.emitField(&json_stream, ambi.fog_density);

            try json_stream.endObject();
        } else try json_stream.emitNull();

        try json_stream.objectField("FRMR");
        const maybe_forms = record_map.frmr.interior.get(k);
        if (maybe_forms) |forms| {
            try json_stream.beginObject();
            for (forms.keys(), forms.values()) |index, frmr| {
                if (frmr.moved) continue;
                // u32 fits in, at max, 10 bytes; 2 u32's plus a dash for the middle.
                var buffer: [21]u8 = undefined;
                const full_key = blk: {
                    var fbs = std.io.fixedBufferStream(&buffer);
                    var field_writer = fbs.writer();
                    const as_u32s = @bitCast([2]u32, index);
                    field_writer.print("{d}-{d}", .{ as_u32s[1], as_u32s[0] }) catch unreachable;
                    break :blk fbs.getWritten();
                };
                try json_stream.objectField(full_key);
                try json_stream.beginObject();

                try json_stream.objectField("deleted");
                try json_stream.emitBool(frmr.flag & 0x1 != 0);
                try json_stream.objectField("persistent");
                try json_stream.emitBool(frmr.flag & 0x2 != 0);
                try json_stream.objectField("initially_disabled");
                try json_stream.emitBool(frmr.flag & 0x4 != 0);
                try json_stream.objectField("blocked");
                try json_stream.emitBool(frmr.flag & 0x8 != 0);

                try json_stream.objectField("NAME");
                try util.emitField(&json_stream, frmr.NAME);
                inline for (std.meta.fields(FRMR)[3..]) |field| {
                    // This is backwards from how we usually do it, but it makes the output tons
                    // easier to read.
                    if (@field(frmr, field.name)) |f| {
                        try json_stream.objectField(field.name);
                        try util.emitField(&json_stream, f);
                    }
                }
                try json_stream.endObject();
            }
            try json_stream.endObject();
        } else try json_stream.emitNull();

        try json_stream.endObject();
        try buffered_writer.flush();
    }

    for (record_map.header.exterior.keys(), record_map.header.exterior.values()) |k, v| {
        var key_buffer: [29]u8 = undefined;
        const key = blk: {
            var key_stream = std.io.fixedBufferStream(&key_buffer);
            var key_writer = key_stream.writer();
            const as_grid = @bitCast([2]i32, k);
            key_writer.print("{d}, {d}.json", .{ as_grid[0], as_grid[1] }) catch unreachable;
            break :blk key_stream.getWritten();
        };

        try list_writer.writer().print("\"{s}\",", .{key[0 .. key.len - 5]});

        const out_file = try dir.createFile(key, .{});
        defer out_file.close();

        var buffered_writer = std.io.bufferedWriter(out_file.writer());
        var json_stream = std.json.writeStream(buffered_writer.writer(), 16);
        json_stream.whitespace.indent = .{ .space = 2 };

        try json_stream.beginObject();
        try json_stream.objectField("deleted");
        try json_stream.emitBool(v.deleted);

        inline for (std.meta.fields(CELL)[1..5]) |field| {
            try json_stream.objectField(field.name);
            try util.emitField(&json_stream, @field(v, field.name));
        }

        try json_stream.objectField("NAM5");
        if (v.NAM5) |nam5| {
            try std.json.stringify(nam5, .{ .string = .Array }, json_stream.stream);
            json_stream.state_index -= 1;
        } else try json_stream.emitNull();

        try json_stream.objectField("AMBI");
        if (v.AMBI) |ambi| {
            try json_stream.beginObject();

            try json_stream.objectField("ambient");
            try std.json.stringify(ambi.ambient, .{ .string = .Array }, json_stream.stream);
            json_stream.state_index -= 1;
            try json_stream.objectField("sunlight");
            try std.json.stringify(ambi.sunlight, .{ .string = .Array }, json_stream.stream);
            json_stream.state_index -= 1;
            try json_stream.objectField("fog_color");
            try std.json.stringify(ambi.fog_color, .{ .string = .Array }, json_stream.stream);
            json_stream.state_index -= 1;
            try json_stream.objectField("fog_density");
            try util.emitField(&json_stream, ambi.fog_density);

            try json_stream.endObject();
        } else try json_stream.emitNull();

        try json_stream.objectField("FRMR");
        const maybe_forms = record_map.frmr.exterior.get(k);
        if (maybe_forms) |forms| {
            try json_stream.beginObject();
            for (forms.keys(), forms.values()) |index, frmr| {
                if (frmr.moved) continue;
                // u32 fits in, at max, 10 bytes; 2 u32's plus a dash for the middle.
                var buffer: [21]u8 = undefined;
                const full_key = blk: {
                    var fbs = std.io.fixedBufferStream(&buffer);
                    var field_writer = fbs.writer();
                    const as_u32s = @bitCast([2]u32, index);
                    field_writer.print("{d}-{d}", .{ as_u32s[1], as_u32s[0] }) catch unreachable;
                    break :blk fbs.getWritten();
                };
                try json_stream.objectField(full_key);
                try json_stream.beginObject();

                try json_stream.objectField("deleted");
                try json_stream.emitBool(frmr.flag & 0x1 != 0);
                try json_stream.objectField("persistent");
                try json_stream.emitBool(frmr.flag & 0x2 != 0);
                try json_stream.objectField("initially_disabled");
                try json_stream.emitBool(frmr.flag & 0x4 != 0);
                try json_stream.objectField("blocked");
                try json_stream.emitBool(frmr.flag & 0x8 != 0);

                try json_stream.objectField("NAME");
                try util.emitField(&json_stream, frmr.NAME);
                inline for (std.meta.fields(FRMR)[3..]) |field| {
                    // This is backwards from how we usually do it, but it makes the output tons
                    // easier to read.
                    if (@field(frmr, field.name)) |f| {
                        try json_stream.objectField(field.name);
                        try util.emitField(&json_stream, f);
                    }
                }
                try json_stream.endObject();
            }
            try json_stream.endObject();
        } else try json_stream.emitNull();

        try json_stream.endObject();
        try buffered_writer.flush();
    }
}
