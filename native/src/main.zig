//! Entry point of the OpenShooter native module (a Godot GDExtension).
//!
//! Godot loads the shared library listed in `openshooter_native.gdextension`
//! and calls the exported function named by its `entry_symbol`:
//! `openshooter_native_init`. That function:
//!
//!   1. loads the engine function table (`godot.load`),
//!   2. tells Godot which callbacks to run at each initialization level.
//!
//! At the SCENE level we register the `NativeOps` (map mesher) and
//! `DiscordIpc` (Rich Presence channel) classes; at shutdown we unregister
//! them.

const std: type = @import("std");
const godot: type = @import("godot.zig");
const native_ops: type = @import("native_ops.zig");
const discord_class: type = @import("discord_class.zig");

const c: type = godot.c;

/// Called by Godot when the library is loaded. Returns 1 on success.
export fn openshooter_native_init(
    get_proc_address: c.GDExtensionInterfaceGetProcAddress,
    library: c.GDExtensionClassLibraryPtr,
    initialization: [*c]c.GDExtensionInitialization,
) callconv(.c) c.GDExtensionBool {
    godot.load(get_proc_address, library) catch {
        // Godot is missing a function we need (older engine?): refuse to
        // load. The game then uses its GDScript mesher.
        return 0;
    };
    initialization.*.initialize = initialize;
    initialization.*.deinitialize = deinitialize;
    initialization.*.userdata = null;
    initialization.*.minimum_initialization_level = c.GDEXTENSION_INITIALIZATION_SCENE;
    return 1;
}

fn initialize(userdata: ?*anyopaque, level: c.GDExtensionInitializationLevel) callconv(.c) void {
    _ = userdata;
    if (level != c.GDEXTENSION_INITIALIZATION_SCENE) {
        return;
    }
    native_ops.register();
    discord_class.register();
}

fn deinitialize(userdata: ?*anyopaque, level: c.GDExtensionInitializationLevel) callconv(.c) void {
    _ = userdata;
    if (level != c.GDEXTENSION_INITIALIZATION_SCENE) {
        return;
    }
    discord_class.unregister();
    native_ops.unregister();
}

// `zig build test` runs the tests of every file imported from here.
test {
    _ = @import("mesher.zig");
    _ = @import("discord_ipc.zig");
}
