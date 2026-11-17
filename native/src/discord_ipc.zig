//! Discord local IPC: the channel the Discord desktop app opens so games can
//! show Rich Presence.
//!
//! Where it lives:
//!   Linux, macOS, FreeBSD  a Unix socket file named "discord-ipc-0" .. "-9"
//!                          (the folder is found by GDScript, see discord.gd)
//!   Windows                a named pipe \\?\pipe\discord-ipc-0 .. -9
//!
//! Every message is a FRAME:
//!   bytes 0..4   opcode, u32 little endian (0 handshake, 1 frame, 2 close,
//!                3 ping, 4 pong)
//!   bytes 4..8   payload length, u32 little endian
//!   bytes 8..    payload: UTF-8 JSON
//!
//! This file only moves frames. The JSON is written and read by GDScript.
//! Nothing here ever blocks the game: reads return whatever has arrived.

const std: type = @import("std");
const builtin: type = @import("builtin");

const Allocator: type = std.mem.Allocator;
const os_tag: std.Target.Os.Tag = builtin.os.tag;

/// Size of the frame header (opcode + length).
pub const HEADER_SIZE: usize = 8;
/// Discord never sends frames this large; anything bigger means a broken
/// stream, and the connection is dropped.
pub const MAX_PAYLOAD: usize = 64 * 1024;

pub const Error = error{
    /// Nothing is listening at that path (Discord is not running).
    NotFound,
    /// The other side closed the channel.
    Closed,
    /// Any other operating-system failure.
    SystemError,
    /// This platform has no Discord desktop app (Android, web...).
    Unsupported,
} || Allocator.Error;

// ===========================================================================
// Frames
// ===========================================================================

/// Writes header + payload for one frame into a new buffer (caller frees).
pub fn encodeFrame(gpa: Allocator, opcode: u32, payload: []const u8) Allocator.Error![]u8 {
    const frame: []u8 = try gpa.alloc(u8, HEADER_SIZE + payload.len);
    std.mem.writeInt(u32, frame[0..4], opcode, .little);
    std.mem.writeInt(u32, frame[4..8], @intCast(payload.len), .little);
    @memcpy(frame[HEADER_SIZE..], payload);
    return frame;
}

/// Collects incoming bytes and cuts them into frames.
pub const FrameReader = struct {
    buffer: std.ArrayList(u8) = .empty,
    /// Bytes of the frame handed out last, removed on the next call.
    consumed: usize = 0,

    pub const Frame = struct {
        opcode: u32,
        /// Points into the reader's buffer: valid until the next call.
        payload: []const u8,
    };

    pub fn deinit(self: *FrameReader, gpa: Allocator) void {
        self.buffer.deinit(gpa);
    }

    pub fn push(self: *FrameReader, gpa: Allocator, bytes: []const u8) Allocator.Error!void {
        try self.buffer.appendSlice(gpa, bytes);
    }

    /// The next complete frame, or null if more bytes are needed. Returns
    /// error.Closed when the stream is clearly broken (absurd length).
    pub fn next(self: *FrameReader) Error!?Frame {
        // Drop the frame handed out last time (kept until now so its payload
        // stayed valid for the caller).
        if (self.consumed > 0) {
            const rest: usize = self.buffer.items.len - self.consumed;
            std.mem.copyForwards(u8, self.buffer.items[0..rest], self.buffer.items[self.consumed..]);
            self.buffer.shrinkRetainingCapacity(rest);
            self.consumed = 0;
        }
        const data: []const u8 = self.buffer.items;
        if (data.len < HEADER_SIZE) {
            return null;
        }
        const opcode: u32 = std.mem.readInt(u32, data[0..4], .little);
        const length: usize = std.mem.readInt(u32, data[4..8], .little);
        if (length > MAX_PAYLOAD) {
            return error.Closed;
        }
        if (data.len < HEADER_SIZE + length) {
            return null;
        }
        self.consumed = HEADER_SIZE + length;
        return .{ .opcode = opcode, .payload = data[HEADER_SIZE .. HEADER_SIZE + length] };
    }
};

