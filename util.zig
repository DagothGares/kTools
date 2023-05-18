const std = @import("std");
const builtin = @import("builtin");

pub const FileMap = @import("util/FileMap.zig");
pub const Logger = @import("util/Logger.zig");
pub const PackedIntArrayList = @import(
    "util/packed_int_array_list.zig",
).PackedIntArrayListUnmanaged;
pub const iterators = @import("util/iterators.zig");
pub const SubrecordIterator = iterators.SubrecordIterator(std.io.FixedBufferStream([]const u8));

// TODO: make writer versions of these so we don't have to pass an allocator
pub const toUtf8 = struct {
    const map_to_utf8 = struct {
        /// Central/Eastern European languages
        pub const win1250 = [_][]const u8{
            "\u{20AC}", "\x81", "\u{201A}", "\x83", "\u{201E}", "\u{2026}", "\u{2020}", // 134
            "\u{2021}", "\x88", "\u{2030}", "\u{0160}", "\u{2039}", "\u{015A}", "\u{0164}", // 141
            "\u{017D}", "\u{0179}", "\x90", "\u{2018}", "\u{2019}", "\u{201C}", "\u{201D}", // 148
            "\u{2022}", "\u{2013}", "\u{2014}", "\x98", "\u{2122}", "\u{0161}", "\u{203A}", // 155
            "\u{015B}", "\u{0165}", "\u{017E}", "\u{017A}", "\u{00A0}", "\u{02C7}", "\u{02D8}", // 162
            "\u{0141}", "\u{00A4}", "\u{0104}", "\u{00A6}", "\u{00A7}", "\u{00A8}", "\u{00A9}", // 169
            "\u{015E}", "\u{00AB}", "\u{00AC}", "\u{00AD}", "\u{00AE}", "\u{017B}", "\u{00B0}", // 176
            "\u{00B1}", "\u{02DB}", "\u{0142}", "\u{00B4}", "\u{00B5}", "\u{00B6}", "\u{00B7}", // 183
            "\u{00B8}", "\u{0105}", "\u{015F}", "\u{00BB}", "\u{013D}", "\u{02DD}", "\u{013E}", // 190
            "\u{017C}", "\u{0154}", "\u{00C1}", "\u{00C2}", "\u{0102}", "\u{00C4}", "\u{0139}", // 197
            "\u{0106}", "\u{00C7}", "\u{010C}", "\u{00C9}", "\u{0118}", "\u{00CB}", "\u{011A}", // 204
            "\u{00CD}", "\u{00CE}", "\u{010E}", "\u{0110}", "\u{0143}", "\u{0147}", "\u{00D3}", // 211
            "\u{00D4}", "\u{0150}", "\u{00D6}", "\u{00D7}", "\u{0158}", "\u{016E}", "\u{00DA}", // 218
            "\u{0170}", "\u{00DC}", "\u{00DD}", "\u{0162}", "\u{00DF}", "\u{0155}", "\u{00E1}", // 225
            "\u{00E2}", "\u{0103}", "\u{00E4}", "\u{013A}", "\u{0107}", "\u{00E7}", "\u{010D}", // 232
            "\u{00E9}", "\u{0119}", "\u{00EB}", "\u{011B}", "\u{00ED}", "\u{00EE}", "\u{010F}", // 239
            "\u{0111}", "\u{0144}", "\u{0148}", "\u{00F3}", "\u{00F4}", "\u{0151}", "\u{00F6}", // 246
            "\u{00F7}", "\u{0159}", "\u{016F}", "\u{00FA}", "\u{0171}", "\u{00FC}", "\u{00FD}", // 253
            "\u{0163}", "\u{02D9}", // 255
        };
        /// Cyrillic languages
        pub const win1251 = [_][]const u8{
            "\u{0402}", "\u{0403}", "\u{201A}", "\u{0453}", "\u{201E}", "\u{2026}", "\u{2020}", // 134
            "\u{2021}", "\u{20AC}", "\u{2030}", "\u{0409}", "\u{2039}", "\u{040A}", "\u{040C}", // 141
            "\u{040B}", "\u{040F}", "\u{0452}", "\u{2018}", "\u{2019}", "\u{201C}", "\u{201D}", // 148
            "\u{2022}", "\u{2013}", "\u{2014}", "\x98", "\u{2122}", "\u{0459}", "\u{203A}", // 155
            "\u{045A}", "\u{045C}", "\u{045B}", "\u{045F}", "\u{00A0}", "\u{040E}", "\u{045E}", // 162
            "\u{0408}", "\u{00A4}", "\u{0490}", "\u{00A6}", "\u{00A7}", "\u{0401}", "\u{00A9}", // 169
            "\u{0404}", "\u{00AB}", "\u{00AC}", "\u{00AD}", "\u{00AE}", "\u{0407}", "\u{00B0}", // 176
            "\u{00B1}", "\u{0406}", "\u{0456}", "\u{0491}", "\u{00B5}", "\u{00B6}", "\u{00B7}", // 183
            "\u{0451}", "\u{2116}", "\u{0454}", "\u{00BB}", "\u{0458}", "\u{0405}", "\u{0455}", // 190
            "\u{0457}", // 191
        };
        /// Latin-derived languages (default)
        pub const win1252 = [_][]const u8{
            "\u{20AC}", "\x81", "\u{201A}", "\u{0192}", "\u{201E}", "\u{2026}", "\u{2020}", // 134
            "\u{2021}", "\u{02C6}", "\u{2030}", "\u{0160}", "\u{2039}", "\u{0152}", "\x8D", // 141
            "\u{017D}", "\x8F", "\x90", "\u{2018}", "\u{2019}", "\u{201C}", "\u{201D}", // 148
            "\u{2022}", "\u{2013}", "\u{2014}", "\u{02DC}", "\u{2122}", "\u{0161}", "\u{203A}", // 155
            "\u{0153}", "\x9D", "\u{017E}", "\u{0178}", // 159
        };
    };
    var codepage: usize = 1252;
    pub fn set_codepage(page: usize) !void {
        switch (page) {
            1250...1252 => codepage = page,
            else => return error.InvalidCodePage,
        }
    }
    pub fn european(allocator: std.mem.Allocator, target: []const u8) ![]u8 {
        var out = try std.ArrayList(u8).initCapacity(allocator, target.len);
        errdefer out.deinit();

        for (target) |byte| {
            switch (byte) {
                0 => break,
                1...127 => try out.append(byte),
                128...255 => try out.appendSlice(map_to_utf8.win1250[byte - 128]),
            }
        }

        return out.toOwnedSlice();
    }

    pub fn cyrillic(allocator: std.mem.Allocator, target: []const u8) ![]u8 {
        var out = try std.ArrayList(u8).initCapacity(allocator, target.len);
        errdefer out.deinit();

        for (target) |byte| {
            switch (byte) {
                0 => break,
                1...127 => try out.append(byte),
                128...191 => try out.appendSlice(map_to_utf8.win1251[byte - 128]),
                192...239 => try out.appendSlice(@ptrCast(*const [2]u8, // todo: simplify
                    &std.mem.nativeToBig(u16, (0xC380 - 192 + @as(u16, byte))))),
                240...255 => try out.appendSlice(@ptrCast(*const [2]u8, &std.mem.nativeToBig(u16, (0xD090 - 240 + @as(u16, byte))))),
            }
        }

        return out.toOwnedSlice();
    }

    pub fn latin(allocator: std.mem.Allocator, target: []const u8) ![]u8 {
        var out = try std.ArrayList(u8).initCapacity(allocator, target.len);
        errdefer out.deinit();
        for (target) |byte| {
            switch (byte) {
                0 => break,
                1...127 => try out.append(byte),
                128...159 => try out.appendSlice(map_to_utf8.win1252[byte - 128]),
                160...191 => try out.appendSlice(@ptrCast(*const [2]u8, &std.mem.nativeToBig(u16, (0xC2A0 - 160 + @as(u16, byte))))),
                192...255 => try out.appendSlice(@ptrCast(*const [2]u8, &std.mem.nativeToBig(u16, (0xC380 - 192 + @as(u16, byte))))),
            }
        }

        return out.toOwnedSlice();
    }

    /// Note: All functions linked here assume the string being read is zero terminated.
    pub fn convert(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
        return switch (codepage) {
            1250 => try european(allocator, raw),
            1251 => try cyrillic(allocator, raw),
            1252 => try latin(allocator, raw),
            else => unreachable,
        };
    }
};

