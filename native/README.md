# OpenShooter native module (C)

Optional GDExtension that bakes maps outside GDScript. The game runs without it;
`BlockBaker.native_available()` falls back to the pure GDScript mesher.

## What it does

- Receives the visible `Block` list as a flat `PackedFloat32Array` (24 floats per
  block: transform, size, color, metallic, roughness, emission, shape, flags).
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
  block is not emitted. Collision faces are removed only when covered by
  another colliding block. `CULL_FACES` (default 1) can disable this at compile
  time for debugging.

The class is `NativeOps` with `ping()` and `bake_map(data, count, cell)`.

## Build

The source is plain C11. The script uses `zig cc` as a cross-compiler, so no
Linux/Android toolchain needs to be installed on the host:

```sh
./build.sh linux     # bin/libopenshooter_native.so
./build.sh windows   # bin/openshooter_native.dll
./build.sh android   # bin/libopenshooter_native.android*.so (NDK 27+)
./build.sh freebsd   # bin/libopenshooter_native.freebsd.so
./build.sh all
```

For Android, set `ANDROID_NDK_HOME` or edit the default path in `build.sh`.
API level 24 matches the game's minimum.

## Files

- `src/gdextension_interface.h` — dumped from Godot 4.7.2
  (`godot --dump-gdextension-interface`).
- `src/api.c` / `api.h` — loads the GDExtension function table, makes strings
  and property info, caches builtin constructors/destructors.
- `src/native_ops.c` — class registration, geometry generation and the
  `bake_map` call.
- `src/init.c` — extension entry point.

## Notes

- C is compiled outside the Godot editor; rebuild and reload the project after
  changes.
- The extension is optional on every platform. `--no-native` disables it.
- `reloadable = false`: the class cannot be hot-reloaded safely.
