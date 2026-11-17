//! Build script of the OpenShooter native module (Godot GDExtension, Zig).
//!
//! USAGE (run inside native/):
//!
//!   zig build linux      -> bin/libopenshooter_native.so
//!   zig build windows    -> bin/openshooter_native.dll
//!   zig build macos      -> bin/libopenshooter_native.macos.dylib  (universal: Intel + Apple Silicon)
//!   zig build android    -> bin/libopenshooter_native.android.so   (arm64)
//!                           bin/libopenshooter_native.android-arm32.so (armv7)
//!   zig build freebsd    -> bin/libopenshooter_native.freebsd.so
//!   zig build all        -> every library above
//!   zig build test       -> run the mesher unit tests
//!
//! Options:
//!   -Dmatch_c=true       reproduce the old C module's output exactly
//!                        (only to compare against it; see src/mesher.zig)
//!
//! Every library is built WITHOUT libc: math comes from Zig and memory from
//! Godot's allocator. That is why one Linux host can build every platform,
//! Android included, without the NDK.

const std: type = @import("std");
const builtin: type = std.builtin;
const Builder: type = std.Build;
const Translator: type = @import("translate_c").Translator;

/// The C header translated into the Zig module `c` (Godot's GDExtension API).
const C_HEADER: []const u8 = "src/c.h";
/// Root source file of the library.
const ROOT_SOURCE: []const u8 = "src/main.zig";
/// Base name of the library; Zig adds the platform prefix/extension.
const LIBRARY_NAME: []const u8 = "openshooter_native";

/// One library to produce, and where it goes in native/bin/.
const Platform = struct {
    /// Zig target triple, e.g. "x86_64-linux-gnu".
    triple: []const u8,
    /// CPU model and features ("baseline" = the oldest CPU of the arch).
    cpu: []const u8 = "baseline",
    /// File name inside native/bin/ (must match openshooter_native.gdextension).
    output: []const u8,
    /// Android 15+ devices may use 16 KB memory pages; their libraries must
    /// be aligned to that.
    page_size_16k: bool = false,
};

const LINUX: Platform = .{ .triple = "x86_64-linux-gnu", .output = "bin/libopenshooter_native.so" };
const WINDOWS: Platform = .{ .triple = "x86_64-windows-gnu", .output = "bin/openshooter_native.dll" };
const FREEBSD: Platform = .{ .triple = "x86_64-freebsd", .output = "bin/libopenshooter_native.freebsd.so" };
const ANDROID_ARM64: Platform = .{
    .triple = "aarch64-linux-android",
    .output = "bin/libopenshooter_native.android.so",
    .page_size_16k = true,
};
/// armeabi-v7a: ARMv7-A with Thumb-2, VFPv3-D16 and NEON (NDK defaults).
const ANDROID_ARM32: Platform = .{
    .triple = "arm-linux-androideabi",
    .cpu = "generic+v7a+thumb2+vfp3d16+neon",
    .output = "bin/libopenshooter_native.android-arm32.so",
};
/// macOS: both architectures are built, then merged by lipo.py.
const MACOS_X86_64: Platform = .{ .triple = "x86_64-macos", .output = "" };
const MACOS_ARM64: Platform = .{ .triple = "aarch64-macos", .output = "" };
const MACOS_OUTPUT: []const u8 = "bin/libopenshooter_native.macos.dylib";

pub fn build(b: *Builder) void {
    const optimize: builtin.Optimize = .fast;
    const match_c: bool = b.option(bool, "match_c", "Reproduce the old C module output exactly") orelse false;

    // Build-time options visible to the code as @import("options").
    const options: *Builder.Step.Options = b.addOptions();
    options.addOption(bool, "match_c", match_c);

    const translate_c: *Builder.Dependency = b.dependency("translate_c", .{});

    // --- One step per platform ------------------------------------------------
    const linux_step: *Builder.Step = b.step("linux", "Build the Linux x86_64 library");
    const windows_step: *Builder.Step = b.step("windows", "Build the Windows x86_64 library");
    const macos_step: *Builder.Step = b.step("macos", "Build the universal macOS library");
    const android_step: *Builder.Step = b.step("android", "Build the Android arm64 + armv7 libraries");
    const freebsd_step: *Builder.Step = b.step("freebsd", "Build the FreeBSD x86_64 library");
    const all_step: *Builder.Step = b.step("all", "Build every library");

    installPlatform(b, linux_step, translate_c, options, optimize, LINUX);
    installPlatform(b, windows_step, translate_c, options, optimize, WINDOWS);
    installPlatform(b, freebsd_step, translate_c, options, optimize, FREEBSD);
    installPlatform(b, android_step, translate_c, options, optimize, ANDROID_ARM64);
    installPlatform(b, android_step, translate_c, options, optimize, ANDROID_ARM32);
    installMacosUniversal(b, macos_step, translate_c, options, optimize);

    for ([_]*Builder.Step{ linux_step, windows_step, macos_step, android_step, freebsd_step }) |platform_step| {
        all_step.dependOn(platform_step);
    }

    // --- `zig build` (no step): the library for this machine, in zig-out/ ------
    const host_target: Builder.ResolvedTarget = b.standardTargetOptions(.{});
    const host_library: *Builder.Step.Compile = addLibrary(b, translate_c, options, host_target, optimize, false);
    b.installArtifact(host_library);

    // --- `zig build test` ------------------------------------------------------
    const test_step: *Builder.Step = b.step("test", "Run the mesher unit tests");
    const test_module: *Builder.Module = addRootModule(b, translate_c, options, host_target, .debug);
    const tests: *Builder.Step.Compile = b.addTest(.{ .root_module = test_module });
    const run_tests: *Builder.Step.Run = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);
}