// todo: expand into a proper test suite
test "unicode" {
    const latin_small_u_with_acute = "ú";
    const equivalent_lsuwa = [_]u8{ 0xC3, 0xBA };
    const equivalent_lsuwa_2 = try toUtf8.convert(std.testing.allocator, "\xFA");
    defer std.testing.allocator.free(equivalent_lsuwa_2);
    try std.testing.expectEqualStrings(latin_small_u_with_acute, &equivalent_lsuwa);
    try std.testing.expectEqualStrings(latin_small_u_with_acute, equivalent_lsuwa_2);
    const right_single_quotation_mark = "’";
    const equivalent_rsqm = [_]u8{ 0xE2, 0x80, 0x99 };
    const equivalent_rsqm_2 = try toUtf8.convert(std.testing.allocator, "\x92");
    defer std.testing.allocator.free(equivalent_rsqm_2);
    try std.testing.expectEqualStrings(right_single_quotation_mark, &equivalent_rsqm);
    try std.testing.expectEqualStrings(right_single_quotation_mark, equivalent_rsqm_2);
}

/// TODO: this could probably just use a stack allocation
pub fn emitAnsiJson(allocator: std.mem.Allocator, json_stream: anytype, str: []const u8) !void {
    const is_utf8 = std.unicode.utf8ValidateSlice(str);
    const utf8_str = if (is_utf8) str else try toUtf8.convert(allocator, str);
    defer if (!is_utf8) allocator.free(utf8_str);

    const end_index = std.mem.indexOf(u8, utf8_str, "\x00") orelse utf8_str.len;
    try json_stream.emitString(utf8_str[0..end_index]);
}

