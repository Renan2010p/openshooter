//! Thin, explicit layer over Godot's GDExtension C interface.
//!
//! Godot hands the extension ONE function, `get_proc_address`, and every other
//! engine function is looked up by name through it. This file:
//!
//!   1. loads those functions into the `api` table (`load()`),
//!   2. defines the opaque Godot value types (String, Array, Variant...) as
//!      fixed-size byte buffers that Godot fills in,
//!   3. wraps the handful of operations the extension needs (make strings,
//!      build packed arrays, dictionaries and arrays),
//!   4. exposes Godot's own allocator as a `std.mem.Allocator`.
//!
//! The C declarations come from `gdextension_interface.h` (dumped from
//! Godot 4.7.2 with `godot --dump-gdextension-interface`), translated to Zig
//! at build time by the `translate_c` package and imported as `c`.

const std: type = @import("std");
pub const c: type = @import("c");

// ===========================================================================
// Opaque Godot values
// ===========================================================================
//
// Godot builtin types are opaque to extensions: we only reserve memory of the
// right size and let Godot construct, copy and destroy them.
//
// Sizes come from `extension_api.json` ("builtin_class_sizes"). They depend on
// the pointer size: 64-bit builds use the numbers below, 32-bit builds
// (Android armv7) use smaller ones. Reserving the 64-bit size everywhere is
// always safe (Godot never writes past the real size), so one definition
// serves every platform.

/// String, StringName, Array, Dictionary: one pointer.
const POINTER_VALUE_SIZE: usize = 8;
/// Packed*Array: a pointer plus a copy-on-write pointer.
const PACKED_ARRAY_SIZE: usize = 16;
/// Variant: a type tag plus 16 bytes of payload.
const VARIANT_SIZE: usize = 24;

pub const String = extern struct {
    opaque_data: [POINTER_VALUE_SIZE]u8 align(8) = undefined,

    /// New String from UTF-8 text. Call `deinit()` when done.
    pub fn fromUtf8(text: [:0]const u8) String {
        var out: String = .{};
        api.string_new_with_utf8_chars.?(@ptrCast(&out), text.ptr);
        return out;
    }

    pub fn deinit(self: *String) void {
        destructors.string.?(@ptrCast(self));
    }
};

pub const StringName = extern struct {
    opaque_data: [POINTER_VALUE_SIZE]u8 align(8) = undefined,

    /// New StringName from Latin-1 text. Call `deinit()` when done.
    pub fn fromLatin1(text: [:0]const u8) StringName {
        var out: StringName = .{};
        const is_static: c.GDExtensionBool = 0;
        api.string_name_new_with_latin1_chars.?(@ptrCast(&out), text.ptr, is_static);
        return out;
    }

    pub fn deinit(self: *StringName) void {
        destructors.string_name.?(@ptrCast(self));
    }
};

pub const Variant = extern struct {
    opaque_data: [VARIANT_SIZE]u8 align(8) = undefined,
};

pub const Array = extern struct {
    opaque_data: [POINTER_VALUE_SIZE]u8 align(8) = undefined,

    /// New empty Array. Call `deinit()` when done.
    pub fn init() Array {
        var out: Array = .{};
        constructors.array.?(@ptrCast(&out), null);
        return out;
    }

    pub fn deinit(self: *Array) void {
        destructors.array.?(@ptrCast(self));
    }

    pub fn resize(self: *Array, new_size: usize) void {
        callResize(methods.array_resize, @ptrCast(self), new_size);
    }

    /// Slot `index` (must be < size). Write into it with `Variant` setters.
    pub fn slot(self: *Array, index: usize) *Variant {
        return @ptrCast(@alignCast(api.array_operator_index.?(@ptrCast(self), @intCast(index))));
    }
};