/// The module rooted at src/main.zig, with `c` (translated Godot header) and
/// `options` available to @import.
fn addRootModule(
    b: *Builder,
    translate_c: *Builder.Dependency,
    options: *Builder.Step.Options,
    target: Builder.ResolvedTarget,
    optimize: builtin.Optimize,
) *Builder.Module {
    const translator: Translator = .init(translate_c, .{
        .c_source_file = b.path(C_HEADER),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
        .link_system_libs = &.{},
    });

    const native_mod: *Builder.Module = b.createModule(.{
        .root_source_file = b.path(ROOT_SOURCE),
        .target = target,
        .optimize = optimize,
        .code_model = .default,
        .link_libc = false,
        .strip = optimize != .debug,
        .imports = &.{
            .{ .name = "c", .module = translator.mod },
            .{ .name = "options", .module = options.createModule() },
        },
    });
    return native_mod;
}

/// The shared library for `target`.
fn addLibrary(
    b: *Builder,
    translate_c: *Builder.Dependency,
    options: *Builder.Step.Options,
    target: Builder.ResolvedTarget,
    optimize: builtin.Optimize,
    page_size_16k: bool,
) *Builder.Step.Compile {
    const native_lib: *Builder.Step.Compile = b.addLibrary(.{
        .linkage = .dynamic,
        .name = LIBRARY_NAME,
        .root_module = addRootModule(b, translate_c, options, target, optimize),
    });
    if (page_size_16k) {
        native_lib.link_z_max_page_size = 16 * 1024;
    }
    return native_lib;
}

fn resolve(b: *Builder, platform: Platform) Builder.ResolvedTarget {
    const query: std.Target.Query = std.Target.Query.parse(.{
        .arch_os_abi = platform.triple,
        .cpu_features = platform.cpu,
    }) catch @panic("invalid target in build.zig");
    return b.resolveTargetQuery(query);
}

/// Builds `platform` and copies the library to native/bin/ when `step` runs.
fn installPlatform(
    b: *Builder,
    step: *Builder.Step,
    translate_c: *Builder.Dependency,
    options: *Builder.Step.Options,
    optimize: builtin.Optimize,
    platform: Platform,
) void {
    const native_lib: *Builder.Step.Compile = addLibrary(b, translate_c, options, resolve(b, platform), optimize, platform.page_size_16k);
    const copy: *Builder.Step.UpdateSourceFiles = b.addUpdateSourceFiles();
    copy.addCopyFileToSource(native_lib.getEmittedBin(), platform.output);
    step.dependOn(&copy.step);
}

/// Builds both macOS architectures and merges them into one universal
/// library with lipo.py (Python, so no Apple tools are needed).
fn installMacosUniversal(
    b: *Builder,
    step: *Builder.Step,
    translate_c: *Builder.Dependency,
    options: *Builder.Step.Options,
    optimize: builtin.Optimize,
) void {
    const intel: *Builder.Step.Compile = addLibrary(b, translate_c, options, resolve(b, MACOS_X86_64), optimize, false);
    const apple: *Builder.Step.Compile = addLibrary(b, translate_c, options, resolve(b, MACOS_ARM64), optimize, false);

    // python3 lipo.py <output> <x86_64 dylib> <arm64 dylib>
    const lipo: *Builder.Step.Run = b.addSystemCommand(&.{"python3"});
    lipo.addFileArg(b.path("lipo.py"));
    const universal: Builder.LazyPath = lipo.addOutputFileArg("libopenshooter_native.macos.dylib");
    lipo.addFileArg(intel.getEmittedBin());
    lipo.addFileArg(apple.getEmittedBin());

    const copy: *Builder.Step.UpdateSourceFiles = b.addUpdateSourceFiles();
    copy.addCopyFileToSource(universal, MACOS_OUTPUT);
    step.dependOn(&copy.step);
}