pub const callback_err_type = std.os.WriteError || std.mem.Allocator.Error;

pub fn writeAllGeneric(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: anytype,
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
    comptime max_depth: comptime_int,
    // TODO: figure out some way to simplify this crap
    comptime ignored_fields: anytype,
    comptime callback: ?fn (
        allocator: std.mem.Allocator,
        stream: anytype,
        key: []const u8,
        value: anytype,
    ) callconv(.Inline) callback_err_type!void,
) !void {
    const ignored = std.ComptimeStringMap(void, if (@hasField(@TypeOf(ignored_fields), "0"))
        ignored_fields
    else
        .{.{""}});

    for (record_map.keys(), record_map.values()) |k, v| {
        const translated_key = try getValidFilename(allocator, k);
        defer allocator.free(translated_key);
        var sub_key = translated_key;

        try list_writer.writer().print("\"{s}\",", .{translated_key[0 .. translated_key.len - 5]});

        var sub_dir = dir;
        const new_dir = try getPath(&sub_key, &sub_dir);
        defer if (new_dir) sub_dir.close();
        const out_file = try sub_dir.createFile(sub_key, .{});
        defer out_file.close();

        var buffered_writer = std.io.bufferedWriter(out_file.writer());
        var json_stream = std.json.writeStream(buffered_writer.writer(), max_depth);
        json_stream.whitespace.indent = .{ .Space = 2 };

        const T = @TypeOf(v);

        try json_stream.beginObject();
        if (@hasField(T, "flag")) try emitFlags(&json_stream, v.flag) else {
            try json_stream.objectField("deleted");
            try json_stream.emitBool(v.deleted);
        }

        const fields = std.meta.fields(@TypeOf(v));
        inline for (fields[1..]) |field| {
            comptime if (ignored.has(field.name)) continue;
            try json_stream.objectField(field.name);
            try emitField(allocator, &json_stream, @field(v, field.name));
        }

        if (callback) |call| try call(allocator, &json_stream, k, &v);

        try json_stream.endObject();
        try buffered_writer.flush();
    }
}