pub const Dictionary = extern struct {
    opaque_data: [POINTER_VALUE_SIZE]u8 align(8) = undefined,

    /// New empty Dictionary. Call `deinit()` when done.
    pub fn init() Dictionary {
        var out: Dictionary = .{};
        constructors.dictionary.?(@ptrCast(&out), null);
        return out;
    }

    pub fn deinit(self: *Dictionary) void {
        destructors.dictionary.?(@ptrCast(self));
    }

    /// The value slot for String key `key` (created if missing).
    pub fn slot(self: *Dictionary, key: [:0]const u8) *Variant {
        var key_string: String = .fromUtf8(key);
        defer key_string.deinit();
        var key_variant: Variant = .{};
        from_type.string.?(@ptrCast(&key_variant), @ptrCast(&key_string));
        defer api.variant_destroy.?(@ptrCast(&key_variant));
        return @ptrCast(@alignCast(api.dictionary_operator_index.?(@ptrCast(self), @ptrCast(&key_variant))));
    }
};

/// The packed array types the extension uses, and their element types.
pub const PackedKind = enum {
    float32,
    int32,
    vector2,
    vector3,
    color,
};

/// Packed*Array of one `kind`. Element memory layouts match the mesher's
/// `Vector2`, `Vector3`, `Color`, `i32` and `f32`.
pub fn PackedArray(comptime kind: PackedKind, comptime Element: type) type {
    return extern struct {
        const Self = @This();

        opaque_data: [PACKED_ARRAY_SIZE]u8 align(8) = undefined,

        /// New Packed*Array holding a copy of `items`. Call `deinit()`.
        pub fn fromSlice(items: []const Element) Self {
            var out: Self = .{};
            packedConstructor(kind).?(@ptrCast(&out), null);
            if (items.len > 0) {
                callResize(packedResize(kind), @ptrCast(&out), items.len);
                const data: [*]Element = @ptrCast(@alignCast(packedIndex(kind, @ptrCast(&out), 0)));
                @memcpy(data[0..items.len], items);
            }
            return out;
        }

        pub fn deinit(self: *Self) void {
            packedDestructor(kind).?(@ptrCast(self));
        }
    };
}

// ===========================================================================
// Variant <-> value conversion
// ===========================================================================

/// Writes `value` into an uninitialized (or Nil) variant slot.
pub fn setBool(slot: *Variant, value: bool) void {
    var raw: c.GDExtensionBool = @intFromBool(value);
    from_type.boolean.?(@ptrCast(slot), @ptrCast(&raw));
}

pub fn setInt(slot: *Variant, value: i64) void {
    var copy: i64 = value;
    from_type.int.?(@ptrCast(slot), @ptrCast(&copy));
}

pub fn setVector3(slot: *Variant, value: anytype) void {
    var copy = value; // Godot reads through a mutable pointer
    from_type.vector3.?(@ptrCast(slot), @ptrCast(&copy));
}

pub fn setString(slot: *Variant, text: [:0]const u8) void {
    var value: String = .fromUtf8(text);
    defer value.deinit();
    from_type.string.?(@ptrCast(slot), @ptrCast(&value));
}

pub fn setDictionary(slot: *Variant, value: *Dictionary) void {
    from_type.dictionary.?(@ptrCast(slot), @ptrCast(value));
}

pub fn setArray(slot: *Variant, value: *Array) void {
    from_type.array.?(@ptrCast(slot), @ptrCast(value));
}

/// Copies a packed array into a variant slot (Godot keeps its own reference;
/// the caller still owns and must `deinit()` `value`).
pub fn setPacked(slot: *Variant, comptime kind: PackedKind, value: anytype) void {
    packedFromType(kind).?(@ptrCast(slot), @ptrCast(value));
}

/// The Variant.Type of an argument.
pub fn variantType(value: c.GDExtensionConstVariantPtr) c.GDExtensionVariantType {
    return api.variant_get_type.?(value);
}

pub fn toInt(value: c.GDExtensionConstVariantPtr) i64 {
    var out: i64 = 0;
    to_type.int.?(@ptrCast(&out), @constCast(value));
    return out;
}

