const std = @import("std");

// TODO: clean other functions into another file so this file can easily be replaced, in the event
// that a zig compiler update breaks the build setup

fn checksum_file(blake: *std.crypto.hash.Blake3, file: std.fs.File) !void {
    var buffer: [4096]u8 = undefined;

    var byte_count: usize = try file.read(&buffer);
    while (byte_count == buffer.len) {
        blake.update(&buffer);
        byte_count = try file.read(&buffer);
    }
    blake.update(buffer[0..byte_count]);
}

fn checksum_recursive(blake: *std.crypto.hash.Blake3, dir: std.fs.Dir) !void {
    var iterable = try dir.openIterableDir(
        "",
        .{ .no_follow = true },
    );
    defer iterable.close();
    var iter = iterable.iterate();

    while ((try iter.next())) |entry| {
        //if (disallowed.has(entry.name)) continue;

        switch (entry.kind) {
            .File => {
                var file = try dir.openFile(entry.name, .{});
                defer file.close();
                try checksum_file(blake, file);
            },
            .Directory => {
                var child_dir = try dir.openDir(
                    entry.name,
                    .{ .no_follow = true },
                );
                defer child_dir.close();
                try checksum_recursive(blake, child_dir);
            },
            else => {}, // ignore irregular filesystem objects
        }
    }
}

fn checksumSrcDirectory(root: std.fs.Dir, out: []u8) ?[]const u8 {
    var dir = root.openDir("src", .{ .no_follow = true }) catch return null;
    defer dir.close();

    var hash = std.crypto.hash.Blake3.init(.{});
    checksum_recursive(&hash, dir) catch return null;
    hash.final(out);

    return out;
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const build_info = b.addOptions();
    build_info.addOption(?[]const u8, "semantic_version", null);
    // git hashes require more information than we have, so we just take a checksum
    // of the current directory via BLAKE3, instead.
    var blake3_checksum: [32]u8 = .{0} ** 32;
    build_info.addOption(
        ?[]const u8,
        "local_hash",
        checksumSrcDirectory(b.build_root.handle, &blake3_checksum),
    );
    build_info.addOption(i64, "date_time", std.time.timestamp());

    const args_module = b.addModule(
        "zig-args",
        .{ .source_file = .{ .path = "src/lib/zig-args/args.zig" } },
    );

    const exe = b.addExecutable(.{
        .name = "kTv3",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addOptions("build-info", build_info);
    exe.addModule("zig-args", args_module);
    switch (optimize) {
        .ReleaseFast, .ReleaseSmall => exe.strip = true,
        else => {},
    }

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // Creates a step for unit testing.
    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/test.zig" },
        .target = target,
        .optimize = optimize,
    });

    // https://github.com/ziglang/zig/issues/15059
    // I manually applied this since it fixes the issue; however, 'zig build test' is now silent
    // unless a test fails.
    const run_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