// TODO: this needs to be rewritten in such a way that the compiler can better optimize it;
// I'm fairly certain what's being output right now is trash (or at least needs a helping hand
// from an async i/o interface like io_uring or windows registered IO)
pub fn emitField(
    allocator: std.mem.Allocator,
    stream: anytype,
    value: anytype,
) !void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .Bool => return stream.emitBool(value),
        .Optional => if (value) |v| return emitField(
            allocator,
            stream,
            v,
        ) else return stream.emitNull(),
        .Pointer => |ptr_info| switch (ptr_info.size) {
            .One => switch (@typeInfo(ptr_info.child)) {
                .Array => {
                    const Slice = []const std.meta.Elem(ptr_info.child);
                    return emitField(allocator, stream, @as(Slice, value));
                },
                else => return emitField(allocator, stream, value.*),
            },
            .Slice => {
                if (ptr_info.child == u8) return try emitAnsiJson(allocator, stream, value);
                try stream.beginArray();
                for (value) |v| {
                    try stream.arrayElem();
                    try emitField(allocator, stream, v);
                }
                try stream.endArray();
            },
            else => @compileError("Not implemented for type '" ++ @typeName(T) ++ "'"),
        },
        .Array => |arr_info| {
            switch (@typeInfo(arr_info.child)) {
                .Int => {
                    if (arr_info.child == u8) return emitAnsiJson(allocator, stream, &value);
                    try std.json.stringify(value, .{}, stream.stream);
                    stream.state_index -= 1;
                },
                .Float => {
                    stream.whitespace.indent = .{ .None = {} };
                    try stream.beginArray();
                    for (value) |v| {
                        try stream.arrayElem();
                        try emitField(allocator, stream, v);
                    }
                    try stream.endArray();
                    stream.whitespace.indent = .{ .Space = 2 };
                },
                else => {
                    try stream.beginArray();
                    for (value) |v| {
                        try stream.arrayElem();
                        try emitField(allocator, stream, v);
                    }
                    try stream.endArray();
                },
            }
        },
        .Struct => {
            try stream.beginObject();
            inline for (std.meta.fields(T)) |field| {
                if (comptime std.mem.indexOf(u8, field.name, "_garbage") != null) continue;
                try stream.objectField(field.name);
                try emitField(allocator, stream, @field(value, field.name));
            }
            try stream.endObject();
        },
        .Int => return stream.emitNumber(value),
        .Float => { // emitNumber sucks when it comes to floats
            if (value > -1_000_000_000 and value < 1_000_000_000) {
                try stream.stream.print("{d}", .{value});
            } else try stream.stream.print("{}", .{value});
            stream.state_index -= 1;
        },
        .Union => |union_info| if (union_info.tag_type != null) {
            return switch (value) {
                inline else => |v| return emitField(allocator, stream, v),
            };
        } else @compileError("Cannot infer value of non-enumerated union '" ++ @typeName(T) ++ "'"),
        else => @compileError("Not implemented for type '" ++ @typeName(T) ++ "'"),
    }
}

pub fn emitFlags(stream: anytype, flags: u2) !void {
    try stream.objectField("deleted");
    try stream.emitBool(flags & 0x1 != 0);
    try stream.objectField("persistent");
    try stream.emitBool(flags & 0x2 != 0);
}

pub fn getPath(key: *[]const u8, dir: *std.fs.Dir) !bool {
    if (std.mem.lastIndexOfAny(u8, key.*, "/\\")) |cutoff| {
        dir.* = try dir.*.makeOpenPath(key.*[0..cutoff], .{});
        key.* = key.*[cutoff + 1 ..];
        return true;
    } else return false;
}

