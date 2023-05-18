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
    tag: util.subs,
    payload: []const u8,
};

pub fn SubrecordIterator(comptime stream_type: type) type {
    return struct {
        stream: stream_type,

        const Self = @This();

        pub fn next(
            self: *Self,
            logger: util.Logger,
            plugin_name: []const u8,
            start: u64,
        ) !?Subrecord {
            if (self.stream.getPos() catch unreachable >= self.stream.buffer.len) return null;
            var reader = self.stream.reader();

            const tag = try util.parseSub(
                logger,
                plugin_name,
                try self.stream.getPos() + start,
                try reader.readIntNative(u32),
            );
            var len = try reader.readIntLittle(u32);
            if (len == 0) len = 1;

            const pos = self.stream.getPos() catch unreachable;
            try self.stream.seekBy(len);
            return .{
                .tag = tag,
                .payload = self.stream.buffer[pos .. pos + len],
            };
        }
    };
}
