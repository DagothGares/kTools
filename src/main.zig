const std = @import("std");
const builtin = @import("builtin");

const argsParser = @import("zig-args");
const build_info = @import("build-info");

const cache = @import("cache.zig");
const util = @import("util.zig");

fn printHelpMessage(allocator: std.mem.Allocator, writer: anytype) !void {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    try writer.print(
        "Usage: {s} [options] <input_file> <output_dir>\n\n" ++
            "Options:\n" ++
            "\t-h --help\tShow this help message and exit.\n" ++
            "\t-v --version\tShow version information and exit.\n" ++
            //"\t-c --codepage\tSets the ANSI codepage to use when reading plugins. (1250-1252).\n" ++
            "\t   --log-level\tSets how verbose kTools logging should be. 0-4, 0 is least verbose.\n",

        .{args.next() orelse "kTools"},
    );
}

fn printVersionInfo(allocator: std.mem.Allocator, writer: anytype) !void {
    const formatted_hash = try std.fmt.allocPrint(
        allocator,
        "{x}",
        .{std.fmt.fmtSliceHexLower(build_info.local_hash)},
    );
    defer allocator.free(formatted_hash);

    try writer.print(
        "Semantic Version:\t{s}\n" ++
            "Source Version:  \t{s}\n" ++
            // Zig's std currently does not include methods for formatting timestamps, and I
            // can't be bothered to implement ISO 8601 on my own. (There's a library for it,
            // but it requires an additional dependency that I don't want to deal with.)
            "Timestamp:       \t{d}\n" ++
            "Build Mode:      \t{s}\n",
        .{
            build_info.semantic_version orelse "UNDEFINED",
            formatted_hash,
            build_info.date_time,
            @tagName(builtin.mode),
        },
    );
}

const plug_data = struct {
    paths_raw: []const u8,
    paths: [][]const u8,
    paths_short: [][]const u8,
    checksums: []const u32,
};

/// Given an allocator and the path to an input file, we verify that it's valid JSON besides the
/// comments, check that the format matches what we expect (a requiredDataFiles.json, edited for
/// full paths and with at least one checksum per file), and then open the path to each file and
/// take a checksum, ensuring that it matches the first one provided for that file. Ignores any
/// extra checksums; having no checksum is considered invalid.
/// If you run kTools outside of the directory it is in, the input file should be set with
/// absolute paths.
fn getPluginList(allocator: std.mem.Allocator, path: []const u8) !plug_data {
    const pluginlist_file = try std.fs.cwd().openFile(path, .{});
    defer pluginlist_file.close();
    const pluginlist_map = try util.FileMap.init(pluginlist_file, .read);
    defer pluginlist_map.deinit();

    const raw_content = pluginlist_map.slice;

    const pluginlist_raw = raw_content[
    // zig fmt: off
        std.mem.indexOf(u8, raw_content, "[") orelse return error.InvalidJSON
        .. (std.mem.lastIndexOf(u8, raw_content, "]") orelse return error.InvalidJSON) + 1
        // zig fmt: on
    ];

    var parser = std.json.Parser.init(allocator, .alloc_if_needed);
    defer parser.deinit();

    var pluginlist_json = try parser.parse(pluginlist_raw);
    defer pluginlist_json.deinit();
    const pluginlist = pluginlist_json.root.array.items;

    const paths = try allocator.alloc([]const u8, pluginlist.len);
    errdefer allocator.free(paths);
    const paths_short = try allocator.alloc([]const u8, pluginlist.len);
    var used_length: usize = 0;
    errdefer {
        for (paths_short[0..used_length]) |ptr| allocator.free(ptr);
        allocator.free(paths_short);
    }
    const checksums = try allocator.alloc(u32, pluginlist.len);
    errdefer allocator.free(checksums);

    var pathsSizeTotal: usize = 0;
    for (pluginlist, 0..) |item, i| {
        var iter = item.object.iterator();
        const entry = iter.next() orelse return error.InvalidJSON;

        pathsSizeTotal += entry.key_ptr.len;
        paths[i] = entry.key_ptr.*;
        checksums[i] = if (entry.value_ptr.array.items.len > 0)
            try std.fmt.parseInt(u32, entry.value_ptr.array.items[0].string, 0)
        else
            0;
    }
    const paths_raw = try allocator.alloc(u8, pathsSizeTotal);
    errdefer allocator.free(paths_raw);

    var cur_pos: usize = 0;
    for (paths, 0..) |key, i| {
        const length = key.len;

        std.mem.copy(u8, paths_raw[cur_pos .. cur_pos + length], key);
        paths[i] = paths_raw[cur_pos .. cur_pos + length];

        const short_name = blk: {
            const start_index = std.mem.lastIndexOfAny(u8, paths[i], "/\\");
            break :blk paths[i][if (start_index) |s| s + 1 else 0..];
        };
        paths_short[i] = try std.ascii.allocLowerString(allocator, short_name);
        used_length += 1;

        cur_pos += length;
    }

    var buffered_StdErr = std.io.bufferedWriter(std.io.getStdErr().writer());
    errdefer buffered_StdErr.flush() catch {};

    var all_checksums_match = true;
    for (paths, checksums) |path_plugin, expected| {
        const plugin_file = try std.fs.cwd().openFile(path_plugin, .{});
        defer plugin_file.close();

        var crc32 = std.hash.Crc32.init();

        const plugin_map = try util.FileMap.init(plugin_file, .read);
        defer plugin_map.deinit();

        crc32.update(plugin_map.slice);
        const actual = crc32.final();

        if (expected != actual) {
            all_checksums_match = false;

            const index_start = std.mem.lastIndexOfAny(u8, path_plugin, "/\\");

            try buffered_StdErr.writer().print("{s}: Expected checksum 0x{X}, got 0x{X}\n", .{
                path_plugin[(if (index_start) |s| s + 1 else 0)..],
                expected,
                actual,
            });
        }
    }

    if (!all_checksums_match) return error.BadHash;

    return .{
        .paths_raw = paths_raw,
        .paths = paths,
        .paths_short = paths_short,
        .checksums = checksums,
    };
}

