# OpenShooter native module (Zig)

Optional GDExtension that bakes maps outside GDScript. The game runs without it:
`BlockBaker.native_available()` falls back to the pure GDScript mesher.

## What it does

- Receives the visible `Block` list as a flat `PackedFloat32Array` (24 floats per
  block: transform, size, color, metallic, roughness, emission, shape, flags;
  the full layout is documented at the top of `src/mesher.zig`).
- Merges boxes, cylinders and spheres into chunks of `chunk_size` meters.
- Returns one dictionary per chunk with `vertices`, `normals`, `colors`, `uv2`,
  `indices`, `collision`, `origin`, `detail` and `huge`. `collision` is a flat
  triangle list in map coordinates; GDScript turns it into one
  `ConcavePolygonShape3D` per chunk instead of one box per block.
- GDScript wraps each chunk into a single-surface `ArrayMesh` with a shared
  shader (`resources/materials/map_surface.gdshader`). Material data travels per
  vertex, so a chunk costs one draw call instead of two or three.
- Roughness is stored in `COLOR.a`; metallic and emission strength in `UV2.x`
  and `UV2.y`.
- Detail blocks are split into their own chunk mesh, so they can disappear at
  the detail distance without adding extra surfaces to the main geometry.
- Hidden box faces are removed: a face fully covered by an opaque, non-detail
  block is not drawn. Collision faces are removed only when covered by another
  colliding block.

The class is `NativeOps` (a `RefCounted`) with `ping()` (returns `"pong-zig"`)
and `bake_map(data, count, cell)`.

A second class, `DiscordIpc`, carries **Discord Rich Presence**: it opens the
local channel of the Discord desktop app (a Unix socket on Linux/macOS/FreeBSD,
a named pipe on Windows) and sends/receives frames without ever blocking. The
JSON itself is built in `scripts/autoload/discord.gd`. Methods: `open(path)`,
`send(opcode, json)`, `receive()`, `last_opcode()`, `is_open()`, `close()`.

## Build

Needs [Zig](https://ziglang.org) **0.17.1**. Run inside `native/`:

```sh
zig build linux      # bin/libopenshooter_native.so
zig build windows    # bin/openshooter_native.dll
zig build macos      # bin/libopenshooter_native.macos.dylib (universal, merged by lipo.py)
zig build android    # bin/libopenshooter_native.android.so (arm64)
                     # bin/libopenshooter_native.android-arm32.so (armv7)
zig build freebsd    # bin/libopenshooter_native.freebsd.so
zig build all        # every library above
zig build test       # mesher unit tests
```

The libraries are built **without libc**: math comes from Zig, memory from
Godot's own allocator. That is why one machine builds every platform, Android
included, with no NDK or system compiler. (FreeBSD is the exception: Zig always
links FreeBSD's libc, which every FreeBSD system has.) The Android arm64 library
is aligned to 16 KB pages for Android 15+ devices.

`zig build -Dmatch_c=true` reproduces the old C module's output exactly (see
"History" below). It exists only to compare against it.

## Files

| File | Role |
|---|---|
| `build.zig` | One step per platform; copies each library into `bin/`. |
| `build.zig.zon` | Package manifest; depends on `translate_c`. |
| `src/c.h` | Input for `translate_c`, which turns the Godot C header into the Zig module `c`. |
| `src/gdextension_interface.h` | Godot's C interface, dumped from Godot 4.7.2 (`godot --dump-gdextension-interface`). Not our code; re-dump it when upgrading Godot. |
| `src/main.zig` | Entry point `openshooter_native_init`. |
| `src/godot.zig` | Loads the engine function table; opaque Godot values (String, Array, Dictionary, Variant, Packed arrays); Godot's allocator as a `std.mem.Allocator`. |
| `src/native_ops.zig` | Registers `NativeOps` and implements `ping()` / `bake_map()`. |
| `src/mesher.zig` | The geometry. Plain Zig with no Godot dependency, and unit tests. |
| `src/discord_ipc.zig` | Discord IPC transport per platform and the frame format, with unit tests. |
| `src/discord_class.zig` | Registers `DiscordIpc` for GDScript. |
| `lipo.py` | Joins the two macOS libraries into one universal file. |

## Testing

- `zig build test`: unit tests for the mesher (faces, culling, chunking,
  cylinders/spheres, bad input, no leaks when memory runs out).
- `godot --headless --path . -s res://tests/bake_bench.gd` (from the project
  root): times every map and prints a geometry checksum per map. Add
  `-- --no-native` to time the GDScript mesher, `--dump=FILE` to save the
  checksums for comparison.

## History

The module used to be written in C. The Zig port was verified against it:
with `-Dmatch_c=true`, all four maps produce byte-identical checksums. The
default build fixes two bugs of the C version:

1. **Neighbour grid:** the C grid used a linked list with one `next` pointer
   per box, so a box spanning several cells overwrote its own link and some
   neighbours were never checked. Hidden faces stayed in the mesh. The fix gives
   about 3% fewer vertices and 4–5% fewer collision triangles.
2. **Collision-only chunks:** a chunk whose faces were all hidden was dropped
   together with its collision. Now it is still sent.

Speed, bake_map on the four maps (Godot 4.7.2, same machine): Zig 30.2 ms vs
C 31.0 ms in Godot. The mesher alone, outside Godot: Zig 6.3–7.7 ms per map vs
C 8.2–9.7 ms.

## Notes

- The extension is compiled outside the Godot editor; rebuild and reload the
  project after changes.
- The extension is optional on every platform. `--no-native` disables it.