/// The text of a String variant as UTF-8, allocated with `gpa` (caller frees).
pub fn toUtf8(gpa: std.mem.Allocator, value: c.GDExtensionConstVariantPtr) std.mem.Allocator.Error![]u8 {
    var string: String = .{};
    to_type.string.?(@ptrCast(&string), @constCast(value));
    defer string.deinit();
    // First call: length only; second call: the bytes.
    const length: c.GDExtensionInt = api.string_to_utf8_chars.?(@ptrCast(&string), null, 0);
    const bytes: []u8 = try gpa.alloc(u8, @intCast(@max(length, 0)));
    _ = api.string_to_utf8_chars.?(@ptrCast(&string), bytes.ptr, length);
    return bytes;
}

/// Writes UTF-8 `text` (not zero-terminated) into a variant slot as a String.
pub fn setStringBytes(gpa: std.mem.Allocator, slot: *Variant, text: []const u8) std.mem.Allocator.Error!void {
    const terminated: [:0]u8 = try gpa.allocSentinel(u8, text.len, 0);
    defer gpa.free(terminated);
    @memcpy(terminated, text);
    setString(slot, terminated);
}

pub fn toFloat(value: c.GDExtensionConstVariantPtr) f64 {
    var out: f64 = 0.0;
    to_type.float.?(@ptrCast(&out), @constCast(value));
    return out;
}

/// A PackedFloat32Array copied out of a variant. Call `deinit()` when done.
pub const PackedFloat32 = PackedArray(.float32, f32);

pub fn toPackedFloat32(value: c.GDExtensionConstVariantPtr) PackedFloat32 {
    var out: PackedFloat32 = .{};
    to_type.packed_float32.?(@ptrCast(&out), @constCast(value));
    return out;
}

/// Read-only view of a PackedFloat32Array's contents (valid while `array`
/// lives and is not modified).
pub fn packedFloat32Slice(array: *const PackedFloat32, len: usize) []const f32 {
    if (len == 0) {
        return &.{};
    }
    const data: [*]const f32 = @ptrCast(@alignCast(api.packed_float32_array_operator_index_const.?(@ptrCast(array), 0)));
    return data[0..len];
}

/// Number of elements of a PackedFloat32Array.
pub fn packedFloat32Size(array: *const PackedFloat32) usize {
    var size: i64 = 0;
    methods.packed_float32_size.?(@ptrCast(@constCast(array)), null, @ptrCast(&size), 0);
    return @intCast(@max(size, 0));
}

// ===========================================================================
// Godot's allocator as a std.mem.Allocator
// ===========================================================================
//
// All memory the mesher uses comes from Godot (so it shows up in Godot's
// memory monitors, and no libc is needed). `mem_alloc2` returns blocks
// aligned like malloc: at least MAX_ALIGNMENT bytes.

const MAX_ALIGNMENT: usize = 2 * @sizeOf(usize);
const NO_PADDING: c.GDExtensionBool = 0;

pub const allocator: std.mem.Allocator = .{
    .ptr = undefined,
    .vtable = &.{
        .alloc = godotAlloc,
        .resize = godotResize,
        .remap = godotRemap,
        .free = godotFree,
    },
};

fn godotAlloc(_: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
    if (alignment.toByteUnits() > MAX_ALIGNMENT) {
        return null;
    }
    const memory: ?*anyopaque = api.mem_alloc2.?(len, NO_PADDING);
    return @ptrCast(memory);
}

/// In-place resize: only shrinking is possible without moving.
fn godotResize(_: *anyopaque, memory: []u8, _: std.mem.Alignment, new_len: usize, _: usize) bool {
    return new_len <= memory.len;
}

/// Resize that may move the block (Godot's realloc).
fn godotRemap(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, _: usize) ?[*]u8 {
    if (alignment.toByteUnits() > MAX_ALIGNMENT) {
        return null;
    }
    const moved: ?*anyopaque = api.mem_realloc2.?(memory.ptr, new_len, NO_PADDING);
    return @ptrCast(moved);
}