pub fn getValidFilename(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    const is_windows = builtin.os.tag == .windows;
    // microsoft-ism
    const prefixed = if (is_windows) blk: {
        const invalid_names = std.ComptimeStringMap(void, .{
            .{"CON"},  .{"PRN"},  .{"AUX"},  .{"NUL"},  .{"COM0"}, .{"COM1"}, .{"COM2"}, .{"COM3"},
            .{"COM4"}, .{"COM5"}, .{"COM6"}, .{"COM7"}, .{"COM8"}, .{"COM9"}, .{"LPT0"}, .{"LPT1"},
            .{"LPT2"}, .{"LPT3"}, .{"LPT4"}, .{"LPT5"}, .{"LPT6"}, .{"LPT7"}, .{"LPT8"}, .{"LPT9"},
        });
        break :blk invalid_names.has(str[0 .. std.mem.indexOf(u8, str, ".") orelse str.len]);
    } else false;
    // bethesda-ism
    const no_sentinel = str[str.len - 1] != '\x00';

    const raw_copy = try allocator.alloc(
        u8,
        str.len + 4 + @boolToInt(prefixed) + @boolToInt(no_sentinel),
    );
    if (is_windows) raw_copy[0] = '_';

    _ = std.ascii.lowerString(raw_copy[0 + @boolToInt(prefixed) ..], str);
    std.mem.copy(
        u8,
        raw_copy[raw_copy.len - 5 ..],
        ".json",
    );
    for (raw_copy[0 .. raw_copy.len - 5]) |*c| {
        switch (c.*) {
            '<', '>', '\"', '|', '*', '?', '\r', '\n', '\t' => c.* = '_',
            '.' => c.* = ',',
            ':' => c.* = ';',
            else => {},
        }
    }

    if (std.unicode.utf8ValidateSlice(raw_copy)) return raw_copy else {
        defer allocator.free(raw_copy);
        return try toUtf8.convert(allocator, raw_copy);
    }
}

pub fn truncateRecordFlag(flag: u32) u2 {
    return @truncate(u2, ((flag >> 5) & 0x1) + ((flag >> 9) & 0x2));
}

pub fn cast(comptime T: type, x: anytype) !T {
    return std.math.cast(T, x) orelse return error.CastTruncatedBits;
}

fn castNative(comptime T: type, bytes: []const u8) T {
    std.debug.assert(bytes.len == (@divExact(@bitSizeOf(T), 8)));
    return @ptrCast(*align(1) const T, bytes).*;
}

/// Stub implementation
pub fn castForeign(comptime T: type, bytes: []const u8) T {
    const real = castNative(T, bytes);
    var copy: T = undefined;
    switch (@typeInfo(T)) {
        .Int => copy = @byteSwap(real),
        // @byteswap only works on integers and integer vectors, so we cast it as an integer
        // to get the desired effect. In theory, this isn't valid for some architectures, but
        // as far as I can tell, I'm not going to run into any of these issues on the Big 3 OSes
        // except for maybe a very small, very niche subset of embedded ARM devices, so we should
        // be safe.
        .Float => {
            const as_int = std.meta.Int(.unsigned, @typeInfo(T).Float.bits);
            copy = @bitCast(T, @byteSwap(@bitCast(as_int, copy)));
        },
        .Array => {
            switch (@typeInfo(T).Array.child) {
                .Int => {
                    for (copy, real) |*c, r| c.* = @byteSwap(r);
                },
                .Float => {
                    const child_type = @typeInfo(T).Array.child;
                    const as_int = std.meta.Int(
                        .unsigned,
                        @typeInfo(child_type).Float.bits,
                    );
                    for (copy, real) |*c, r| {
                        c.* = @bitCast(child_type, @byteSwap(@bitCast(as_int, r)));
                    }
                },
                else => @compileError("Arrays must be of types integer or float"),
            }
        },
        .Struct => {
            inline for (std.meta.fields(T)) |field| {
                switch (@typeInfo(field.type)) {
                    .Int => @field(copy, field.name) = @byteSwap(@field(real, field.name)),
                    .Float => {
                        const as_int = @bitCast(
                            std.meta.Int(.unsigned, @typeInfo(field.type).Float.bits),
                            @field(real, field.name),
                        );
                        @field(copy, field.name) = @bitCast(field.type, @byteSwap(as_int));
                    },
                    .Array => {
                        switch (@typeInfo(@typeInfo(field.type).Array.child)) {
                            .Int => {
                                for (@field(real, field.name), 0..) |item, i| {
                                    @field(copy, field.name)[i] = @byteSwap(item);
                                }
                            },
                            .Float => {
                                const int_type = std.meta.Int(.unsigned, @typeInfo(field.type).Float.bits);
                                for (@field(real, field.name), 0..) |item, i| {
                                    @field(copy, field.name)[i] = @bitCast(
                                        field.type,
                                        @byteSwap(@bitCast(int_type, item)),
                                    );
                                }
                            },
                            else => @compileError("Arrays must be of types integer or float"),
                        }
                    },
                    .Opaque => @compileError("Cannot byteswap an opaque field"),
                    .Vector,
                    .Pointer,
                    .Enum,
                    .Union,
                    .Optional,
                    .Struct,
                    => @compileError("Not yet implemented for type '" ++
                        @typeName(field.type) ++ "'"),
                    else => {},
                }
            }
        },
        else => @compileError("Not yet implemented for type '" ++ @typeName(T) ++ "'"),
    }
    return copy;
}

