const std = @import("std");
const util = @import("util.zig");
const recs = util.recs;
const subs = util.subs;

const impl = struct {
    pub const TES3 = @import("rec/tes3.zig");
    pub const ACTI = @import("rec/acti.zig");
    pub const ALCH = @import("rec/alch.zig");
    pub const APPA = @import("rec/appa.zig");
    pub const ARMO = @import("rec/armo.zig");
    pub const BODY = @import("rec/body.zig");
    pub const BOOK = @import("rec/book.zig");
    pub const BSGN = @import("rec/bsgn.zig");
    pub const CELL = @import("rec/cell.zig");
    pub const CLAS = @import("rec/clas.zig");
    pub const CLOT = @import("rec/clot.zig");
    pub const CONT = @import("rec/cont.zig");
    pub const CREA = @import("rec/crea.zig");
    pub const DIAL = @import("rec/dial.zig");
    pub const DOOR = @import("rec/door.zig");
    pub const ENCH = @import("rec/ench.zig");
    pub const FACT = @import("rec/fact.zig");
    pub const GLOB = @import("rec/glob.zig");
    pub const GMST = @import("rec/gmst.zig");
    pub const INFO = @import("rec/info.zig");
    pub const INGR = @import("rec/ingr.zig");
    pub const LAND = @import("rec/land.zig");
    pub const LEV_ = @import("rec/lev_.zig");
    pub const LIGH = @import("rec/ligh.zig");
    pub const LOCK = @import("rec/lock.zig");
    pub const LTEX = @import("rec/ltex.zig");
    pub const MGEF = @import("rec/mgef.zig");
    pub const MISC = @import("rec/misc.zig");
    pub const NPC_ = @import("rec/npc_.zig");
    pub const PGRD = @import("rec/pgrd.zig");
    //// TODO: merge PROB with LOCK
    pub const PROB = @import("rec/prob.zig");
    pub const RACE = @import("rec/race.zig");
    pub const REGN = @import("rec/regn.zig");
    pub const REPA = @import("rec/repa.zig");
    pub const SCPT = @import("rec/scpt.zig");
    pub const SKIL = @import("rec/skil.zig");
    pub const SNDG = @import("rec/sndg.zig");
    pub const SOUN = @import("rec/soun.zig");
    pub const SPEL = @import("rec/spel.zig");
    pub const SSCR = @import("rec/sscr.zig");
    pub const STAT = @import("rec/stat.zig");
    pub const WEAP = @import("rec/weap.zig");
};

