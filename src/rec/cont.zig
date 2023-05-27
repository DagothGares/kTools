const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const NPCO = @import("shared.zig").NPCO;

flag: u2,
CNDT: f32 = 0,
FLAG: u32 = 0,
MODL: ?[]const u8 = null,
FNAM: ?[]const u8 = null,
SCRI: ?[]const u8 = null,
NPCO: ?[]NPCO = null,

const CONT = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(CONT),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_CONT: CONT = .{ .flag = util.truncateRecordFlag(flag) };
    var NAME: []const u8 = "";

    var new_NPCO: std.ArrayListUnmanaged(NPCO) = .{};
    defer new_NPCO.deinit(allocator);

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
            .DELE => new_CONT.flag |= 0x1,
            .NAME => NAME = subrecord.payload,
            inline .CNDT, .FLAG => |known| {
                const field_type = if (known == .CNDT) f32 else u32;
                const tag = @tagName(known);
                @field(new_CONT, tag) = try util.getLittle(field_type, subrecord.payload);
            },
            .NPCO => {
                if (subrecord.payload.len < 36) return error.TooSmall;

                try new_NPCO.append(allocator, .{
                    .count = util.getLittle(i32, subrecord.payload[0..4]) catch unreachable,
                    .name = subrecord.payload[4..],
                });
            },
            inline .MODL, .FNAM, .SCRI => |known| {
                @field(new_CONT, @tagName(known)) = subrecord.payload;
            },
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    if (record_map.get(NAME)) |cont| if (cont.NPCO) |npco| allocator.free(npco);

    if (new_NPCO.items.len > 0) new_CONT.NPCO = try new_NPCO.toOwnedSlice(allocator);
    errdefer if (new_CONT.NPCO) |npco| allocator.free(npco);

    return record_map.put(allocator, NAME, new_CONT);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(CONT),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