fn godotFree(_: *anyopaque, memory: []u8, _: std.mem.Alignment, _: usize) void {
    api.mem_free2.?(memory.ptr, NO_PADDING);
}

// ===========================================================================
// The function table
// ===========================================================================

/// Engine functions, looked up by name. Every field name is EXACTLY the name
/// Godot registers (see `gdextension_interface.h`), so `load()` can fill the
/// whole table with one loop.
pub const Api = struct {
    // Class registration.
    classdb_register_extension_class6: c.GDExtensionInterfaceClassdbRegisterExtensionClass6 = null,
    classdb_unregister_extension_class: c.GDExtensionInterfaceClassdbUnregisterExtensionClass = null,
    classdb_register_extension_class_method: c.GDExtensionInterfaceClassdbRegisterExtensionClassMethod = null,
    classdb_construct_object3: c.GDExtensionInterfaceClassdbConstructObject3 = null,
    object_set_instance: c.GDExtensionInterfaceObjectSetInstance = null,

    // Strings.
    string_name_new_with_latin1_chars: c.GDExtensionInterfaceStringNameNewWithLatin1Chars = null,
    string_new_with_utf8_chars: c.GDExtensionInterfaceStringNewWithUtf8Chars = null,
    string_to_utf8_chars: c.GDExtensionInterfaceStringToUtf8Chars = null,

    // Variants and builtin types.
    get_variant_from_type_constructor: c.GDExtensionInterfaceGetVariantFromTypeConstructor = null,
    get_variant_to_type_constructor: c.GDExtensionInterfaceGetVariantToTypeConstructor = null,
    variant_get_type: c.GDExtensionInterfaceVariantGetType = null,
    variant_get_ptr_constructor: c.GDExtensionInterfaceVariantGetPtrConstructor = null,
    variant_get_ptr_destructor: c.GDExtensionInterfaceVariantGetPtrDestructor = null,
    variant_get_ptr_builtin_method: c.GDExtensionInterfaceVariantGetPtrBuiltinMethod = null,
    variant_destroy: c.GDExtensionInterfaceVariantDestroy = null,

    // Element access.
    array_operator_index: c.GDExtensionInterfaceArrayOperatorIndex = null,
    dictionary_operator_index: c.GDExtensionInterfaceDictionaryOperatorIndex = null,
    packed_float32_array_operator_index: c.GDExtensionInterfacePackedFloat32ArrayOperatorIndex = null,
    packed_float32_array_operator_index_const: c.GDExtensionInterfacePackedFloat32ArrayOperatorIndexConst = null,
    packed_int32_array_operator_index: c.GDExtensionInterfacePackedInt32ArrayOperatorIndex = null,
    packed_vector2_array_operator_index: c.GDExtensionInterfacePackedVector2ArrayOperatorIndex = null,
    packed_vector3_array_operator_index: c.GDExtensionInterfacePackedVector3ArrayOperatorIndex = null,
    packed_color_array_operator_index: c.GDExtensionInterfacePackedColorArrayOperatorIndex = null,

    // Memory.
    mem_alloc2: c.GDExtensionInterfaceMemAlloc2 = null,
    mem_realloc2: c.GDExtensionInterfaceMemRealloc2 = null,
    mem_free2: c.GDExtensionInterfaceMemFree2 = null,
};

/// The loaded table. Valid after `load()` succeeds.
pub var api: Api = .{};
/// The library handle Godot gave us; needed to register classes.
pub var library: c.GDExtensionClassLibraryPtr = null;

