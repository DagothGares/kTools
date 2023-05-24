const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const NPCO = @import("shared.zig").NPCO;

flag: u2,
MODL: []const u8 = undefined,
CNDT: f32 = undefined,
FLAG: u32 = undefined,
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
    var NAME: ?[]const u8 = null;

    var meta: struct {
        MODL: bool = false,
        CNDT: bool = false,
        FLAG: bool = false,
    } = .{};

    var new_NPCO: std.ArrayListUnmanaged(NPCO) = .{};
    defer new_NPCO.deinit(allocator);

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_CONT.flag |= 0x1,
            .NAME => {
                if (NAME != null) return error.SubrecordRedeclared;
                NAME = subrecord.payload;
            },
            .MODL => {
                if (meta.MODL) return error.SubrecordRedeclared;
                meta.MODL = true;

                new_CONT.MODL = subrecord.payload;
            },
            // TODO: apply this technique to CELL
            inline .CNDT, .FLAG => |known| {
                const tag = @tagName(known);
                if (@field(meta, tag)) return error.SubrecordRedeclared;
                @field(meta, tag) = true;

                const field_type = if (known == .CNDT) f32 else u32;
                @field(new_CONT, tag) = try util.getLittle(field_type, subrecord.payload);
            },
            .NPCO => {
                if (subrecord.payload.len < 36) return error.TooSmall;

                try new_NPCO.append(allocator, .{
                    .count = util.getLittle(i32, subrecord.payload[0..4]) catch unreachable,
                    .name = subrecord.payload[4..],
                });
            },
            inline .FNAM, .SCRI => |known| {
                const tag = @tagName(known);
                if (@field(new_CONT, tag) != null) return error.SubrecordRedeclared;

                @field(new_CONT, tag) = subrecord.payload;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    if (NAME) |name| {
        inline for (std.meta.fields(@TypeOf(meta))) |field| {
            if (!@field(meta, field.name)) {
                if (new_CONT.flag & 0x1 != 0) {
                    if (record_map.getPtr(name)) |existing| existing.flag |= 0x1;
                    return;
                }
                return error.MissingRequiredSubrecord;
            }
        }

        if (record_map.get(name)) |cont| if (cont.NPCO) |npco| allocator.free(npco);

        if (new_NPCO.items.len > 0) new_CONT.NPCO = try new_NPCO.toOwnedSlice(allocator);
        errdefer if (new_CONT.NPCO) |npco| allocator.free(npco);

        return record_map.put(allocator, name, new_CONT);
    } else return error.MissingRequiredSubrecord;
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(CONT),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