pub fn main() !void {
    var buffered_StdOut = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer buffered_StdOut.flush() catch {};
    var gpa = switch (builtin.mode) {
        .ReleaseFast, .ReleaseSmall, .ReleaseSafe => switch (builtin.os.tag) {
            .windows => std.heap.HeapAllocator.init(),
            else => null,
        },
        .Debug => std.heap.GeneralPurposeAllocator(.{
            //.stack_trace_frames = 8,
            //.never_unmap = true,
            //.retain_metadata = true,
            //.verbose_log = true,
        }){},
    };
    defer {
        if (builtin.mode == .Debug) {
            var check = gpa.deinit();
            if (check == .leak) @panic("While exiting the program, a memory leak was detected.\n" ++
                "Please report this message along with any additional data you received.\n");
        }
    }
    const allocator = switch (builtin.mode) {
        .ReleaseFast, .ReleaseSmall, .ReleaseSafe => switch (builtin.os.tag) {
            .windows => gpa.allocator(),
            else => std.heap.c_allocator,
        },
        .Debug => gpa.allocator(),
    };

    const args = argsParser.parseForCurrentProcess(struct {
        help: bool = false,
        version: bool = false,
        @"log-level": u2 = 2,
        codepage: u11 = 1252,

        pub const shorthands = .{
            .h = "help",
            .v = "version",
        };
    }, allocator, .print) catch return printHelpMessage(allocator, buffered_StdOut.writer());
    defer args.deinit();

    if (args.options.version) return printVersionInfo(allocator, buffered_StdOut.writer());
    if (args.options.help or args.positionals.len != 2)
        return printHelpMessage(allocator, buffered_StdOut.writer());

    const plugins = try getPluginList(allocator, args.positionals[0]);
    defer {
        allocator.free(plugins.paths_raw);
        allocator.free(plugins.paths);
        for (plugins.paths_short) |ps| allocator.free(ps);
        allocator.free(plugins.paths_short);
        allocator.free(plugins.checksums);
    }

    var buffered_StdErr = std.io.bufferedWriter(std.io.getStdErr().writer());
    defer buffered_StdErr.flush() catch {};
    const logger: util.Logger = .{
        .logLevel = @intToEnum(std.log.Level, args.options.@"log-level"),
        .buffer = &buffered_StdErr,
    };

    // TODO: clean output directory before using it
    var output_directory = try std.fs.cwd().makeOpenPath(args.positionals[1], .{});
    defer output_directory.close();

    var open: struct {
        files: []std.fs.File,
        maps: []util.FileMap,
    } = blk: {
        var handles: std.ArrayListUnmanaged(std.fs.File) = .{};
        var maps: std.ArrayListUnmanaged(util.FileMap) = .{};
        defer {
            handles.deinit(allocator);
            maps.deinit(allocator);
        }
        errdefer {
            for (handles.items) |f| f.close();
            for (maps.items) |m| m.deinit();
        }

        for (plugins.paths) |path| {
            const file = try std.fs.cwd().openFile(path, .{});
            errdefer file.close();

            try handles.append(allocator, file);

            const plugin_map = try util.FileMap.init(file, .read);
            errdefer plugin_map.deinit();

            try maps.append(allocator, plugin_map);
        }

        const handle_slice = try handles.toOwnedSlice(allocator);
        errdefer allocator.free(handle_slice);

        break :blk .{
            .files = handle_slice,
            .maps = try maps.toOwnedSlice(allocator),
        };
    };
    defer {
        for (open.files) |f| f.close();
        for (open.maps) |m| m.deinit();
        allocator.free(open.files);
        allocator.free(open.maps);
    }

    var map: cache.map = .{};
    defer map.deinit(allocator);

    for (plugins.paths, open.maps, 0..) |path, plugin_map, i| {
        const short_name = blk: {
            const start_index = std.mem.lastIndexOfAny(u8, path, "/\\");
            break :blk path[if (start_index) |s| s + 1 else 0..];
        };
        try logger.info("Now parsing {s}\n", .{short_name});
        try buffered_StdErr.flush();
        try cache.cachePlugin(
            allocator,
            short_name,
            @intCast(u32, i),
            plugins.paths_short[0..i],
            plugin_map,
            &map,
            logger,
        );
    }

    try logger.info("Now writing database\n", .{});
    try logger.buffer.flush();

    // TODO: allow setting a codepage
    try cache.writeAll(allocator, &map, output_directory);
}