// ===========================================================================
// Connection, per platform
// ===========================================================================

pub const Connection = switch (os_tag) {
    .linux => if (builtin.abi.isAndroid()) Unsupported else LinuxSocket,
    .macos, .freebsd => LibcSocket,
    .windows => WindowsPipe,
    else => Unsupported,
};

/// Platforms without the Discord desktop app.
const Unsupported = struct {
    pub fn open(path: []const u8) Error!Unsupported {
        _ = path;
        return error.Unsupported;
    }
    pub fn writeAll(self: *Unsupported, bytes: []const u8) Error!void {
        _ = self;
        _ = bytes;
        return error.Unsupported;
    }
    pub fn readAvailable(self: *Unsupported, buffer: []u8) Error!usize {
        _ = self;
        _ = buffer;
        return error.Unsupported;
    }
    pub fn close(self: *Unsupported) void {
        _ = self;
    }
};

/// Linux: raw system calls (the library does not link libc).
const LinuxSocket = struct {
    const linux: type = std.os.linux;

    fd: i32,

    pub fn open(path: []const u8) Error!LinuxSocket {
        var address: linux.sockaddr.un = .{ .family = linux.AF.UNIX, .path = @splat(0) };
        if (path.len >= address.path.len) {
            return error.NotFound;
        }
        @memcpy(address.path[0..path.len], path);

        const flags: u32 = linux.SOCK.STREAM | linux.SOCK.CLOEXEC | linux.SOCK.NONBLOCK;
        const created: usize = linux.socket(linux.AF.UNIX, flags, 0);
        if (linux.errno(created) != .SUCCESS) {
            return error.SystemError;
        }
        const fd: i32 = @intCast(created);
        // A Unix-socket connect completes right away (or fails right away).
        const connected: usize = linux.connect(fd, &address, @sizeOf(linux.sockaddr.un));
        if (linux.errno(connected) != .SUCCESS) {
            _ = linux.close(fd);
            return error.NotFound;
        }
        return .{ .fd = fd };
    }

    /// Frames are small; if the socket is momentarily full, try again a
    /// bounded number of times rather than blocking.
    pub fn writeAll(self: *LinuxSocket, bytes: []const u8) Error!void {
        var sent: usize = 0;
        var attempts: u32 = 0;
        while (sent < bytes.len) {
            const result: usize = linux.write(self.fd, bytes[sent..].ptr, bytes.len - sent);
            switch (linux.errno(result)) {
                .SUCCESS => sent += result,
                .AGAIN => {
                    attempts += 1;
                    if (attempts > 1000) return error.SystemError;
                },
                .INTR => {},
                else => return error.Closed,
            }
        }
    }

    /// Bytes that have already arrived (0 if none). error.Closed when the
    /// other side hung up.
    pub fn readAvailable(self: *LinuxSocket, buffer: []u8) Error!usize {
        const result: usize = linux.read(self.fd, buffer.ptr, buffer.len);
        return switch (linux.errno(result)) {
            .SUCCESS => if (result == 0) error.Closed else result,
            .AGAIN, .INTR => 0,
            else => error.Closed,
        };
    }

    pub fn close(self: *LinuxSocket) void {
        _ = linux.close(self.fd);
    }
};

