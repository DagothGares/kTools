//CLAS flags (generic, DESC, playable)
//    NAME indexes
//    FNAM offsets
//    CLDT attributes ([2]u3 from [2]u32)
//    CLDT specializations (u2 from u32)
//    CLDT minor skills ([5]u32)
//    CLDT major skills ([5]u32)
//    CLDT 'playable' flags (bool)
//    CLDT autocalc flags (u17(?) from u32)
//    DESC offsets

const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const CLDT = extern struct {
    attributes: [2]u32 align(1) = [_]u32{ 0, 0 },
    specialization: u32 align(1) = 0,
    skills: [5][2]u32 align(1) = [_][2]u32{.{ 0, 0 }} ** 5,
    flags: u32 align(1) = 0,
    autocalc: u32 align(1) = 0,
};

deleted: bool,
CLDT: CLDT = .{},
FNAM: ?[]const u8 = null,
DESC: ?[]const u8 = null,

const CLAS = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(CLAS),
    record: []const u8,
    start: u64,
    flag: u32,
) !void {
    var new_CLAS: CLAS = .{ .deleted = util.truncateRecordFlag(flag) & 1 != 0 };
    var NAME: []const u8 = "";

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
            .DELE => new_CLAS.deleted = true,
            .NAME => NAME = subrecord.payload,
            .FNAM => new_CLAS.FNAM = subrecord.payload,
            .CLDT => new_CLAS.CLDT = try util.getLittle(CLDT, subrecord.payload),
            .DESC => new_CLAS.DESC = subrecord.payload,
            else => try util.warnUnexpectedSubrecord(logger, sub_tag, subrecord.pos, plugin_name),
        }
    }

    return record_map.put(allocator, NAME, new_CLAS);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(CLAS),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
