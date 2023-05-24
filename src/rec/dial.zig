const std = @import("std");
const util = @import("../util.zig");

const subs = util.subs;

const INFO = @import("info.zig");

deleted: bool,
DATA: u8 = undefined,
// TODO: this should probably just be a linked list instead
INFO: std.StringArrayHashMapUnmanaged(INFO) = .{},

const DIAL = @This();

pub fn parse(
    allocator: std.mem.Allocator,
    logger: util.Logger,
    plugin_name: []const u8,
    record_map: *std.StringArrayHashMapUnmanaged(DIAL),
    record: []const u8,
    start: u64,
    flag: u32,
) !*DIAL {
    var new_DIAL: DIAL = .{ .deleted = util.truncateRecordFlag(flag) & 0x1 != 0 };
    var NAME: ?[]const u8 = null;

    var meta: struct {
        DATA: bool = false,
    } = .{};

    var iterator: util.SubrecordIterator = .{ .stream = std.io.fixedBufferStream(record) };

    while (try iterator.next(logger, plugin_name, start)) |subrecord| {
        switch (subrecord.tag) {
            .DELE => new_DIAL.deleted = true,
            .NAME => {
                if (NAME != null) return error.SubrecordRedeclared;

                NAME = subrecord.payload;
            },
            .DATA => {
                if (meta.DATA) return error.SubrecordRedeclared;
                meta.DATA = true;

                new_DIAL.DATA = subrecord.payload[0];
            },
            else => return util.errUnexpectedSubrecord(logger, subrecord.tag),
        }
    }

    if (NAME) |name| {
        const dial = try record_map.getOrPut(allocator, name);
        const ptr = dial.value_ptr;
        ptr.deleted = new_DIAL.deleted;
        inline for (std.meta.fields(@TypeOf(meta))) |field| {
            if (!@field(meta, field.name)) {
                if (new_DIAL.deleted and dial.found_existing) return ptr;
                return error.MissingRequiredSubrecord;
            }
        }

        ptr.DATA = new_DIAL.DATA;
        if (!dial.found_existing) ptr.INFO = .{};

        return ptr;
    } else return error.MissingRequiredSubrecord;
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    record_map: std.StringArrayHashMapUnmanaged(DIAL),
    list_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer),
) !void {
    return util.writeAllGeneric(allocator, dir, record_map, list_writer, 10, .{
        .{"INFO"},
    }, INFO.writeAll);
}