/// Variant <- value constructors.
var from_type: struct {
    boolean: c.GDExtensionVariantFromTypeConstructorFunc = null,
    int: c.GDExtensionVariantFromTypeConstructorFunc = null,
    string: c.GDExtensionVariantFromTypeConstructorFunc = null,
    vector3: c.GDExtensionVariantFromTypeConstructorFunc = null,
    array: c.GDExtensionVariantFromTypeConstructorFunc = null,
    dictionary: c.GDExtensionVariantFromTypeConstructorFunc = null,
    packed_float32: c.GDExtensionVariantFromTypeConstructorFunc = null,
    packed_int32: c.GDExtensionVariantFromTypeConstructorFunc = null,
    packed_vector2: c.GDExtensionVariantFromTypeConstructorFunc = null,
    packed_vector3: c.GDExtensionVariantFromTypeConstructorFunc = null,
    packed_color: c.GDExtensionVariantFromTypeConstructorFunc = null,
} = .{};

/// value <- Variant constructors.
var to_type: struct {
    int: c.GDExtensionTypeFromVariantConstructorFunc = null,
    string: c.GDExtensionTypeFromVariantConstructorFunc = null,
    float: c.GDExtensionTypeFromVariantConstructorFunc = null,
    packed_float32: c.GDExtensionTypeFromVariantConstructorFunc = null,
} = .{};

/// Default constructors (`Type()`), index 0 of each builtin type.
var constructors: struct {
    array: c.GDExtensionPtrConstructor = null,
    dictionary: c.GDExtensionPtrConstructor = null,
    packed_float32: c.GDExtensionPtrConstructor = null,
    packed_int32: c.GDExtensionPtrConstructor = null,
    packed_vector2: c.GDExtensionPtrConstructor = null,
    packed_vector3: c.GDExtensionPtrConstructor = null,
    packed_color: c.GDExtensionPtrConstructor = null,
} = .{};

var destructors: struct {
    string: c.GDExtensionPtrDestructor = null,
    string_name: c.GDExtensionPtrDestructor = null,
    array: c.GDExtensionPtrDestructor = null,
    dictionary: c.GDExtensionPtrDestructor = null,
    packed_float32: c.GDExtensionPtrDestructor = null,
    packed_int32: c.GDExtensionPtrDestructor = null,
    packed_vector2: c.GDExtensionPtrDestructor = null,
    packed_vector3: c.GDExtensionPtrDestructor = null,
    packed_color: c.GDExtensionPtrDestructor = null,
} = .{};

/// Builtin methods, looked up by name and hash.
var methods: struct {
    array_resize: c.GDExtensionPtrBuiltInMethod = null,
    packed_float32_resize: c.GDExtensionPtrBuiltInMethod = null,
    packed_int32_resize: c.GDExtensionPtrBuiltInMethod = null,
    packed_vector2_resize: c.GDExtensionPtrBuiltInMethod = null,
    packed_vector3_resize: c.GDExtensionPtrBuiltInMethod = null,
    packed_color_resize: c.GDExtensionPtrBuiltInMethod = null,
    packed_float32_size: c.GDExtensionPtrBuiltInMethod = null,
} = .{};

/// Hash of `int resize(int new_size)` in extension_api.json. It is the same
/// for Array and every Packed*Array.
const RESIZE_HASH: c.GDExtensionInt = 848867239;
/// Hash of `int size() const` on Packed*Array.
const SIZE_HASH: c.GDExtensionInt = 3173160232;

pub const LoadError = error{MissingFunction};

