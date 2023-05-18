const std = @import("std");

logLevel: std.log.Level = .err,
buffer: *std.io.BufferedWriter(4 * 1024, std.fs.File.Writer),

const Self = @This();

pub fn log(self: Self, comptime level: std.log.Level, comptime format: []const u8, args: anytype) !void {
    if (@enumToInt(level) > @enumToInt(self.logLevel)) return;

    return self.buffer.writer().print(format, args);
}

pub fn debug(self: Self, comptime format: []const u8, args: anytype) !void {
    return log(self, .debug, format, args);
}

pub fn info(self: Self, comptime format: []const u8, args: anytype) !void {
    return log(self, .info, format, args);
}

pub fn warn(self: Self, comptime format: []const u8, args: anytype) !void {
    return log(self, .warn, format, args);
}

pub fn err(self: Self, comptime format: []const u8, args: anytype) !void {
    return log(self, .err, format, args);
}