pub const getLittle = switch (builtin.cpu.arch.endian()) {
    .Little => castNative,
    .Big => castForeign,
};

pub fn parseRec(logger: Logger, plugin: []const u8, pos: u64, rec: u32) !recs {
    return std.meta.intToEnum(recs, rec) catch {
        try logger.err(
            "{s}: Expected any record at 0x{X}, got \"{s}\"\n",
            .{
                plugin,
                pos,
                @ptrCast(*const [4]u8, &rec),
            },
        );
        return error.ParserFailure;
    };
}

pub fn parseSub(logger: Logger, plugin: []const u8, pos: u64, sub: u32) !subs {
    return std.meta.intToEnum(subs, sub) catch {
        try logger.err(
            "{s}: Expected any subrecord at 0x{X}, got \"{s}\"\n",
            .{
                plugin,
                pos,
                @ptrCast(*const [4]u8, &sub),
            },
        );
        return error.ParserFailure;
    };
}

pub fn errUnexpectedSubrecord(logger: Logger, sub: subs) anyerror {
    try logger.err(
        "Expected valid subrecord, got \"{s}\"\n",
        .{@tagName(sub)},
    );
    return error.ParserFailure;
}

pub const recs = enum(u32) {
    ACTI = std.mem.readIntNative(u32, "ACTI"),
    ALCH = std.mem.readIntNative(u32, "ALCH"),
    APPA = std.mem.readIntNative(u32, "APPA"),
    ARMO = std.mem.readIntNative(u32, "ARMO"),
    BODY = std.mem.readIntNative(u32, "BODY"),
    BOOK = std.mem.readIntNative(u32, "BOOK"),
    BSGN = std.mem.readIntNative(u32, "BSGN"),
    CELL = std.mem.readIntNative(u32, "CELL"),
    CLAS = std.mem.readIntNative(u32, "CLAS"),
    CLOT = std.mem.readIntNative(u32, "CLOT"),
    CONT = std.mem.readIntNative(u32, "CONT"),
    CREA = std.mem.readIntNative(u32, "CREA"),
    DIAL = std.mem.readIntNative(u32, "DIAL"),
    DOOR = std.mem.readIntNative(u32, "DOOR"),
    ENCH = std.mem.readIntNative(u32, "ENCH"),
    FACT = std.mem.readIntNative(u32, "FACT"),
    GLOB = std.mem.readIntNative(u32, "GLOB"),
    GMST = std.mem.readIntNative(u32, "GMST"),
    INFO = std.mem.readIntNative(u32, "INFO"),
    INGR = std.mem.readIntNative(u32, "INGR"),
    LAND = std.mem.readIntNative(u32, "LAND"),
    LEVC = std.mem.readIntNative(u32, "LEVC"),
    LEVI = std.mem.readIntNative(u32, "LEVI"),
    LIGH = std.mem.readIntNative(u32, "LIGH"),
    LOCK = std.mem.readIntNative(u32, "LOCK"),
    LTEX = std.mem.readIntNative(u32, "LTEX"),
    MGEF = std.mem.readIntNative(u32, "MGEF"),
    MISC = std.mem.readIntNative(u32, "MISC"),
    NPC_ = std.mem.readIntNative(u32, "NPC_"),
    PGRD = std.mem.readIntNative(u32, "PGRD"),
    PROB = std.mem.readIntNative(u32, "PROB"),
    RACE = std.mem.readIntNative(u32, "RACE"),
    REGN = std.mem.readIntNative(u32, "REGN"),
    REPA = std.mem.readIntNative(u32, "REPA"),
    SCPT = std.mem.readIntNative(u32, "SCPT"),
    SKIL = std.mem.readIntNative(u32, "SKIL"),
    SNDG = std.mem.readIntNative(u32, "SNDG"),
    SOUN = std.mem.readIntNative(u32, "SOUN"),
    SPEL = std.mem.readIntNative(u32, "SPEL"),
    SSCR = std.mem.readIntNative(u32, "SSCR"),
    STAT = std.mem.readIntNative(u32, "STAT"),
    TES3 = std.mem.readIntNative(u32, "TES3"),
    WEAP = std.mem.readIntNative(u32, "WEAP"),
};