/// Fills every table from `get_proc_address`. Fails if Godot lacks any
/// function (for example, a Godot older than 4.7).
pub fn load(get_proc_address: c.GDExtensionInterfaceGetProcAddress, library_handle: c.GDExtensionClassLibraryPtr) LoadError!void {
    library = library_handle;
    const lookup = get_proc_address orelse return error.MissingFunction;

    // 1) Interface functions: field name == registered name.
    inline for (comptime std.meta.fieldNames(Api)) |field_name| {
        const function: c.GDExtensionInterfaceFunctionPtr = lookup(field_name);
        if (function == null) {
            return error.MissingFunction;
        }
        @field(api, field_name) = @ptrCast(function);
    }

    // 2) Builtin type helpers.
    const T: type = VariantTypes;
    from_type = .{
        .boolean = api.get_variant_from_type_constructor.?(T.boolean),
        .int = api.get_variant_from_type_constructor.?(T.int),
        .string = api.get_variant_from_type_constructor.?(T.string),
        .vector3 = api.get_variant_from_type_constructor.?(T.vector3),
        .array = api.get_variant_from_type_constructor.?(T.array),
        .dictionary = api.get_variant_from_type_constructor.?(T.dictionary),
        .packed_float32 = api.get_variant_from_type_constructor.?(T.packed_float32),
        .packed_int32 = api.get_variant_from_type_constructor.?(T.packed_int32),
        .packed_vector2 = api.get_variant_from_type_constructor.?(T.packed_vector2),
        .packed_vector3 = api.get_variant_from_type_constructor.?(T.packed_vector3),
        .packed_color = api.get_variant_from_type_constructor.?(T.packed_color),
    };
    to_type = .{
        .int = api.get_variant_to_type_constructor.?(T.int),
        .string = api.get_variant_to_type_constructor.?(T.string),
        .float = api.get_variant_to_type_constructor.?(T.float),
        .packed_float32 = api.get_variant_to_type_constructor.?(T.packed_float32),
    };
    constructors = .{
        .array = api.variant_get_ptr_constructor.?(T.array, 0),
        .dictionary = api.variant_get_ptr_constructor.?(T.dictionary, 0),
        .packed_float32 = api.variant_get_ptr_constructor.?(T.packed_float32, 0),
        .packed_int32 = api.variant_get_ptr_constructor.?(T.packed_int32, 0),
        .packed_vector2 = api.variant_get_ptr_constructor.?(T.packed_vector2, 0),
        .packed_vector3 = api.variant_get_ptr_constructor.?(T.packed_vector3, 0),
        .packed_color = api.variant_get_ptr_constructor.?(T.packed_color, 0),
    };
    destructors = .{
        .string = api.variant_get_ptr_destructor.?(T.string),
        .string_name = api.variant_get_ptr_destructor.?(T.string_name),
        .array = api.variant_get_ptr_destructor.?(T.array),
        .dictionary = api.variant_get_ptr_destructor.?(T.dictionary),
        .packed_float32 = api.variant_get_ptr_destructor.?(T.packed_float32),
        .packed_int32 = api.variant_get_ptr_destructor.?(T.packed_int32),
        .packed_vector2 = api.variant_get_ptr_destructor.?(T.packed_vector2),
        .packed_vector3 = api.variant_get_ptr_destructor.?(T.packed_vector3),
        .packed_color = api.variant_get_ptr_destructor.?(T.packed_color),
    };
    methods = .{
        .array_resize = builtinMethod(T.array, "resize", RESIZE_HASH),
        .packed_float32_resize = builtinMethod(T.packed_float32, "resize", RESIZE_HASH),
        .packed_int32_resize = builtinMethod(T.packed_int32, "resize", RESIZE_HASH),
        .packed_vector2_resize = builtinMethod(T.packed_vector2, "resize", RESIZE_HASH),
        .packed_vector3_resize = builtinMethod(T.packed_vector3, "resize", RESIZE_HASH),
        .packed_color_resize = builtinMethod(T.packed_color, "resize", RESIZE_HASH),
        .packed_float32_size = builtinMethod(T.packed_float32, "size", SIZE_HASH),
    };

    // 3) Every helper must exist.
    inline for (.{ from_type, to_type, constructors, destructors, methods }) |table| {
        inline for (comptime std.meta.fieldNames(@TypeOf(table))) |field_name| {
            if (@field(table, field_name) == null) {
                return error.MissingFunction;
            }
        }
    }
}

