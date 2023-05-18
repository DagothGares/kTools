// Stub wrapper for windows FileMap and linux mmap

const std = @import("std");
const builtin = @import("builtin");

const is_windows = builtin.os.tag == .windows;
const windows = std.os.windows;
const WINAPI = windows.WINAPI;

const Self = @This();

map_handle: (if (is_windows) std.os.fd_t else void) = undefined,
slice: []align(std.mem.page_size) const u8,
permissions: Permissions,

pub const Permissions = enum {
    read,
    read_write,
    execute_read,
    execute_read_write,
};

const windows_protection = enum(windows.DWORD) {
    read = 0x2,
    read_write = 0x4,
    execute_read = 0x20,
    execute_read_write = 0x40,
};

const windows_access = enum(windows.DWORD) {
    read = 0x4,
    read_write = 0x2,
    execute_read = 0x20 + 0x4,
    execute_read_write = 0x20 + 0x2,
};

extern "kernel32" fn CreateFileMappingW(
    hFile: ?windows.HANDLE,
    lpFileMappingAttributes: ?*windows.SECURITY_ATTRIBUTES,
    flProtect: windows.DWORD,
    dwMaximumSizeHigh: windows.DWORD,
    dwMaximumSizeLow: windows.DWORD,
    lpName: ?[*:0]const windows.WCHAR,
) callconv(WINAPI) ?windows.HANDLE;

extern "kernel32" fn MapViewOfFile(
    hFileMappingObject: windows.HANDLE,
    dwDesiredAccess: windows.DWORD,
    dwFileOffsetHigh: windows.DWORD,
    dwFileOffsetLow: windows.DWORD,
    dwNumberOfBytesToMap: windows.SIZE_T,
) callconv(WINAPI) ?windows.LPVOID;

extern "kernel32" fn UnmapViewOfFile(lpBaseAddress: windows.LPCVOID) callconv(WINAPI) windows.BOOL;

pub fn init(
    file: std.fs.File,
    comptime permissions: Permissions,
    //offset: u64,
) !Self {
    const length: u64 = (try file.metadata()).size();
    if (length == 0) return error.FileEmpty;

    if (is_windows) {
        const w = windows;

        // I think I don't actually need this...?
        //var SystemInfo: w.SYSTEM_INFO = undefined;
        //w.kernel32.GetSystemInfo(&SystemInfo);

        const prot = @enumToInt(@field(windows_protection, @tagName(permissions)));

        const map_handle = CreateFileMappingW(
            file.handle,
            null,
            prot,
            0, // TODO: set actual file size (aligned to page size) here
            0,
            null,
        ) orelse switch (w.kernel32.GetLastError()) {
            .ACCESS_DENIED => return error.AccessDenied,
            else => |err| return w.unexpectedError(err),
        };

        const access = @enumToInt(@field(windows_access, @tagName(permissions)));

        const map_ptr = MapViewOfFile(map_handle, access, 0, 0, 0) orelse
            return w.unexpectedError(w.kernel32.GetLastError());

        return .{
            .map_handle = map_handle,
            .slice = @ptrCast(
                [*]align(std.mem.page_size) u8,
                @alignCast(std.mem.page_size, map_ptr),
            )[0..length],
            .permissions = permissions,
        };
    } else {
        const prot: u32 = switch (permissions) {
            .read => std.os.PROT.READ,
            .read_write => std.os.PROT.WRITE + std.os.PROT.READ,
            .execute_read => std.os.PROT.EXEC + std.os.PROT.READ,
            .execute_read_write => std.os.PROT.EXEC + std.os.PROT.WRITE + std.os.PROT.READ,
        };
        return .{
            .slice = try std.os.mmap(null, length, prot, std.os.MAP.PRIVATE, file.handle, 0),
            .permissions = permissions,
        };
    }
}

pub fn deinit(self: Self) void {
    if (is_windows) {
        // Resource deallocation must succeed.
        _ = UnmapViewOfFile(@ptrCast(windows.LPCVOID, self.slice));
        windows.CloseHandle(self.map_handle);
    } else std.os.munmap(self.slice);
}
