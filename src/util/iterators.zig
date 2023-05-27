const std = @import("std");
const util = @import("../util.zig");

pub const Record = struct {
    tag: util.recs,
    flag: u32,
    payload: []const u8,
};

pub fn RecordIterator(comptime stream_type: type) type {
    return struct {
        stream: stream_type,

        const Self = @This();

        pub fn next(self: *Self, logger: util.Logger, plugin_name: []const u8) !?Record {
            if (self.stream.getPos() catch unreachable >= self.stream.buffer.len) return null;
            var reader = self.stream.reader();

            const tag = try util.parseRec(
                logger,
                plugin_name,
                try self.stream.getPos(),
                try reader.readIntNative(u32),
            );
            const len = try reader.readIntLittle(u32);
            try self.stream.seekBy(4);
            const flag = try reader.readIntLittle(u32);

            const pos = self.stream.getPos() catch unreachable;
            try self.stream.seekBy(len);
            return .{
                .tag = tag,
                .flag = flag,
                .payload = self.stream.buffer[pos .. pos + len],
            };
        }
    };
}

pub const Subrecord = struct {
    tag: u32,
    pos: u64,
    payload: []const u8,
};

pub fn SubrecordIterator(comptime stream_type: type) type {
    return struct {
        stream: stream_type,
        pos_offset: u64,

        const Self = @This();

        pub fn next(self: *Self) ?Subrecord {
            if (self.stream.getPos() catch unreachable >= self.stream.buffer.len) return null;
            var reader = self.stream.reader();

            const stream_pos = self.pos_offset + (self.stream.getPos() catch unreachable);

            const tag = reader.readIntLittle(u32) catch return null;
            var len = reader.readIntLittle(u32) catch return null;
            len += @boolToInt(len == 0);

            const pos = self.stream.getPos() catch unreachable;
            if (pos + len > self.stream.buffer.len) return null;
            self.stream.seekBy(len) catch unreachable;

            return .{
                .tag = tag,
                .pos = stream_pos,
                .payload = self.stream.buffer[pos .. pos + len],
            };
        }
    };
}
