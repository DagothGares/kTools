pub const INDX = struct {
    index: u8,
    BNAM: ?[]const u8 = null,
    CNAM: ?[]const u8 = null,
};

pub const DODT = struct {
    destination: [6]f32,
    DNAM: ?[]const u8 = null,
};

pub const NPCO = struct {
    count: i32,
    name: []const u8,
};

pub const AIDT = extern struct {
    greet: u8 align(1) = 0,
    _garbage1: u8 align(1) = 0,
    fight: u8 align(1) = 0,
    flee: u8 align(1) = 0,
    alarm: u8 align(1) = 0,
    _garbage2: u16 align(1) = 0,
    _garbage3: u8 align(1) = 0,
    flags: u32 align(1) = 0,
};

pub const __DT = extern struct {
    weight: f32 align(1) = 0,
    value: u32 align(1) = 0,
    quality: f32 align(1) = 0,
    durability: u32 align(1) = 0,
};

pub const ENAM = extern struct {
    effect_index: u16 align(1),
    skill_affected: i8 align(1),
    attribute_affected: i8 align(1),
    range: u32 align(1),
    area: u32 align(1),
    duration: u32 align(1),
    magnitude: extern struct {
        min: u32 align(1),
        max: u32 align(1),
    } align(1),
};

/// Garbage fields are ignored, since they come at the end of the struct.
pub const AI__ = union(enum) {
    pub const a_package = extern struct {
        name: [32]u8 align(1),
    };
    pub const ef_package = extern struct {
        position: [3]f32 align(1),
        duration: u16 align(1),
        name: [32]u8 align(1),
    };
    pub const t_package = extern struct {
        position: [3]f32 align(1),
    };
    pub const w_package = extern struct {
        distance: u16 align(1),
        duration: u16 align(1),
        time_of_day: u8 align(1),
        idles: [8]u8 align(1),
    };
    A: a_package,
    E: struct {
        core: ef_package,
        CNDT: ?[]const u8 = null,
    },
    F: struct {
        core: ef_package,
        CNDT: ?[]const u8 = null,
    },
    T: t_package,
    W: w_package,
};