/// macOS and FreeBSD: the system C library (always present there).
const LibcSocket = struct {
    /// struct sockaddr_un on macOS and FreeBSD: a length byte, the family
    /// byte, then the path.
    const SockaddrUn = extern struct {
        len: u8,
        family: u8,
        path: [104]u8,
    };
    const AF_UNIX: c_int = 1;
    const SOCK_STREAM: c_int = 1;
    const F_GETFL: c_int = 3;
    const F_SETFL: c_int = 4;
    const O_NONBLOCK: c_int = 4;
    const EAGAIN: c_int = 35;
    const EINTR: c_int = 4;

    extern "c" fn socket(domain: c_int, kind: c_int, protocol: c_int) c_int;
    extern "c" fn connect(fd: c_int, address: *const anyopaque, length: u32) c_int;
    extern "c" fn fcntl(fd: c_int, command: c_int, ...) c_int;
    extern "c" fn read(fd: c_int, buffer: [*]u8, count: usize) isize;
    extern "c" fn write(fd: c_int, buffer: [*]const u8, count: usize) isize;
    /// libc close(), under another name: `close` is this struct's method.
    const closeFd = @extern(*const fn (fd: c_int) callconv(.c) c_int, .{ .name = "close" });
    extern "c" fn __error() *c_int;

    fd: c_int,

    pub fn open(path: []const u8) Error!LibcSocket {
        var address: SockaddrUn = .{ .len = @sizeOf(SockaddrUn), .family = AF_UNIX, .path = @splat(0) };
        if (path.len >= address.path.len) {
            return error.NotFound;
        }
        @memcpy(address.path[0..path.len], path);
        const fd: c_int = socket(AF_UNIX, SOCK_STREAM, 0);
        if (fd < 0) {
            return error.SystemError;
        }
        if (connect(fd, &address, @sizeOf(SockaddrUn)) != 0) {
            _ = closeFd(fd);
            return error.NotFound;
        }
        // Non-blocking from now on, so reads never stall the game.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, @as(c_int, 0)) | O_NONBLOCK);
        return .{ .fd = fd };
    }

    pub fn writeAll(self: *LibcSocket, bytes: []const u8) Error!void {
        var sent: usize = 0;
        var attempts: u32 = 0;
        while (sent < bytes.len) {
            const result: isize = write(self.fd, bytes[sent..].ptr, bytes.len - sent);
            if (result >= 0) {
                sent += @intCast(result);
                continue;
            }
            const code: c_int = __error().*;
            if (code == EINTR) continue;
            if (code != EAGAIN) return error.Closed;
            attempts += 1;
            if (attempts > 1000) return error.SystemError;
        }
    }

    pub fn readAvailable(self: *LibcSocket, buffer: []u8) Error!usize {
        const result: isize = read(self.fd, buffer.ptr, buffer.len);
        if (result > 0) return @intCast(result);
        if (result == 0) return error.Closed;
        const code: c_int = __error().*;
        return if (code == EAGAIN or code == EINTR) 0 else error.Closed;
    }

    pub fn close(self: *LibcSocket) void {
        _ = closeFd(self.fd);
    }
};

