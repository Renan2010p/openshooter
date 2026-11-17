//! The `DiscordIpc` class seen by GDScript (a RefCounted), used by
//! scripts/autoload/discord.gd for Rich Presence:
//!
//!     var ipc = ClassDB.instantiate("DiscordIpc")
//!     ipc.open(path)              # -> bool: connected to the Discord app
//!     ipc.send(opcode, json)      # -> bool: one frame sent
//!     ipc.receive()               # -> String: JSON of the next frame that
//!                                 #    arrived, or "" (never waits)
//!     ipc.last_opcode()           # -> int: opcode of that frame
//!     ipc.is_open()               # -> bool
//!     ipc.close()                 # -> bool
//!
//! The transport and the frame format are in discord_ipc.zig.

const std: type = @import("std");
const godot: type = @import("godot.zig");
const ipc: type = @import("discord_ipc.zig");

const c: type = godot.c;
const T: type = godot.VariantTypes;

const CLASS_NAME: [:0]const u8 = "DiscordIpc";
const PARENT_CLASS_NAME: [:0]const u8 = "RefCounted";

/// State of one DiscordIpc object.
const Instance = struct {
    connection: ?ipc.Connection = null,
    reader: ipc.FrameReader = .{},
    last_opcode: i64 = -1,

    fn close(self: *Instance) void {
        if (self.connection) |*connection| {
            connection.close();
        }
        self.connection = null;
        self.reader.deinit(godot.allocator);
        self.reader = .{};
    }
};

var registered: bool = false;

pub fn register() void {
    if (registered) {
        return;
    }
    registered = true;
    var class_name: godot.StringName = .fromLatin1(CLASS_NAME);
    defer class_name.deinit();
    var parent_name: godot.StringName = .fromLatin1(PARENT_CLASS_NAME);
    defer parent_name.deinit();
    const info: c.GDExtensionClassCreationInfo6 = .{
        .is_virtual = 0,
        .is_abstract = 0,
        .is_exposed = 1,
        .is_runtime = 0,
        .icon_path = null,
        .set_func = null,
        .get_func = null,
        .get_property_list_func = null,
        .free_property_list_func = null,
        .property_can_revert_func = null,
        .property_get_revert_func = null,
        .validate_property_func = null,
        .notification_func = null,
        .to_string_func = null,
        .reference_func = null,
        .unreference_func = null,
        .create_instance_func = createInstance,
        .free_instance_func = freeInstance,
        .recreate_instance_func = null,
        .get_virtual_func = null,
        .get_virtual_call_data_func = null,
        .call_virtual_with_data_func = null,
        .class_userdata = null,
    };
    godot.api.classdb_register_extension_class6.?(godot.library, @ptrCast(&class_name), @ptrCast(&parent_name), &info);

    godot.bindMethod(CLASS_NAME, "open", callOpen, T.boolean, &.{.{ .name = "path", .variant_type = T.string }});
    godot.bindMethod(CLASS_NAME, "send", callSend, T.boolean, &.{
        .{ .name = "opcode", .variant_type = T.int },
        .{ .name = "json", .variant_type = T.string },
    });
    godot.bindMethod(CLASS_NAME, "receive", callReceive, T.string, &.{});
    godot.bindMethod(CLASS_NAME, "last_opcode", callLastOpcode, T.int, &.{});
    godot.bindMethod(CLASS_NAME, "is_open", callIsOpen, T.boolean, &.{});
    godot.bindMethod(CLASS_NAME, "close", callClose, T.boolean, &.{});
}

pub fn unregister() void {
    if (!registered) {
        return;
    }
    registered = false;
    var class_name: godot.StringName = .fromLatin1(CLASS_NAME);
    defer class_name.deinit();
    godot.api.classdb_unregister_extension_class.?(godot.library, @ptrCast(&class_name));
}

// ===========================================================================
// Instances
// ===========================================================================

fn createInstance(class_userdata: ?*anyopaque, notify_postinitialize: c.GDExtensionBool) callconv(.c) c.GDExtensionObjectPtr {
    _ = class_userdata;
    _ = notify_postinitialize;
    var parent_name: godot.StringName = .fromLatin1(PARENT_CLASS_NAME);
    defer parent_name.deinit();
    const object: c.GDExtensionObjectPtr = godot.api.classdb_construct_object3.?(@ptrCast(&parent_name));
    if (object == null) {
        return null;
    }
    const instance: *Instance = godot.allocator.create(Instance) catch return object;
    instance.* = .{};
    var class_name: godot.StringName = .fromLatin1(CLASS_NAME);
    defer class_name.deinit();
    godot.api.object_set_instance.?(object, @ptrCast(&class_name), instance);
    return object;
}

/// The object is gone: close the channel and free its memory.
fn freeInstance(class_userdata: ?*anyopaque, instance: c.GDExtensionClassInstancePtr) callconv(.c) void {
    _ = class_userdata;
    const self: *Instance = @ptrCast(@alignCast(instance orelse return));
    self.close();
    godot.allocator.destroy(self);
}

// ===========================================================================
// Methods
// ===========================================================================

