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
    attributes: [2]u32 align(1),
    specialization: u32 align(1),
    skills: [5][2]u32 align(1),
    flags: u32 align(1),
    autocalc: u32 align(1),
};

pub const CLAS = struct {
    deleted: bool,
    FNAM: []const u8 = undefined,
    CLDT: CLDT = undefined,
    DESC: ?[]const u8 = null,
};

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
    var NAME: []const u8 = undefined;

    var meta: struct {
        NAME: bool = false,
        FNAM: bool = false,
        CLDT: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_CLAS.deleted = true,
            .NAME => {
                if (meta.NAME) return error.SubrecordRedeclared;
                meta.NAME = true;

                NAME = subrecord.payload;
            },
            .FNAM => {
                if (meta.FNAM) return error.SubrecordRedeclared;
                meta.FNAM = true;

                new_CLAS.FNAM = subrecord.payload;
            },
            .CLDT => {
                if (meta.CLDT) return error.SubrecordRedeclared;
                meta.CLDT = true;

                new_CLAS.CLDT = util.getLittle(CLDT, subrecord.payload);
            },
            .DESC => {
                if (new_CLAS.DESC != null) return error.SubrecordRedeclared;

                new_CLAS.DESC = subrecord.payload;
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    inline for (std.meta.fields(@TypeOf(meta))) |field| {
        if (!@field(meta, field.name)) return error.MissingRequiredSubrecord;
    }

    try record_map.put(allocator, NAME, new_CLAS);
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(CLAS),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 6, .{}, null);
}