pub const map = struct {
    ACTI: std.StringArrayHashMapUnmanaged(impl.ACTI) = .{},
    ALCH: std.StringArrayHashMapUnmanaged(impl.ALCH) = .{},
    APPA: std.StringArrayHashMapUnmanaged(impl.APPA) = .{},
    ARMO: std.StringArrayHashMapUnmanaged(impl.ARMO) = .{},
    BODY: std.StringArrayHashMapUnmanaged(impl.BODY) = .{},
    BOOK: std.StringArrayHashMapUnmanaged(impl.BOOK) = .{},
    BSGN: std.StringArrayHashMapUnmanaged(impl.BSGN) = .{},
    CELL: impl.CELL.cell_data = .{},
    CLAS: std.StringArrayHashMapUnmanaged(impl.CLAS) = .{},
    CLOT: std.StringArrayHashMapUnmanaged(impl.CLOT) = .{},
    CONT: std.StringArrayHashMapUnmanaged(impl.CONT) = .{},
    CREA: std.StringArrayHashMapUnmanaged(impl.CREA) = .{},
    DIAL: std.StringArrayHashMapUnmanaged(impl.DIAL) = .{},
    DOOR: std.StringArrayHashMapUnmanaged(impl.DOOR) = .{},
    ENCH: std.StringArrayHashMapUnmanaged(impl.ENCH) = .{},
    FACT: std.StringArrayHashMapUnmanaged(impl.FACT) = .{},
    GLOB: std.StringArrayHashMapUnmanaged(impl.GLOB) = .{},
    GMST: std.StringArrayHashMapUnmanaged(impl.GMST) = .{},
    INGR: std.StringArrayHashMapUnmanaged(impl.INGR) = .{},
    LAND: std.AutoArrayHashMapUnmanaged(u64, impl.LAND) = .{},
    LEV_: std.StringArrayHashMapUnmanaged(impl.LEV_) = .{},
    LIGH: std.StringArrayHashMapUnmanaged(impl.LIGH) = .{},
    LOCK: std.StringArrayHashMapUnmanaged(impl.LOCK) = .{},
    LTEX: std.StringArrayHashMapUnmanaged(impl.LTEX) = .{},
    MGEF: std.AutoArrayHashMapUnmanaged(u32, impl.MGEF) = .{},
    MISC: std.StringArrayHashMapUnmanaged(impl.MISC) = .{},
    NPC_: std.StringArrayHashMapUnmanaged(impl.NPC_) = .{},
    PGRD: impl.PGRD.pgrd_data = .{},
    PROB: std.StringArrayHashMapUnmanaged(impl.PROB) = .{},
    RACE: std.StringArrayHashMapUnmanaged(impl.RACE) = .{},
    REGN: std.StringArrayHashMapUnmanaged(impl.REGN) = .{},
    REPA: std.StringArrayHashMapUnmanaged(impl.REPA) = .{},
    SCPT: std.StringArrayHashMapUnmanaged(impl.SCPT) = .{},
    SKIL: std.AutoArrayHashMapUnmanaged(u32, impl.SKIL) = .{},
    SNDG: std.StringArrayHashMapUnmanaged(impl.SNDG) = .{},
    SOUN: std.StringArrayHashMapUnmanaged(impl.SOUN) = .{},
    SPEL: std.StringArrayHashMapUnmanaged(impl.SPEL) = .{},
    SSCR: std.StringArrayHashMapUnmanaged(impl.SSCR) = .{},
    STAT: std.StringArrayHashMapUnmanaged(impl.STAT) = .{},
    WEAP: std.StringArrayHashMapUnmanaged(impl.WEAP) = .{},

    const Self = @This();

    // I may end up moving all this code into individual 'deinit' functions for each impl
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        for (self.ALCH.values()) |alch| if (alch.ENAM) |enam| allocator.free(enam);
        for (self.ARMO.values()) |armo| if (armo.INDX) |indx| allocator.free(indx);
        for (self.BSGN.values()) |bsgn| if (bsgn.NPCS) |npcs| allocator.free(npcs);
        for (self.CLOT.values()) |clot| if (clot.INDX) |indx| allocator.free(indx);
        for (self.CONT.values()) |cont| if (cont.NPCO) |npco| allocator.free(npco);
        for (self.CREA.values()) |crea| {
            if (crea.NPCO) |npco| allocator.free(npco);
            if (crea.NPCS) |npcs| allocator.free(npcs);
            if (crea.DODT) |dodt| allocator.free(dodt);
            if (crea.AI__) |ai__| allocator.free(ai__);
        }
        for (self.DIAL.values()) |*dial| {
            for (dial.INFO.values()) |info| if (info.SCVR) |scvr| allocator.free(scvr);
            dial.INFO.deinit(allocator);
        }
        for (self.ENCH.values()) |ench| if (ench.ENAM) |enam| allocator.free(enam);
        for (self.FACT.values()) |fact| {
            if (fact.RNAM) |rnam| allocator.free(rnam);
            if (fact.ANAM) |anam| allocator.free(anam);
        }
        for (self.LEV_.values()) |lev_| if (lev_._NAM) |_nam| allocator.free(_nam);
        for (self.NPC_.values()) |npc_| {
            if (npc_.NPCO) |npco| allocator.free(npco);
            if (npc_.NPCS) |npcs| allocator.free(npcs);
            if (npc_.DODT) |dodt| allocator.free(dodt);
            if (npc_.AI__) |ai__| allocator.free(ai__);
        }
        for (self.RACE.values()) |race| if (race.NPCS) |npcs| allocator.free(npcs);
        for (self.REGN.values()) |regn| if (regn.SNAM) |snam| allocator.free(snam);
        for (self.SPEL.values()) |spel| if (spel.ENAM) |enam| allocator.free(enam);
        inline for (std.meta.fields(Self)) |field| {
            @field(self, field.name).deinit(allocator);
        }
    }
};

