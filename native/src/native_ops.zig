//! The `NativeOps` class seen by GDScript (a RefCounted):
//!
//!     var ops = ClassDB.instantiate("NativeOps")
//!     ops.ping()                         # -> "pong-zig"
//!     ops.bake_map(data, count, cell)    # -> Array of Dictionary, one per chunk
//!
//! `bake_map` is used by `scripts/core/block_baker.gd`. Each returned
//! dictionary holds:
//!
//!     "origin"    Vector3              chunk center (mesh positions are relative to it)
//!     "huge"      bool                 the global chunk (ground, map borders)
//!     "detail"    bool                 small details, hidden sooner and without shadows
//!     "vertices"  PackedVector3Array
//!     "normals"   PackedVector3Array
//!     "colors"    PackedColorArray     roughness in alpha
//!     "uv2"       PackedVector2Array   x = metallic, y = emission strength
//!     "indices"   PackedInt32Array
//!     "collision" PackedVector3Array   triangle list, map coordinates
//!
//! On bad arguments or out of memory it returns an EMPTY array, and GDScript
//! falls back to its own mesher.

const std: type = @import("std");
const godot: type = @import("godot.zig");
const mesher: type = @import("mesher.zig");

const c: type = godot.c;
const T: type = godot.VariantTypes;

const CLASS_NAME: [:0]const u8 = "NativeOps";
const PARENT_CLASS_NAME: [:0]const u8 = "RefCounted";
const PING_REPLY: [:0]const u8 = "pong-zig";

/// The per-object data Godot keeps for every NativeOps instance. The class
/// has no state; this only remembers which Godot object it belongs to.
const Instance = struct {
    object: c.GDExtensionObjectPtr,
};

var registered: bool = false;

// ===========================================================================
// Registration
// ===========================================================================

pub fn register() void {
    if (registered) {
        return;
    }
    registered = true;

    var class_name: godot.StringName = .fromLatin1(CLASS_NAME);
    defer class_name.deinit();
    var parent_name: godot.StringName = .fromLatin1(PARENT_CLASS_NAME);
    defer parent_name.deinit();

    // Every field is listed on purpose: zero / null means "not used".
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

    godot.bindMethod(CLASS_NAME, "ping", callPing, T.string, &.{});
    godot.bindMethod(CLASS_NAME, "bake_map", callBakeMap, T.array, &.{
        .{ .name = "data", .variant_type = T.packed_float32 },
        .{ .name = "count", .variant_type = T.int },
        .{ .name = "cell", .variant_type = T.float },
    });
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

/// Godot asks for a new NativeOps: build the parent RefCounted object and
/// attach our instance data to it.
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
    instance.* = .{ .object = object };

    var class_name: godot.StringName = .fromLatin1(CLASS_NAME);
    defer class_name.deinit();
    godot.api.object_set_instance.?(object, @ptrCast(&class_name), instance);
    return object;
}

fn freeInstance(class_userdata: ?*anyopaque, instance: c.GDExtensionClassInstancePtr) callconv(.c) void {
    _ = class_userdata;
    const self: *Instance = @ptrCast(@alignCast(instance orelse return));
    godot.allocator.destroy(self);
}

// ===========================================================================
// Method calls
// ===========================================================================

/// Shape of every `call_func` callback.
const CallArgs = struct {
    arguments: [*c]const c.GDExtensionConstVariantPtr,
    argument_count: c.GDExtensionInt,
    result: c.GDExtensionVariantPtr,
    call_error: [*c]c.GDExtensionCallError,
};

/// Checks the argument count; reports the error to Godot on mismatch.
fn expectArgumentCount(call: CallArgs, expected: c.GDExtensionInt) bool {
    if (call.argument_count == expected) {
        return true;
    }
    call.call_error.*.@"error" = if (call.argument_count < expected)
        c.GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS
    else
        c.GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
    call.call_error.*.expected = @intCast(expected);
    return false;
}

/// `ping() -> String`
fn callPing(
    method_userdata: ?*anyopaque,
    instance: c.GDExtensionClassInstancePtr,
    arguments: [*c]const c.GDExtensionConstVariantPtr,
    argument_count: c.GDExtensionInt,
    result: c.GDExtensionVariantPtr,
    call_error: [*c]c.GDExtensionCallError,
) callconv(.c) void {
    _ = method_userdata;
    _ = instance;
    const call: CallArgs = .{ .arguments = arguments, .argument_count = argument_count, .result = result, .call_error = call_error };
    if (!expectArgumentCount(call, 0)) {
        return;
    }
    godot.setString(@ptrCast(@alignCast(result)), PING_REPLY);
}