/// Windows: a named pipe opened like a file.
const WindowsPipe = struct {
    const HANDLE = *anyopaque;
    const INVALID_HANDLE_VALUE: usize = std.math.maxInt(usize);
    const GENERIC_READ: u32 = 0x80000000;
    const GENERIC_WRITE: u32 = 0x40000000;
    const OPEN_EXISTING: u32 = 3;

    extern "kernel32" fn CreateFileW(name: [*:0]const u16, access: u32, share: u32, security: ?*anyopaque,
        disposition: u32, flags: u32, template: ?HANDLE) callconv(.winapi) usize;
    extern "kernel32" fn WriteFile(file: HANDLE, buffer: [*]const u8, count: u32, written: *u32,
        overlapped: ?*anyopaque) callconv(.winapi) i32;
    extern "kernel32" fn ReadFile(file: HANDLE, buffer: [*]u8, count: u32, read: *u32,
        overlapped: ?*anyopaque) callconv(.winapi) i32;
    extern "kernel32" fn PeekNamedPipe(pipe: HANDLE, buffer: ?*anyopaque, size: u32, read: ?*u32,
        available: ?*u32, left: ?*u32) callconv(.winapi) i32;
    extern "kernel32" fn CloseHandle(handle: HANDLE) callconv(.winapi) i32;

    handle: HANDLE,

    pub fn open(path: []const u8) Error!WindowsPipe {
        // The path is ASCII (\\?\pipe\discord-ipc-N): widen it to UTF-16.
        var wide: [128:0]u16 = @splat(0);
        if (path.len >= wide.len) {
            return error.NotFound;
        }
        for (path, 0..) |byte, i| {
            wide[i] = byte;
        }
        const result: usize = CreateFileW(&wide, GENERIC_READ | GENERIC_WRITE, 0, null, OPEN_EXISTING, 0, null);
        if (result == INVALID_HANDLE_VALUE or result == 0) {
            return error.NotFound;
        }
        return .{ .handle = @ptrFromInt(result) };
    }

    pub fn writeAll(self: *WindowsPipe, bytes: []const u8) Error!void {
        var sent: usize = 0;
        while (sent < bytes.len) {
            var written: u32 = 0;
            const chunk: u32 = @intCast(@min(bytes.len - sent, std.math.maxInt(u32)));
            if (WriteFile(self.handle, bytes[sent..].ptr, chunk, &written, null) == 0) {
                return error.Closed;
            }
            sent += written;
        }
    }

    /// Only reads what PeekNamedPipe says is waiting, so ReadFile never
    /// blocks.
    pub fn readAvailable(self: *WindowsPipe, buffer: []u8) Error!usize {
        var available: u32 = 0;
        if (PeekNamedPipe(self.handle, null, 0, null, &available, null) == 0) {
            return error.Closed;
        }
        if (available == 0) {
            return 0;
        }
        var read: u32 = 0;
        const wanted: u32 = @intCast(@min(available, buffer.len));
        if (ReadFile(self.handle, buffer.ptr, wanted, &read, null) == 0) {
            return error.Closed;
        }
        return read;
    }

    pub fn close(self: *WindowsPipe) void {
        _ = CloseHandle(self.handle);
    }
};

// ===========================================================================
// Tests (`zig build test`)
// ===========================================================================

const testing: type = std.testing;

test "a frame is opcode, length and payload, little endian" {
    const frame: []u8 = try encodeFrame(testing.allocator, 1, "{\"a\":1}");
    defer testing.allocator.free(frame);
    try testing.expectEqualSlices(u8, &.{ 1, 0, 0, 0, 7, 0, 0, 0 }, frame[0..8]);
    try testing.expectEqualStrings("{\"a\":1}", frame[8..]);
}

test "the reader waits for whole frames and cuts them apart" {
    var reader: FrameReader = .{};
    defer reader.deinit(testing.allocator);
    const first: []u8 = try encodeFrame(testing.allocator, 1, "hello");
    defer testing.allocator.free(first);
    const second: []u8 = try encodeFrame(testing.allocator, 3, "ping!");
    defer testing.allocator.free(second);

    // Half a frame: nothing yet.
    try reader.push(testing.allocator, first[0..6]);
    try testing.expectEqual(@as(?FrameReader.Frame, null), try reader.next());
    // The rest of the first frame plus the whole second one.
    try reader.push(testing.allocator, first[6..]);
    try reader.push(testing.allocator, second);
    const a: FrameReader.Frame = (try reader.next()).?;
    try testing.expectEqual(@as(u32, 1), a.opcode);
    try testing.expectEqualStrings("hello", a.payload);
    const b: FrameReader.Frame = (try reader.next()).?;
    try testing.expectEqual(@as(u32, 3), b.opcode);
    try testing.expectEqualStrings("ping!", b.payload);
    try testing.expectEqual(@as(?FrameReader.Frame, null), try reader.next());
}

test "an absurd length closes the stream" {
    var reader: FrameReader = .{};
    defer reader.deinit(testing.allocator);
    try reader.push(testing.allocator, &.{ 1, 0, 0, 0, 0xff, 0xff, 0xff, 0x7f });
    try testing.expectError(error.Closed, reader.next());
}

test "connecting to a missing socket fails cleanly" {
    if (Connection == Unsupported or os_tag == .windows) return error.SkipZigTest;
    try testing.expectError(error.NotFound, Connection.open("/nonexistent/discord-ipc-0"));
}