/// Variant.Type values used above, with short names.
pub const VariantTypes = struct {
    pub const nil: c.GDExtensionVariantType = c.GDEXTENSION_VARIANT_TYPE_NIL;
    pub const boolean: c.GDExtensionVariantType = c.GDEXTENSION_VARIANT_TYPE_BOOL;
    pub const int: c.GDExtensionVariantType = c.GDEXTENSION_VARIANT_TYPE_INT;
    pub const float: c.GDExtensionVariantType = c.GDEXTENSION_VARIANT_TYPE_FLOAT;
    pub const string: c.GDExtensionVariantType = c.GDEXTENSION_VARIANT_TYPE_STRING;
    pub const vector3: c.GDExtensionVariantType = c.GDEXTENSION_VARIANT_TYPE_VECTOR3;
    pub const string_name: c.GDExtensionVariantType = c.GDEXTENSION_VARIANT_TYPE_STRING_NAME;
    pub const dictionary: c.GDExtensionVariantType = c.GDEXTENSION_VARIANT_TYPE_DICTIONARY;
    pub const array: c.GDExtensionVariantType = c.GDEXTENSION_VARIANT_TYPE_ARRAY;
    pub const packed_int32: c.GDExtensionVariantType = c.GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY;
    pub const packed_float32: c.GDExtensionVariantType = c.GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY;
    pub const packed_vector2: c.GDExtensionVariantType = c.GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY;
    pub const packed_vector3: c.GDExtensionVariantType = c.GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY;
    pub const packed_color: c.GDExtensionVariantType = c.GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY;
};

fn builtinMethod(variant_type: c.GDExtensionVariantType, name: [:0]const u8, hash: c.GDExtensionInt) c.GDExtensionPtrBuiltInMethod {
    var method_name: StringName = .fromLatin1(name);
    defer method_name.deinit();
    return api.variant_get_ptr_builtin_method.?(variant_type, @ptrCast(&method_name), hash);
}

/// Calls `resize(new_size)` on an Array or Packed*Array.
fn callResize(method: c.GDExtensionPtrBuiltInMethod, self: c.GDExtensionTypePtr, new_size: usize) void {
    const size_argument: i64 = @intCast(new_size);
    const arguments: [1]c.GDExtensionConstTypePtr = .{@ptrCast(&size_argument)};
    var error_code: i64 = 0; // resize() returns an Error enum value
    method.?(self, &arguments, @ptrCast(&error_code), arguments.len);
}

fn packedConstructor(comptime kind: PackedKind) c.GDExtensionPtrConstructor {
    return switch (kind) {
        .float32 => constructors.packed_float32,
        .int32 => constructors.packed_int32,
        .vector2 => constructors.packed_vector2,
        .vector3 => constructors.packed_vector3,
        .color => constructors.packed_color,
    };
}

fn packedDestructor(comptime kind: PackedKind) c.GDExtensionPtrDestructor {
    return switch (kind) {
        .float32 => destructors.packed_float32,
        .int32 => destructors.packed_int32,
        .vector2 => destructors.packed_vector2,
        .vector3 => destructors.packed_vector3,
        .color => destructors.packed_color,
    };
}

fn packedResize(comptime kind: PackedKind) c.GDExtensionPtrBuiltInMethod {
    return switch (kind) {
        .float32 => methods.packed_float32_resize,
        .int32 => methods.packed_int32_resize,
        .vector2 => methods.packed_vector2_resize,
        .vector3 => methods.packed_vector3_resize,
        .color => methods.packed_color_resize,
    };
}

fn packedFromType(comptime kind: PackedKind) c.GDExtensionVariantFromTypeConstructorFunc {
    return switch (kind) {
        .float32 => from_type.packed_float32,
        .int32 => from_type.packed_int32,
        .vector2 => from_type.packed_vector2,
        .vector3 => from_type.packed_vector3,
        .color => from_type.packed_color,
    };
}

/// Pointer to element `index` of a packed array (writable).
fn packedIndex(comptime kind: PackedKind, self: c.GDExtensionTypePtr, index: c.GDExtensionInt) ?*anyopaque {
    return switch (kind) {
        .float32 => @ptrCast(api.packed_float32_array_operator_index.?(self, index)),
        .int32 => @ptrCast(api.packed_int32_array_operator_index.?(self, index)),
        .vector2 => @ptrCast(api.packed_vector2_array_operator_index.?(self, index)),
        .vector3 => @ptrCast(api.packed_vector3_array_operator_index.?(self, index)),
        .color => @ptrCast(api.packed_color_array_operator_index.?(self, index)),
    };
}