/// `bake_map(data: PackedFloat32Array, count: int, cell: float) -> Array`
fn callBakeMap(
    method_userdata: ?*anyopaque,
    instance: c.GDExtensionClassInstancePtr,
    arguments: [*c]const c.GDExtensionConstVariantPtr,
    argument_count: c.GDExtensionInt,
    result: c.GDExtensionVariantPtr,
    call_error: [*c]c.GDExtensionCallError,
) callconv(.c) void {
    _ = method_userdata;
    _ = instance;
    const call: CallArgs = .{ .arguments = arguments, .argument_count = argument_count, .result = result, .call_error = call_error };
    if (!expectArgumentCount(call, 3)) {
        return;
    }
    const expected_types: [3]c.GDExtensionVariantType = .{ T.packed_float32, T.int, T.float };
    for (expected_types, 0..) |expected_type, i| {
        if (godot.variantType(arguments[i]) != expected_type) {
            call_error.*.@"error" = c.GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
            call_error.*.argument = @intCast(i);
            call_error.*.expected = @intCast(expected_type);
            return;
        }
    }

    // Read the arguments.
    var data: godot.PackedFloat32 = godot.toPackedFloat32(arguments[0]);
    defer data.deinit();
    const count: i64 = godot.toInt(arguments[1]);
    const cell: f64 = godot.toFloat(arguments[2]);
    const floats: []const f32 = godot.packedFloat32Slice(&data, godot.packedFloat32Size(&data));

    // Bake and convert. Any failure -> empty array (GDScript falls back).
    var out: godot.Array = .init();
    defer out.deinit();
    if (count > 0 and cell > 0.0) {
        bakeInto(&out, floats, @intCast(count), @floatCast(cell)) catch {
            out.resize(0);
        };
    }
    godot.setArray(@ptrCast(@alignCast(result)), &out);
}

/// Runs the mesher and fills `out` with one Dictionary per chunk.
fn bakeInto(out: *godot.Array, floats: []const f32, count: usize, cell: f32) std.mem.Allocator.Error!void {
    var baked: mesher.BakeResult = try mesher.bake(godot.allocator, floats, count, cell);
    defer baked.deinit(godot.allocator);

    var output_count: usize = 0;
    for (baked.chunks.items) |*chunk| {
        if (chunk.hasOutput()) output_count += 1;
    }
    out.resize(output_count);

    var slot_index: usize = 0;
    for (baked.chunks.items) |*chunk| {
        if (!chunk.hasOutput()) {
            continue;
        }
        var dictionary: godot.Dictionary = .init();
        defer dictionary.deinit();
        fillChunkDictionary(&dictionary, chunk);
        godot.setDictionary(out.slot(slot_index), &dictionary);
        slot_index += 1;
    }
}

const PackedVector3: type = godot.PackedArray(.vector3, mesher.Vector3);
const PackedVector2: type = godot.PackedArray(.vector2, mesher.Vector2);
const PackedColor: type = godot.PackedArray(.color, mesher.Color);
const PackedInt32: type = godot.PackedArray(.int32, i32);

fn fillChunkDictionary(dictionary: *godot.Dictionary, chunk: *const mesher.Chunk) void {
    godot.setVector3(dictionary.slot("origin"), chunk.origin);
    godot.setBool(dictionary.slot("huge"), chunk.huge);
    godot.setBool(dictionary.slot("detail"), chunk.detail);

    var vertices: PackedVector3 = .fromSlice(chunk.verts.items);
    defer vertices.deinit();
    godot.setPacked(dictionary.slot("vertices"), .vector3, &vertices);

    var normals: PackedVector3 = .fromSlice(chunk.norms.items);
    defer normals.deinit();
    godot.setPacked(dictionary.slot("normals"), .vector3, &normals);

    var colors: PackedColor = .fromSlice(chunk.cols.items);
    defer colors.deinit();
    godot.setPacked(dictionary.slot("colors"), .color, &colors);

    var uv2: PackedVector2 = .fromSlice(chunk.uv2.items);
    defer uv2.deinit();
    godot.setPacked(dictionary.slot("uv2"), .vector2, &uv2);

    var indices: PackedInt32 = .fromSlice(chunk.idx.items);
    defer indices.deinit();
    godot.setPacked(dictionary.slot("indices"), .int32, &indices);

    var collision: PackedVector3 = .fromSlice(chunk.collision.items);
    defer collision.deinit();
    godot.setPacked(dictionary.slot("collision"), .vector3, &collision);
}

// The mesher's types must match Godot's memory layout exactly, because packed
// arrays are filled with a plain memcpy.
comptime {
    std.debug.assert(@sizeOf(mesher.Vector3) == 12);
    std.debug.assert(@sizeOf(mesher.Vector2) == 8);
    std.debug.assert(@sizeOf(mesher.Color) == 16);
}