pub fn cachePlugin(
    allocator: std.mem.Allocator,
    short_name: []const u8,
    plugin_index: u32,
    loaded_plugins: [][]const u8,
    plugin: util.FileMap,
    record_map: *map,
    logger: util.Logger,
) !void {
    var iterator: util.iterators.RecordIterator(@TypeOf(
        std.io.fixedBufferStream(plugin.slice),
    )) = .{ .stream = std.io.fixedBufferStream(plugin.slice) };

    const tes3: impl.TES3 = blk: {
        const rec = try iterator.next(logger, short_name) orelse return error.InvalidFormat;
        if (rec.tag != .TES3) {
            try logger.err(
                "{s}: Expected file to begin with TES3, got {s} instead\n",
                .{ short_name, @ptrCast(*const [4]u8, &@enumToInt(rec.tag)) },
            );
            return error.InvalidFormat;
        }
        break :blk try impl.TES3.parse(
            allocator,
            logger,
            short_name,
            plugin_index,
            loaded_plugins,
            rec.payload,
        );
    };
    defer allocator.free(tes3.masters);

    // TODO: perform error handling here in a catch instead of in util.parseRec
    while (try iterator.next(logger, short_name)) |record| {
        const start = try iterator.stream.getPos() - record.payload.len - 16;
        switch (record.tag) {
            // TODO: reporting invalid subrecords should be done here instead of in individual
            // record functions
            // zig fmt: off
            inline .ACTI, .ALCH, .APPA, .ARMO, .BODY, .BOOK, .BSGN, .CLAS, .CLOT, .CONT, .CREA,
            .DOOR, .ENCH, .FACT, .GLOB, .GMST, .INGR, .LAND, .LIGH, .LOCK, .LTEX, .MGEF, .MISC,
            .NPC_, .PROB, .RACE, .REGN, .REPA, .SCPT, .SKIL, .SNDG, .SOUN, .SPEL, .SSCR, .STAT,
            .WEAP,
            => |known| {
            // zig fmt: on
                const tag = @tagName(known);
                try logger.debug("{s}: " ++ tag ++ " at 0x{X}\n", .{ short_name, start });

                try @field(impl, tag).parse(
                    allocator,
                    logger,
                    short_name,
                    &@field(record_map, tag),
                    record.payload,
                    @intCast(u32, start + 16),
                    record.flag,
                );
            },
            .CELL => {
                try logger.debug("{s}: CELL at 0x{X}\n", .{ short_name, start });

                try impl.CELL.parse(
                    allocator,
                    logger,
                    short_name,
                    tes3.masters,
                    &record_map.CELL,
                    record.payload,
                    @intCast(u32, start + 16),
                    record.flag,
                );
            },
            .DIAL => {
                try logger.debug("{s}: DIAL at 0x{X}\n", .{ short_name, start });

                // Just a pointer to the value in the hashmap.
                var dial = try impl.DIAL.parse(
                    allocator,
                    logger,
                    short_name,
                    &record_map.DIAL,
                    record.payload,
                    @intCast(u32, start + 16),
                    record.flag,
                );

                while (try iterator.next(logger, short_name)) |next_rec| {
                    if (next_rec.tag != .INFO) {
                        try iterator.stream.seekBy(-1 * @intCast(
                            isize,
                            next_rec.payload.len + 16,
                        ));
                        break;
                    }
                    const info_start = try iterator.stream.getPos() - next_rec.payload.len - 16;
                    try logger.debug("{s}: INFO at 0x{X}\n", .{ short_name, info_start });

                    try impl.INFO.parse(
                        allocator,
                        logger,
                        short_name,
                        &dial.INFO,
                        next_rec.payload,
                        @intCast(u32, info_start + 16),
                        record.flag,
                    );
                }
            },
            inline .LEVC, .LEVI => |known| {
                const tag = @tagName(known);
                try logger.debug("{s}: " ++ tag ++ " at 0x{X}\n", .{ short_name, start });

                try impl.LEV_.parse(
                    allocator,
                    logger,
                    short_name,
                    &record_map.LEV_,
                    record.payload,
                    @intCast(u32, start + 16),
                    record.flag,
                    @field(impl.LEV_.lev_type, tag),
                );
            },
            .PGRD => {
                try logger.debug("{s}: PGRD at 0x{X}\n", .{ short_name, start });

                try impl.PGRD.parse(
                    allocator,
                    logger,
                    short_name,
                    &record_map.PGRD,
                    record.payload,
                    @intCast(u32, start + 16),
                    record.flag,
                );
            },
            .INFO => return error.Parentless_INFO,
            else => {},
        }
    }
}