pub const subs = enum(u32) {
    AADT = std.mem.readIntNative(u32, "AADT"),
    AI_A = std.mem.readIntNative(u32, "AI_A"),
    AI_E = std.mem.readIntNative(u32, "AI_E"),
    AI_F = std.mem.readIntNative(u32, "AI_F"),
    AI_T = std.mem.readIntNative(u32, "AI_T"),
    AI_W = std.mem.readIntNative(u32, "AI_W"),
    AIDT = std.mem.readIntNative(u32, "AIDT"),
    ALDT = std.mem.readIntNative(u32, "ALDT"),
    AMBI = std.mem.readIntNative(u32, "AMBI"),
    ANAM = std.mem.readIntNative(u32, "ANAM"),
    AODT = std.mem.readIntNative(u32, "AODT"),
    ASND = std.mem.readIntNative(u32, "ASND"),
    AVFX = std.mem.readIntNative(u32, "AVFX"),
    BKDT = std.mem.readIntNative(u32, "BKDT"),
    BNAM = std.mem.readIntNative(u32, "BNAM"),
    BSND = std.mem.readIntNative(u32, "BSND"),
    BVFX = std.mem.readIntNative(u32, "BVFX"),
    BYDT = std.mem.readIntNative(u32, "BYDT"),
    CLDT = std.mem.readIntNative(u32, "CLDT"),
    CNAM = std.mem.readIntNative(u32, "CNAM"),
    CNDT = std.mem.readIntNative(u32, "CNDT"),
    CSND = std.mem.readIntNative(u32, "CSND"),
    CVFX = std.mem.readIntNative(u32, "CVFX"),
    CTDT = std.mem.readIntNative(u32, "CTDT"),
    DATA = std.mem.readIntNative(u32, "DATA"),
    DELE = std.mem.readIntNative(u32, "DELE"),
    DESC = std.mem.readIntNative(u32, "DESC"),
    DNAM = std.mem.readIntNative(u32, "DNAM"),
    DODT = std.mem.readIntNative(u32, "DODT"),
    ENAM = std.mem.readIntNative(u32, "ENAM"),
    ENDT = std.mem.readIntNative(u32, "ENDT"),
    FADT = std.mem.readIntNative(u32, "FADT"),
    FLAG = std.mem.readIntNative(u32, "FLAG"),
    FLTV = std.mem.readIntNative(u32, "FLTV"),
    FNAM = std.mem.readIntNative(u32, "FNAM"),
    FRMR = std.mem.readIntNative(u32, "FRMR"),
    HEDR = std.mem.readIntNative(u32, "HEDR"),
    HSND = std.mem.readIntNative(u32, "HSND"),
    HVFX = std.mem.readIntNative(u32, "HVFX"),
    INAM = std.mem.readIntNative(u32, "INAM"),
    INDX = std.mem.readIntNative(u32, "INDX"),
    INTV = std.mem.readIntNative(u32, "INTV"),
    IRDT = std.mem.readIntNative(u32, "IRDT"),
    ITEX = std.mem.readIntNative(u32, "ITEX"),
    KNAM = std.mem.readIntNative(u32, "KNAM"),
    LHDT = std.mem.readIntNative(u32, "LHDT"),
    LKDT = std.mem.readIntNative(u32, "LKDT"),
    MAST = std.mem.readIntNative(u32, "MAST"),
    MCDT = std.mem.readIntNative(u32, "MCDT"),
    MEDT = std.mem.readIntNative(u32, "MEDT"),
    MODL = std.mem.readIntNative(u32, "MODL"),
    MVRF = std.mem.readIntNative(u32, "MVRF"),
    NAM0 = std.mem.readIntNative(u32, "NAM0"),
    NAM5 = std.mem.readIntNative(u32, "NAM5"),
    NAM9 = std.mem.readIntNative(u32, "NAM9"),
    NAME = std.mem.readIntNative(u32, "NAME"),
    NNAM = std.mem.readIntNative(u32, "NNAM"),
    NPCO = std.mem.readIntNative(u32, "NPCO"),
    NPCS = std.mem.readIntNative(u32, "NPCS"),
    NPDT = std.mem.readIntNative(u32, "NPDT"),
    ONAM = std.mem.readIntNative(u32, "ONAM"),
    PBDT = std.mem.readIntNative(u32, "PBDT"),
    PGRC = std.mem.readIntNative(u32, "PGRC"),
    PGRP = std.mem.readIntNative(u32, "PGRP"),
    PNAM = std.mem.readIntNative(u32, "PNAM"),
    PTEX = std.mem.readIntNative(u32, "PTEX"),
    QSTF = std.mem.readIntNative(u32, "QSTF"),
    QSTN = std.mem.readIntNative(u32, "QSTN"),
    QSTR = std.mem.readIntNative(u32, "QSTR"),
    RADT = std.mem.readIntNative(u32, "RADT"),
    RGNN = std.mem.readIntNative(u32, "RGNN"),
    RIDT = std.mem.readIntNative(u32, "RIDT"),
    RNAM = std.mem.readIntNative(u32, "RNAM"),
    SCDT = std.mem.readIntNative(u32, "SCDT"),
    SCHD = std.mem.readIntNative(u32, "SCHD"),
    SCRI = std.mem.readIntNative(u32, "SCRI"),
    SCTX = std.mem.readIntNative(u32, "SCTX"),
    SCVR = std.mem.readIntNative(u32, "SCVR"),
    SKDT = std.mem.readIntNative(u32, "SKDT"),
    SNAM = std.mem.readIntNative(u32, "SNAM"),
    SPDT = std.mem.readIntNative(u32, "SPDT"),
    STRV = std.mem.readIntNative(u32, "STRV"),
    TEXT = std.mem.readIntNative(u32, "TEXT"),
    TNAM = std.mem.readIntNative(u32, "TNAM"),
    UNAM = std.mem.readIntNative(u32, "UNAM"),
    VCLR = std.mem.readIntNative(u32, "VCLR"),
    VHGT = std.mem.readIntNative(u32, "VHGT"),
    VNML = std.mem.readIntNative(u32, "VNML"),
    VTEX = std.mem.readIntNative(u32, "VTEX"),
    WEAT = std.mem.readIntNative(u32, "WEAT"),
    WHGT = std.mem.readIntNative(u32, "WHGT"),
    WNAM = std.mem.readIntNative(u32, "WNAM"),
    WPDT = std.mem.readIntNative(u32, "WPDT"),
    XCHG = std.mem.readIntNative(u32, "XCHG"),
    XSCL = std.mem.readIntNative(u32, "XSCL"),
    XSOL = std.mem.readIntNative(u32, "XSOL"),
    ZNAM = std.mem.readIntNative(u32, "ZNAM"),
};