/// Common shape of every method callback: checks the argument count and
/// finds the instance. Returns null (after reporting the error) on mismatch.
fn begin(
    instance: c.GDExtensionClassInstancePtr,
    argument_count: c.GDExtensionInt,
    expected: c.GDExtensionInt,
    call_error: [*c]c.GDExtensionCallError,
) ?*Instance {
    if (argument_count != expected) {
        call_error.*.@"error" = if (argument_count < expected)
            c.GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS
        else
            c.GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
        call_error.*.expected = @intCast(expected);
        return null;
    }
    return @ptrCast(@alignCast(instance orelse return null));
}

fn resultSlot(result: c.GDExtensionVariantPtr) *godot.Variant {
    return @ptrCast(@alignCast(result));
}

/// `open(path: String) -> bool`
fn callOpen(_: ?*anyopaque, instance: c.GDExtensionClassInstancePtr, arguments: [*c]const c.GDExtensionConstVariantPtr,
    argument_count: c.GDExtensionInt, result: c.GDExtensionVariantPtr, call_error: [*c]c.GDExtensionCallError) callconv(.c) void {
    const self: *Instance = begin(instance, argument_count, 1, call_error) orelse return;
    self.close();
    const path: []u8 = godot.toUtf8(godot.allocator, arguments[0]) catch {
        godot.setBool(resultSlot(result), false);
        return;
    };
    defer godot.allocator.free(path);
    self.connection = ipc.Connection.open(path) catch null;
    godot.setBool(resultSlot(result), self.connection != null);
}

/// `send(opcode: int, json: String) -> bool`
fn callSend(_: ?*anyopaque, instance: c.GDExtensionClassInstancePtr, arguments: [*c]const c.GDExtensionConstVariantPtr,
    argument_count: c.GDExtensionInt, result: c.GDExtensionVariantPtr, call_error: [*c]c.GDExtensionCallError) callconv(.c) void {
    const self: *Instance = begin(instance, argument_count, 2, call_error) orelse return;
    const sent: bool = send(self, godot.toInt(arguments[0]), arguments[1]);
    godot.setBool(resultSlot(result), sent);
}

fn send(self: *Instance, opcode: i64, json_variant: c.GDExtensionConstVariantPtr) bool {
    var connection: *ipc.Connection = &(self.connection orelse return false);
    const json: []u8 = godot.toUtf8(godot.allocator, json_variant) catch return false;
    defer godot.allocator.free(json);
    const frame: []u8 = ipc.encodeFrame(godot.allocator, @intCast(@max(opcode, 0)), json) catch return false;
    defer godot.allocator.free(frame);
    connection.writeAll(frame) catch {
        self.close();
        return false;
    };
    return true;
}

/// `receive() -> String`: the JSON of the next complete frame, or "".
fn callReceive(_: ?*anyopaque, instance: c.GDExtensionClassInstancePtr, arguments: [*c]const c.GDExtensionConstVariantPtr,
    argument_count: c.GDExtensionInt, result: c.GDExtensionVariantPtr, call_error: [*c]c.GDExtensionCallError) callconv(.c) void {
    _ = arguments;
    const self: *Instance = begin(instance, argument_count, 0, call_error) orelse return;
    const payload: []const u8 = receive(self);
    godot.setStringBytes(godot.allocator, resultSlot(result), payload) catch godot.setString(resultSlot(result), "");
}

fn receive(self: *Instance) []const u8 {
    var connection: *ipc.Connection = &(self.connection orelse return "");
    // Take everything that has arrived (never waits).
    var chunk: [4096]u8 = undefined;
    while (true) {
        const count: usize = connection.readAvailable(&chunk) catch {
            self.close();
            return "";
        };
        if (count == 0) break;
        self.reader.push(godot.allocator, chunk[0..count]) catch {
            self.close();
            return "";
        };
    }
    const frame: ipc.FrameReader.Frame = (self.reader.next() catch {
        self.close();
        return "";
    }) orelse return "";
    self.last_opcode = frame.opcode;
    return frame.payload;
}

/// `last_opcode() -> int`: opcode of the frame `receive()` returned last.
fn callLastOpcode(_: ?*anyopaque, instance: c.GDExtensionClassInstancePtr, arguments: [*c]const c.GDExtensionConstVariantPtr,
    argument_count: c.GDExtensionInt, result: c.GDExtensionVariantPtr, call_error: [*c]c.GDExtensionCallError) callconv(.c) void {
    _ = arguments;
    const self: *Instance = begin(instance, argument_count, 0, call_error) orelse return;
    godot.setInt(resultSlot(result), self.last_opcode);
}

/// `is_open() -> bool`
fn callIsOpen(_: ?*anyopaque, instance: c.GDExtensionClassInstancePtr, arguments: [*c]const c.GDExtensionConstVariantPtr,
    argument_count: c.GDExtensionInt, result: c.GDExtensionVariantPtr, call_error: [*c]c.GDExtensionCallError) callconv(.c) void {
    _ = arguments;
    const self: *Instance = begin(instance, argument_count, 0, call_error) orelse return;
    godot.setBool(resultSlot(result), self.connection != null);
}

/// `close() -> bool`
fn callClose(_: ?*anyopaque, instance: c.GDExtensionClassInstancePtr, arguments: [*c]const c.GDExtensionConstVariantPtr,
    argument_count: c.GDExtensionInt, result: c.GDExtensionVariantPtr, call_error: [*c]c.GDExtensionCallError) callconv(.c) void {
    _ = arguments;
    const self: *Instance = begin(instance, argument_count, 0, call_error) orelse return;
    self.close();
    godot.setBool(resultSlot(result), true);
}