pub fn writeAll(
    allocator: std.mem.Allocator,
    record_map: *map,
    out_dir: std.fs.Dir,
) !void {
    // zig fmt: off
    const directory_names = [_]*const [4]u8{
        "ACTI", "ALCH", "APPA", "ARMO", "BODY", "BOOK", "BSGN", "CELL", "CLAS", "CLOT", "CONT",
        "CREA", "DIAL", "DOOR", "ENCH", "FACT", "GLOB", "GMST", "INGR", "LAND", "LEVC", "LEVI",
        "LIGH", "LOCK", "LTEX", "MGEF", "MISC", "NPC_", "PGRD", "PROB", "RACE", "REGN", "REPA",
        "SCPT", "SKIL", "SNDG", "SOUN", "SPEL", "SSCR", "STAT", "WEAP",
    };
    // zig fmt: on
    for (directory_names) |rec_tag| {
        out_dir.makeDir(rec_tag) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }

    var list_files: [directory_names.len]std.fs.File = undefined;
    var list_writers: [directory_names.len]std.io.BufferedWriter(
        4096,
        std.fs.File.Writer,
    ) = undefined;
    var initialized_files: u8 = 0;
    defer for (list_files[0..initialized_files]) |file| file.close();

    out_dir.makeDir("list") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    for (directory_names, &list_files, &list_writers) |rec_tag, *file, *writer| {
        file.* = try out_dir.createFile("list/" ++ rec_tag ++ ".json", .{});
        initialized_files += 1;

        writer.* = std.io.bufferedWriter(file.*.writer());
        _ = try writer.write("[");
    }

    inline for (directory_names, &list_writers) |rec_tag, *writer| {
        if (@hasDecl(impl, rec_tag) and @hasDecl(@field(impl, rec_tag), "writeAll")) {
            var dir = try out_dir.openDir(rec_tag, .{});
            defer dir.close();
            try @field(impl, rec_tag).writeAll(
                allocator,
                dir,
                @field(record_map, rec_tag),
                writer,
            );
        } else switch (@field(recs, rec_tag)) {
            .LEVC => {
                var levc_dir = try out_dir.openDir("LEVC", .{});
                defer levc_dir.close();
                var levi_dir = try out_dir.openDir("LEVI", .{});
                defer levi_dir.close();
                const levc_writer = &list_writers[
                    comptime blk: {
                        for (directory_names, 0..) |tag, i| {
                            if (std.mem.eql(u8, tag, "LEVC")) break :blk i;
                        }
                    }
                ];
                const levi_writer = &list_writers[
                    comptime blk: {
                        for (directory_names, 0..) |tag, i| {
                            if (std.mem.eql(u8, tag, "LEVI")) break :blk i;
                        }
                    }
                ];
                try impl.LEV_.writeAll(
                    allocator,
                    levc_dir,
                    levi_dir,
                    record_map.LEV_,
                    levc_writer,
                    levi_writer,
                );
            },
            .LEVI => {},
            else => unreachable,
        }
    }

    for (&list_writers) |*writer| {
        writer.end -= @boolToInt(writer.end > 1);
        _ = try writer.write("]");
        try writer.flush();
    }
}