// ===========================================================================
// Method registration helpers
// ===========================================================================

pub const Argument = struct {
    name: [:0]const u8,
    variant_type: c.GDExtensionVariantType,
};

/// The most arguments any bound method takes.
const MAX_ARGUMENTS: usize = 4;

/// Registers method `name` of extension class `class`, called through
/// Variants (`call_func`). The method has a
/// return value of `return_type` and the listed arguments.
pub fn bindMethod(comptime class: [:0]const u8, comptime name: [:0]const u8, call: c.GDExtensionClassMethodCall, return_type: c.GDExtensionVariantType, comptime arguments: []const Argument) void {
    comptime std.debug.assert(arguments.len <= MAX_ARGUMENTS);

    var method_name: StringName = .fromLatin1(name);
    defer method_name.deinit();
    var class_name: StringName = .fromLatin1(class);
    defer class_name.deinit();

    var return_info: OwnedProperty = undefined;
    return_info.init(return_type, "");
    defer return_info.deinit();

    var argument_props: [MAX_ARGUMENTS]OwnedProperty = undefined;
    var argument_infos: [MAX_ARGUMENTS]c.GDExtensionPropertyInfo = undefined;
    var argument_metadata: [MAX_ARGUMENTS]c.GDExtensionClassMethodArgumentMetadata = undefined;
    inline for (arguments, 0..) |argument, i| {
        argument_props[i].init(argument.variant_type, argument.name);
        argument_infos[i] = argument_props[i].info;
        argument_metadata[i] = c.GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
    }
    defer inline for (0..arguments.len) |i| {
        argument_props[i].deinit();
    };

    var info: c.GDExtensionClassMethodInfo = .{
        .name = @ptrCast(&method_name),
        .method_userdata = null,
        .call_func = call,
        .ptrcall_func = null,
        .method_flags = c.GDEXTENSION_METHOD_FLAGS_DEFAULT,
        .has_return_value = 1,
        .return_value_info = &return_info.info,
        .return_value_metadata = c.GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,
        .argument_count = @intCast(arguments.len),
        .arguments_info = if (arguments.len > 0) &argument_infos else null,
        .arguments_metadata = if (arguments.len > 0) &argument_metadata else null,
        .default_argument_count = 0,
        .default_arguments = null,
    };
    api.classdb_register_extension_class_method.?(library, @ptrCast(&class_name), &info);
}


/// PropertyInfo for one argument or return value, plus the strings it points
/// to. Godot copies everything during registration, so it can be freed right
/// after `classdb_register_extension_class_method`.
pub const OwnedProperty = struct {
    name: StringName,
    class_name: StringName,
    hint_string: String,
    info: c.GDExtensionPropertyInfo,

    /// PROPERTY_HINT_NONE and PROPERTY_USAGE_DEFAULT from Godot's enums.
    const HINT_NONE: u32 = 0;
    const USAGE_DEFAULT: u32 = 6; // STORAGE (2) | EDITOR (4)

    /// Must be called on the final location (the info points into self).
    pub fn init(self: *OwnedProperty, variant_type: c.GDExtensionVariantType, name: [:0]const u8) void {
        self.name = .fromLatin1(name);
        self.class_name = .fromLatin1("");
        self.hint_string = .fromUtf8("");
        self.info = .{
            .type = variant_type,
            .name = @ptrCast(&self.name),
            .class_name = @ptrCast(&self.class_name),
            .hint = HINT_NONE,
            .hint_string = @ptrCast(&self.hint_string),
            .usage = USAGE_DEFAULT,
        };
    }

    pub fn deinit(self: *OwnedProperty) void {
        self.name.deinit();
        self.class_name.deinit();
        self.hint_string.deinit();
    }
};
