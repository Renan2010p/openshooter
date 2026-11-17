//! Map mesher.
//!
//! Merges the map's blocks (boxes, cylinders and spheres) into chunks of
//! `cell` meters. Every chunk gets ONE vertex stream (so ONE draw call in
//! Godot) plus a flat list of collision triangles.
//!
//! Box faces that are completely covered by a neighbouring box are dropped:
//!   - a face covered by an opaque (non-detail) box is not drawn;
//!   - a face covered by a colliding box gets no collision triangles.
//!
//! This file knows nothing about Godot: it only reads floats and fills plain
//! arrays, so it can be unit-tested with `zig build test`.
//!
//! INPUT LAYOUT — `FLOATS_PER_BLOCK` (24) floats per block:
//!
//!   index   meaning
//!   0..9    basis: x column (0,1,2), y column (3,4,5), z column (6,7,8)
//!   9..12   origin (x, y, z), in map coordinates
//!   12..15  size (x, y, z), in meters
//!   15..18  color (r, g, b)
//!   18      metallic
//!   19      roughness
//!   20      emission strength
//!   21      shape: 0 = box, 1 = cylinder, 2 = sphere
//!   22      collide: 0 = no, anything else = yes
//!   23      flags: bit 1 = detail block, bit 2 = huge block

const std: type = @import("std");
const options: type = @import("options");

const Allocator: type = std.mem.Allocator;

// ===========================================================================
// Public constants and types
// ===========================================================================

/// How many floats describe one block in the input array.
pub const FLOATS_PER_BLOCK: usize = 24;

/// When true, the mesher reproduces the old C module exactly (including its
/// two bugs, see `BoxGrid` and `Chunk.hasOutput`). Only used to verify the
/// port: `zig build -Dmatch_c=true`.
const MATCH_C: bool = options.match_c;

/// Same memory layout as Godot's `Vector3` (three f32).
pub const Vector3 = extern struct {
    x: f32,
    y: f32,
    z: f32,

    pub const ZERO: Vector3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 };
    pub const UP: Vector3 = .{ .x = 0.0, .y = 1.0, .z = 0.0 };

    pub fn add(a: Vector3, b: Vector3) Vector3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }

    pub fn sub(a: Vector3, b: Vector3) Vector3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }
};

/// Same memory layout as Godot's `Vector2` (two f32).
pub const Vector2 = extern struct {
    x: f32,
    y: f32,
};

/// Same memory layout as Godot's `Color` (four f32).
pub const Color = extern struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

/// One output mesh: every block inside one cell, or the global "huge" mesh.
///
/// - Vertex positions are relative to `origin` (the cell center).
/// - Collision triangles are in map coordinates (three points per triangle).
/// - `cols` keeps the block color, with ROUGHNESS stored in alpha.
/// - `uv2` keeps METALLIC in x and EMISSION strength in y.
pub const Chunk = struct {
    origin: Vector3,
    huge: bool,
    detail: bool,
    verts: std.ArrayList(Vector3) = .empty,
    norms: std.ArrayList(Vector3) = .empty,
    cols: std.ArrayList(Color) = .empty,
    uv2: std.ArrayList(Vector2) = .empty,
    idx: std.ArrayList(i32) = .empty,
    collision: std.ArrayList(Vector3) = .empty,

    /// Should this chunk be sent to Godot?
    ///
    /// The C module only sent chunks that had something to DRAW, so a chunk
    /// whose faces were all hidden lost its collision too. Now a chunk with
    /// only collision triangles is sent as well.
    pub fn hasOutput(self: *const Chunk) bool {
        if (MATCH_C) {
            return self.verts.items.len > 0;
        }
        return self.verts.items.len > 0 or self.collision.items.len > 0;
    }

    pub fn deinit(self: *Chunk, gpa: Allocator) void {
        self.verts.deinit(gpa);
        self.norms.deinit(gpa);
        self.cols.deinit(gpa);
        self.uv2.deinit(gpa);
        self.idx.deinit(gpa);
        self.collision.deinit(gpa);
    }

    /// Makes room for at least this many more vertices, indices and
    /// collision triangles. The `add*` functions below do NOT check capacity
    /// (that is what makes them fast), so every shape calls `reserve` first
    /// with its worst case. Debug builds (`zig build test`) assert it.
    fn reserve(self: *Chunk, gpa: Allocator, vertices: usize, indices: usize, triangles: usize) Allocator.Error!void {
        try self.verts.ensureUnusedCapacity(gpa, vertices);
        try self.norms.ensureUnusedCapacity(gpa, vertices);
        try self.cols.ensureUnusedCapacity(gpa, vertices);
        try self.uv2.ensureUnusedCapacity(gpa, vertices);
        try self.idx.ensureUnusedCapacity(gpa, indices);
        try self.collision.ensureUnusedCapacity(gpa, triangles * 3);
    }

    /// Appends one vertex (position, normal, color, material attributes).
    fn addVertex(self: *Chunk, position: Vector3, normal: Vector3, color: Color, attrs: Vector2) void {
        self.verts.appendAssumeCapacity(position);
        self.norms.appendAssumeCapacity(normal);
        self.cols.appendAssumeCapacity(color);
        self.uv2.appendAssumeCapacity(attrs);
    }

    /// Appends indices `base + offset` for every offset.
    fn addIndices(self: *Chunk, base: usize, offsets: []const usize) void {
        for (offsets) |offset| {
            const index: i32 = @intCast(base + offset);
            self.idx.appendAssumeCapacity(index);
        }
    }

    /// Appends one collision triangle, unless it has (almost) zero area.
    fn addCollisionTriangle(self: *Chunk, a: Vector3, b: Vector3, d: Vector3) void {
        const u: Vector3 = b.sub(a);
        const v: Vector3 = d.sub(a);
        // Cross product u × v; its length is twice the triangle area.
        const cx: f32 = u.y * v.z - u.z * v.y;
        const cy: f32 = u.z * v.x - u.x * v.z;
        const cz: f32 = u.x * v.y - u.y * v.x;
        const area_squared: f32 = cx * cx + cy * cy + cz * cz;
        if (area_squared < 1e-10) {
            return;
        }
        self.collision.appendAssumeCapacity(a);
        self.collision.appendAssumeCapacity(b);
        self.collision.appendAssumeCapacity(d);
    }
};

/// The result of `bake()`. Free it with `deinit()`.
pub const BakeResult = struct {
    chunks: std.ArrayList(Chunk) = .empty,

    pub fn deinit(self: *BakeResult, gpa: Allocator) void {
        for (self.chunks.items) |*chunk| {
            chunk.deinit(gpa);
        }
        self.chunks.deinit(gpa);
    }
};

// ===========================================================================
// One block, decoded from the flat input
// ===========================================================================

const Shape = enum { box, cylinder, sphere };

const Block = struct {
    /// Basis columns: x = basis[0..3], y = basis[3..6], z = basis[6..9].
    basis: [9]f32,
    origin: Vector3,
    size: Vector3,
    color: Color,
    attrs: Vector2,
    shape: Shape,
    collide: bool,
    detail: bool,
    huge: bool,

    /// Reads one block from its 24 floats.
    fn read(f: []const f32) Block {
        const flags: i32 = floatToInt(f[23]);
        const shape_number: i32 = floatToInt(f[21]);
        return .{
            .basis = f[0..9].*,
            .origin = .{ .x = f[9], .y = f[10], .z = f[11] },
            .size = .{ .x = f[12], .y = f[13], .z = f[14] },
            .color = .{ .r = f[15], .g = f[16], .b = f[17], .a = f[19] },
            .attrs = .{ .x = f[18], .y = f[20] },
            .shape = switch (shape_number) {
                0 => .box,
                1 => .cylinder,
                else => .sphere,
            },
            .collide = f[22] != 0.0,
            .detail = (flags & 1) != 0,
            .huge = (flags & 2) != 0,
        };
    }

    /// Local point (px, py, pz) -> position relative to the chunk origin `co`.
    fn point(self: *const Block, co: Vector3, px: f32, py: f32, pz: f32) Vector3 {
        const b: *const [9]f32 = &self.basis;
        const o: Vector3 = self.origin;
        return .{
            .x = o.x + b[0] * px + b[3] * py + b[6] * pz - co.x,
            .y = o.y + b[1] * px + b[4] * py + b[7] * pz - co.y,
            .z = o.z + b[2] * px + b[5] * py + b[8] * pz - co.z,
        };
    }

    /// Local normal (nx, ny, nz) -> normalized normal in map space.
    fn normal(self: *const Block, nx: f32, ny: f32, nz: f32) Vector3 {
        const b: *const [9]f32 = &self.basis;
        const x: f32 = b[0] * nx + b[3] * ny + b[6] * nz;
        const y: f32 = b[1] * nx + b[4] * ny + b[7] * nz;
        const z: f32 = b[2] * nx + b[5] * ny + b[8] * nz;
        const length: f32 = @sqrt(x * x + y * y + z * z);
        if (length <= 0.00001) {
            return Vector3.UP;
        }
        return .{ .x = x / length, .y = y / length, .z = z / length };
    }
};

/// Float -> integer the way C's `(int)value` does (truncate toward zero),
/// but clamped so a garbage value can never be undefined behaviour.
fn floatToInt(value: f32) i32 {
    if (!(value > -2.0e9 and value < 2.0e9)) { // also catches NaN
        return 0;
    }
    return @intFromFloat(value);
}

/// floor() then integer, clamped like `floatToInt`.
fn floorToInt(value: f32) i32 {
    return floatToInt(@floor(value));
}

// ===========================================================================
// Neighbour grid (hidden-face removal)
// ===========================================================================

/// The grid covers GRID_DIM³ cells of GRID_CELL meters, starting at GRID_MIN
/// on every axis (−96 m to +96 m). Boxes outside are clamped to edge cells.
const GRID_CELL: f32 = 8.0;
const GRID_MIN: f32 = -96.0;
const GRID_DIM: i32 = 24;
const GRID_CELLS: usize = @as(usize, @intCast(GRID_DIM * GRID_DIM * GRID_DIM));
/// Boxes bigger than this on any axis (or touching more than
/// GRID_LARGE_CELLS cells) are not put in cells: they live in a separate
/// "large" list that is checked for every face.
const GRID_LARGE_SIZE: f32 = 30.0;
const GRID_LARGE_CELLS: i32 = 512;
/// Tolerance when comparing face planes and extents (meters).
const GRID_EPS: f32 = 0.02;

/// Axis-aligned bounds of a box block whose basis is axis-aligned.
const BoxInfo = struct {
    min: [3]f32,
    max: [3]f32,
    collide: bool,
    detail: bool,
};

/// Bounds of a box block, or null when its basis is rotated (only 90° turns
/// and flips keep a box axis-aligned; anything else is not culled).
fn blockBox(f: []const f32) ?BoxInfo {
    for (f[0..9]) |value| {
        const a: f32 = @abs(value);
        const is_zero: bool = a <= 0.01;
        const is_one: bool = @abs(a - 1.0) <= 0.01;
        if (!is_zero and !is_one) {
            return null;
        }
    }
    const hx: f32 = f[12] * 0.5;
    const hy: f32 = f[13] * 0.5;
    const hz: f32 = f[14] * 0.5;
    // Half extents of the rotated box on each map axis.
    const ex: f32 = @abs(f[0]) * hx + @abs(f[3]) * hy + @abs(f[6]) * hz;
    const ey: f32 = @abs(f[1]) * hx + @abs(f[4]) * hy + @abs(f[7]) * hz;
    const ez: f32 = @abs(f[2]) * hx + @abs(f[5]) * hy + @abs(f[8]) * hz;
    return .{
        .min = .{ f[9] - ex, f[10] - ey, f[11] - ez },
        .max = .{ f[9] + ex, f[10] + ey, f[11] + ez },
        .collide = f[22] != 0.0,
        .detail = (floatToInt(f[23]) & 1) != 0,
    };
}

/// Map coordinate -> grid coordinate (NOT clamped).
fn gridCoord(value: f32) i32 {
    return floorToInt((value - GRID_MIN) / GRID_CELL);
}

fn clampCell(c: i32) i32 {
    return std.math.clamp(c, 0, GRID_DIM - 1);
}

fn cellIndex(x: i32, y: i32, z: i32) usize {
    const index: i32 = (clampCell(z) * GRID_DIM + clampCell(y)) * GRID_DIM + clampCell(x);
    return @intCast(index);
}

/// Inclusive cell range [x0, y0, z0, x1, y1, z1].
const CellRange = [6]i32;

/// Boxes bucketed by grid cell.
///
/// Storage: the boxes of cell `c` are `items[start[c]..start[c + 1]]`
/// (one flat array, built with a counting pass and a filling pass).
///
/// The old C module used a linked list with ONE `next` pointer per box, so a
/// box spanning several cells overwrote its own link and some neighbours
/// were never found: hidden faces were kept (drawn for nothing). With
/// `MATCH_C` the old lists are rebuilt here so the output can be compared.
const BoxGrid = struct {
    boxes: []?BoxInfo,
    start: []u32,
    items: []u32,
    large: std.ArrayList(u32) = .empty,

    fn init(gpa: Allocator, boxes: []?BoxInfo) Allocator.Error!BoxGrid {
        var grid: BoxGrid = .{
            .boxes = boxes,
            .start = try gpa.alloc(u32, GRID_CELLS + 1),
            .items = &.{},
        };
        errdefer gpa.free(grid.start);
        errdefer grid.large.deinit(gpa);

        // 1) Cell range of every gridded box; null = not in the grid.
        const ranges: []?CellRange = try gpa.alloc(?CellRange, boxes.len);
        defer gpa.free(ranges);
        const counts: []u32 = try gpa.alloc(u32, GRID_CELLS);
        defer gpa.free(counts);
        @memset(counts, 0);

        for (boxes, 0..) |maybe_box, i| {
            ranges[i] = null;
            const box: BoxInfo = maybe_box orelse continue;
            var too_big: bool = false;
            for (0..3) |axis| {
                if (box.max[axis] - box.min[axis] > GRID_LARGE_SIZE) {
                    too_big = true;
                }
            }
            const range: CellRange = .{
                @max(gridCoord(box.min[0]), 0),
                @max(gridCoord(box.min[1]), 0),
                @max(gridCoord(box.min[2]), 0),
                @min(gridCoord(box.max[0]), GRID_DIM - 1),
                @min(gridCoord(box.max[1]), GRID_DIM - 1),
                @min(gridCoord(box.max[2]), GRID_DIM - 1),
            };
            const span: i32 = (range[3] - range[0] + 1) * (range[4] - range[1] + 1) * (range[5] - range[2] + 1);
            if (too_big or span > GRID_LARGE_CELLS) {
                try grid.large.append(gpa, @intCast(i));
                continue;
            }
            ranges[i] = range;
            var cells: CellIterator = .init(range);
            while (cells.next()) |cell| {
                counts[cell] += 1;
            }
        }

        // 2) Prefix sums: start[c] = where cell c begins in `items`.
        grid.start[0] = 0;
        for (0..GRID_CELLS) |c| {
            grid.start[c + 1] = grid.start[c] + counts[c];
        }

        // 3) Fill. `counts` is reused as the write cursor of each cell.
        grid.items = try gpa.alloc(u32, grid.start[GRID_CELLS]);
        @memcpy(counts, grid.start[0..GRID_CELLS]);
        for (ranges, 0..) |maybe_range, i| {
            const range: CellRange = maybe_range orelse continue;
            var cells: CellIterator = .init(range);
            while (cells.next()) |cell| {
                grid.items[counts[cell]] = @intCast(i);
                counts[cell] += 1;
            }
        }

        if (MATCH_C) {
            try grid.rebuildLikeC(gpa, ranges);
        }
        return grid;
    }

    fn deinit(self: *BoxGrid, gpa: Allocator) void {
        gpa.free(self.start);
        gpa.free(self.items);
        self.large.deinit(gpa);
    }

    /// Replaces the cell lists with what the C linked list really contained.
    /// The C code did, for every cell of box i (in z, y, x order):
    ///     next[i] = head[cell]; head[cell] = i;
    /// and walked `head[cell]`, `next[...]` until -1.
    fn rebuildLikeC(self: *BoxGrid, gpa: Allocator, ranges: []const ?CellRange) Allocator.Error!void {
        const head: []i32 = try gpa.alloc(i32, GRID_CELLS);
        defer gpa.free(head);
        const next: []i32 = try gpa.alloc(i32, ranges.len);
        defer gpa.free(next);
        @memset(head, -1);
        @memset(next, -1);
        for (ranges, 0..) |maybe_range, i| {
            const range: CellRange = maybe_range orelse continue;
            var cells: CellIterator = .init(range);
            while (cells.next()) |cell| {
                next[i] = head[cell];
                head[cell] = @intCast(i);
            }
        }
        var lists: std.ArrayList(u32) = .empty;
        errdefer lists.deinit(gpa);
        for (0..GRID_CELLS) |c| {
            self.start[c] = @intCast(lists.items.len);
            var walk: i32 = head[c];
            while (walk >= 0) : (walk = next[@intCast(walk)]) {
                try lists.append(gpa, @intCast(walk));
            }
        }
        self.start[GRID_CELLS] = @intCast(lists.items.len);
        gpa.free(self.items);
        self.items = try lists.toOwnedSlice(gpa);
    }

    /// Which neighbours fully cover face (`axis`, `sign`) of box `me`?
    /// Returns bit 1 = covered by an opaque (non-detail) box,
    ///         bit 2 = covered by a colliding box.
    fn faceCoverage(self: *const BoxGrid, me: usize, own: BoxInfo, axis: usize, sign: i32) u8 {
        // One specialised copy per axis: inside it `axis`, `t0` and `t1` are
        // compile-time constants, so `min[axis]` is a fixed offset instead of
        // an index computed for every neighbour.
        return switch (axis) {
            inline 0, 1, 2 => |constant_axis| self.faceCoverageOnAxis(constant_axis, me, own, sign),
            else => unreachable,
        };
    }

    fn faceCoverageOnAxis(self: *const BoxGrid, comptime axis: usize, me: usize, own: BoxInfo, sign: i32) u8 {
        // The two axes that lie in the face plane.
        const t0: usize = comptime if (axis == 0) 1 else 0;
        const t1: usize = comptime if (axis == 2) 1 else 2;
        const plane: f32 = if (sign > 0) own.max[axis] else own.min[axis];

        // A neighbour covers the face when it touches the face plane and
        // spans the whole face on t0 and t1 (all within GRID_EPS). These are
        // the limits it must reach, computed once per face.
        const limits: FaceLimits = .{
            .plane_high = plane + GRID_EPS,
            .plane_low = plane - GRID_EPS,
            .t0_min = own.min[t0] + GRID_EPS,
            .t0_max = own.max[t0] - GRID_EPS,
            .t1_min = own.min[t1] + GRID_EPS,
            .t1_max = own.max[t1] - GRID_EPS,
        };

        // Cells to search: one layer on `axis`, the face's extent on t0/t1.
        var low: [3]i32 = undefined;
        var high: [3]i32 = undefined;
        low[axis] = clampCell(gridCoord(plane));
        high[axis] = low[axis];
        low[t0] = clampCell(gridCoord(own.min[t0]));
        high[t0] = clampCell(gridCoord(own.max[t0]));
        low[t1] = clampCell(gridCoord(own.min[t1]));
        high[t1] = clampCell(gridCoord(own.max[t1]));

        var covered: u8 = 0;
        var z: i32 = low[2];
        cells: while (z <= high[2]) : (z += 1) {
            var y: i32 = low[1];
            while (y <= high[1]) : (y += 1) {
                var x: i32 = low[0];
                while (x <= high[0]) : (x += 1) {
                    const cell: usize = cellIndex(x, y, z);
                    for (self.items[self.start[cell]..self.start[cell + 1]]) |other| {
                        covered |= self.coverageBits(axis, me, other, &limits);
                    }
                    if (covered == 3) {
                        break :cells;
                    }
                }
            }
        }
        for (self.large.items) |other| {
            if (covered == 3) {
                break;
            }
            covered |= self.coverageBits(axis, me, other, &limits);
        }
        return covered;
    }

    /// See `faceCoverageOnAxis`.
    const FaceLimits = struct {
        plane_high: f32,
        plane_low: f32,
        t0_min: f32,
        t0_max: f32,
        t1_min: f32,
        t1_max: f32,
    };

    /// Coverage bits that box `other` gives to the face (0 if it does not
    /// touch the face plane or does not span the whole face).
    /// Inlined: this is the innermost loop of the whole mesher.
    inline fn coverageBits(self: *const BoxGrid, comptime axis: usize, me: usize, other: u32, limits: *const FaceLimits) u8 {
        const t0: usize = comptime if (axis == 0) 1 else 0;
        const t1: usize = comptime if (axis == 2) 1 else 2;
        if (other == me) {
            return 0;
        }
        // Only valid (axis-aligned) boxes are ever put in the cell lists and
        // in `large`, so the optional is always set here.
        const o: *const BoxInfo = &(self.boxes[other].?);
        const covers: bool = o.min[axis] <= limits.plane_high and o.max[axis] >= limits.plane_low and
            o.min[t0] <= limits.t0_min and o.max[t0] >= limits.t0_max and
            o.min[t1] <= limits.t1_min and o.max[t1] >= limits.t1_max;
        if (!covers) {
            return 0;
        }
        var bits: u8 = 0;
        if (!o.detail) bits |= 1;
        if (o.collide) bits |= 2;
        return bits;
    }
};

/// Walks every cell index in a CellRange, z outermost, x innermost.
const CellIterator = struct {
    range: CellRange,
    x: i32,
    y: i32,
    z: i32,

    fn init(range: CellRange) CellIterator {
        return .{ .range = range, .x = range[0], .y = range[1], .z = range[2] };
    }

    fn next(self: *CellIterator) ?usize {
        if (self.z > self.range[5] or self.range[0] > self.range[3] or self.range[1] > self.range[4]) {
            return null;
        }
        const cell: usize = cellIndex(self.x, self.y, self.z);
        self.x += 1;
        if (self.x > self.range[3]) {
            self.x = self.range[0];
            self.y += 1;
            if (self.y > self.range[4]) {
                self.y = self.range[1];
                self.z += 1;
            }
        }
        return cell;
    }
};

// ===========================================================================
// Shapes
// ===========================================================================

/// For each of the 6 box faces: the axis it faces and the direction.
const FACE_AXIS: [6]usize = .{ 2, 2, 0, 0, 1, 1 };
const FACE_SIGN: [6]i32 = .{ 1, -1, 1, -1, 1, -1 };
const FACE_NORMAL: [6][3]f32 = .{
    .{ 0, 0, 1 }, .{ 0, 0, -1 }, // +Z, -Z
    .{ 1, 0, 0 }, .{ -1, 0, 0 }, // +X, -X
    .{ 0, 1, 0 }, .{ 0, -1, 0 }, // +Y, -Y
};
/// Corners of each face (unit box), clockwise when seen from outside,
/// matching Godot's front-face winding.
const FACE_CORNERS: [6][4][3]f32 = .{
    .{ .{ -1, 1, 1 }, .{ 1, 1, 1 }, .{ -1, -1, 1 }, .{ 1, -1, 1 } }, // +Z
    .{ .{ 1, 1, -1 }, .{ -1, 1, -1 }, .{ 1, -1, -1 }, .{ -1, -1, -1 } }, // -Z
    .{ .{ 1, 1, 1 }, .{ 1, 1, -1 }, .{ 1, -1, 1 }, .{ 1, -1, -1 } }, // +X
    .{ .{ -1, 1, -1 }, .{ -1, 1, 1 }, .{ -1, -1, -1 }, .{ -1, -1, 1 } }, // -X
    .{ .{ 1, 1, 1 }, .{ -1, 1, 1 }, .{ 1, 1, -1 }, .{ -1, 1, -1 } }, // +Y
    .{ .{ -1, -1, 1 }, .{ 1, -1, 1 }, .{ -1, -1, -1 }, .{ 1, -1, -1 } }, // -Y
};
/// Two triangles per face: corners (0, 1, 2) and (1, 3, 2).
const FACE_TRIANGLES: [6]usize = .{ 0, 1, 2, 1, 3, 2 };

fn addBox(gpa: Allocator, chunk: *Chunk, block: *const Block, co: Vector3, grid: *const BoxGrid, me: usize) Allocator.Error!void {
    const hx: f32 = block.size.x * 0.5;
    const hy: f32 = block.size.y * 0.5;
    const hz: f32 = block.size.z * 0.5;
    const own: ?BoxInfo = grid.boxes[me];

    for (0..6) |f| {
        const axis: usize = FACE_AXIS[f];
        const sign: i32 = FACE_SIGN[f];

        // Is this face hidden (for drawing) / buried (for collision)?
        var skip_render: bool = false;
        var skip_collision: bool = false;
        if (own) |box| {
            const coverage: u8 = grid.faceCoverage(me, box, axis, sign);
            skip_render = (coverage & 1) != 0;
            skip_collision = (coverage & 2) != 0;
            // A bottom face resting on the ground is never seen or touched.
            const is_bottom: bool = axis == 1 and sign < 0;
            if (is_bottom and box.min[1] <= 0.05) {
                skip_render = true;
                skip_collision = true;
            }
        }
        if (skip_render and (!block.collide or skip_collision)) {
            continue;
        }

        // One face: 4 vertices, 6 indices, 2 collision triangles.
        try chunk.reserve(gpa, 4, 6, 2);
        const base: usize = chunk.verts.items.len;
        const n: Vector3 = block.normal(FACE_NORMAL[f][0], FACE_NORMAL[f][1], FACE_NORMAL[f][2]);
        var world: [4]Vector3 = undefined;
        for (FACE_CORNERS[f], 0..) |corner, k| {
            const p: Vector3 = block.point(co, corner[0] * hx, corner[1] * hy, corner[2] * hz);
            world[k] = p.add(co);
            if (!skip_render) {
                chunk.addVertex(p, n, block.color, block.attrs);
            }
        }
        if (!skip_render) {
            chunk.addIndices(base, &FACE_TRIANGLES);
        }
        if (block.collide and !skip_collision) {
            chunk.addCollisionTriangle(world[0], world[1], world[2]);
            chunk.addCollisionTriangle(world[1], world[3], world[2]);
        }
    }
}

const CYLINDER_SEGMENTS: usize = 12;
const SPHERE_SEGMENTS: usize = 12;
const SPHERE_RINGS: usize = 6;

/// sin and cos of angle `s / segments` of a full turn.
fn ringAngle(s: usize, segments: usize) struct { sin: f32, cos: f32 } {
    const angle: f32 = @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(segments)) * std.math.tau;
    return .{ .sin = @sin(angle), .cos = @cos(angle) };
}

fn addCylinder(gpa: Allocator, chunk: *Chunk, block: *const Block, co: Vector3) Allocator.Error!void {
    const segments: usize = CYLINDER_SEGMENTS;
    const r: f32 = block.size.x * 0.5;
    const hy: f32 = block.size.y * 0.5;
    const color: Color = block.color;
    const attrs: Vector2 = block.attrs;

    // Side: 4 vertices, 6 indices, 2 triangles per segment.
    // Each cap: 1 + segments vertices, 3 indices and 1 triangle per segment.
    try chunk.reserve(gpa, segments * 4 + 2 * (1 + segments), segments * 6 + 2 * segments * 3, segments * 2 + 2 * segments);

    // Side: one quad (4 vertices, 2 triangles) per segment.
    for (0..segments) |s| {
        const a0 = ringAngle(s, segments);
        const a1 = ringAngle(s + 1, segments);
        const p0: Vector3 = block.point(co, a0.sin * r, hy, a0.cos * r);
        const p1: Vector3 = block.point(co, a1.sin * r, hy, a1.cos * r);
        const p2: Vector3 = block.point(co, a1.sin * r, -hy, a1.cos * r);
        const p3: Vector3 = block.point(co, a0.sin * r, -hy, a0.cos * r);
        const n0: Vector3 = block.normal(a0.sin, 0.0, a0.cos);
        const n1: Vector3 = block.normal(a1.sin, 0.0, a1.cos);
        const base: usize = chunk.verts.items.len;
        chunk.addVertex(p0, n0, color, attrs);
        chunk.addVertex(p1, n1, color, attrs);
        chunk.addVertex(p2, n1, color, attrs);
        chunk.addVertex(p3, n0, color, attrs);
        chunk.addIndices(base, &.{ 0, 1, 2, 0, 2, 3 });
        if (block.collide) {
            chunk.addCollisionTriangle(p0.add(co), p1.add(co), p2.add(co));
            chunk.addCollisionTriangle(p0.add(co), p2.add(co), p3.add(co));
        }
    }

    // Caps: a center vertex plus a rim. The top cap faces up, the bottom
    // cap faces down, so their triangles are wound in opposite directions.
    const caps: [2]struct { y: f32, ny: f32 } = .{ .{ .y = hy, .ny = 1.0 }, .{ .y = -hy, .ny = -1.0 } };
    for (caps) |cap| {
        const n: Vector3 = block.normal(0.0, cap.ny, 0.0);
        const center: usize = chunk.verts.items.len;
        chunk.addVertex(block.point(co, 0.0, cap.y, 0.0), n, color, attrs);
        const rim: usize = chunk.verts.items.len;
        for (0..segments) |s| {
            const a = ringAngle(s, segments);
            chunk.addVertex(block.point(co, a.sin * r, cap.y, a.cos * r), n, color, attrs);
        }
        for (0..segments) |s| {
            const a: usize = rim + s;
            const b: usize = rim + (s + 1) % segments;
            const first: usize = if (cap.ny > 0.0) b else a;
            const second: usize = if (cap.ny > 0.0) a else b;
            chunk.idx.appendAssumeCapacity(@intCast(center));
            chunk.idx.appendAssumeCapacity(@intCast(first));
            chunk.idx.appendAssumeCapacity(@intCast(second));
            if (block.collide) {
                const v: []const Vector3 = chunk.verts.items;
                chunk.addCollisionTriangle(v[center].add(co), v[first].add(co), v[second].add(co));
            }
        }
    }
}

fn addSphere(gpa: Allocator, chunk: *Chunk, block: *const Block, co: Vector3) Allocator.Error!void {
    const segments: usize = SPHERE_SEGMENTS;
    const rings: usize = SPHERE_RINGS;
    const radius: f32 = block.size.x * 0.5;
    const half_height: f32 = block.size.y * 0.5;
    const color: Color = block.color;
    const attrs: Vector2 = block.attrs;

    // Worst case per quad: 4 vertices, 9 indices, 3 triangles.
    try chunk.reserve(gpa, rings * segments * 4, rings * segments * 9, rings * segments * 3);

    for (0..rings) |r| {
        // phi goes from the top pole (0) to the bottom pole (pi).
        const phi0: f32 = @as(f32, @floatFromInt(r)) / @as(f32, @floatFromInt(rings)) * std.math.pi;
        const phi1: f32 = @as(f32, @floatFromInt(r + 1)) / @as(f32, @floatFromInt(rings)) * std.math.pi;
        const sin0: f32 = @sin(phi0);
        const cos0: f32 = @cos(phi0);
        const sin1: f32 = @sin(phi1);
        const cos1: f32 = @cos(phi1);
        const y0: f32 = cos0 * half_height;
        const y1: f32 = cos1 * half_height;
        const rad0: f32 = sin0 * radius;
        const rad1: f32 = sin1 * radius;
        for (0..segments) |s| {
            const a0 = ringAngle(s, segments);
            const a1 = ringAngle(s + 1, segments);
            const p00: Vector3 = block.point(co, a0.sin * rad0, y0, a0.cos * rad0);
            const p01: Vector3 = block.point(co, a1.sin * rad0, y0, a1.cos * rad0);
            const p10: Vector3 = block.point(co, a0.sin * rad1, y1, a0.cos * rad1);
            const p11: Vector3 = block.point(co, a1.sin * rad1, y1, a1.cos * rad1);
            const base: usize = chunk.verts.items.len;
            chunk.addVertex(p00, block.normal(a0.sin * sin0, cos0, a0.cos * sin0), color, attrs);
            chunk.addVertex(p01, block.normal(a1.sin * sin0, cos0, a1.cos * sin0), color, attrs);
            chunk.addVertex(p11, block.normal(a1.sin * sin1, cos1, a1.cos * sin1), color, attrs);
            chunk.addVertex(p10, block.normal(a0.sin * sin1, cos1, a0.cos * sin1), color, attrs);
            // The top ring is a fan of triangles meeting at the pole: skip
            // the degenerate half of the quad there (and at the bottom).
            if (r != 0) {
                chunk.addIndices(base, &.{ 0, 1, 2, 0, 2, 3 });
                if (block.collide) {
                    chunk.addCollisionTriangle(p00.add(co), p01.add(co), p11.add(co));
                    chunk.addCollisionTriangle(p00.add(co), p11.add(co), p10.add(co));
                }
            }
            if (r != rings - 1) {
                chunk.addIndices(base, &.{ 1, 2, 3 });
                if (block.collide) {
                    chunk.addCollisionTriangle(p01.add(co), p11.add(co), p10.add(co));
                }
            }
        }
    }
}

// ===========================================================================
// Entry point
// ===========================================================================

/// Identifies one output chunk.
const ChunkKey = struct {
    cell_x: i32,
    cell_z: i32,
    huge: bool,
    detail: bool,
};

/// Bakes `count` blocks from `data` into chunks of `cell` meters.
/// Blocks past the end of `data` are ignored. Free the result with
/// `result.deinit(gpa)`.
pub fn bake(gpa: Allocator, data: []const f32, count: usize, cell: f32) Allocator.Error!BakeResult {
    var result: BakeResult = .{};
    errdefer result.deinit(gpa);

    const block_count: usize = @min(count, data.len / FLOATS_PER_BLOCK);
    if (block_count == 0 or !(cell > 0.0)) {
        return result;
    }
    const blocks: []const f32 = data[0 .. block_count * FLOATS_PER_BLOCK];

    // 1) Bounds of every axis-aligned box, for hidden-face removal.
    const boxes: []?BoxInfo = try gpa.alloc(?BoxInfo, block_count);
    defer gpa.free(boxes);
    for (0..block_count) |i| {
        const f: []const f32 = blocks[i * FLOATS_PER_BLOCK ..][0..FLOATS_PER_BLOCK];
        const is_box: bool = floatToInt(f[21]) == 0;
        boxes[i] = if (is_box) blockBox(f) else null;
    }
    var grid: BoxGrid = try .init(gpa, boxes);
    defer grid.deinit(gpa);

    // 2) Each block goes into the chunk of the cell holding its origin.
    //    Huge blocks (ground, boundary walls) share one global chunk.
    var lookup: std.AutoHashMapUnmanaged(ChunkKey, usize) = .empty;
    defer lookup.deinit(gpa);
    for (0..block_count) |i| {
        const block: Block = .read(blocks[i * FLOATS_PER_BLOCK ..][0..FLOATS_PER_BLOCK]);
        var key: ChunkKey = .{ .cell_x = 0, .cell_z = 0, .huge = block.huge, .detail = false };
        var chunk_origin: Vector3 = Vector3.ZERO;
        if (!block.huge) {
            key.cell_x = floorToInt(block.origin.x / cell);
            key.cell_z = floorToInt(block.origin.z / cell);
            key.detail = block.detail;
            chunk_origin = .{
                .x = (@as(f32, @floatFromInt(key.cell_x)) + 0.5) * cell,
                .y = 0.0,
                .z = (@as(f32, @floatFromInt(key.cell_z)) + 0.5) * cell,
            };
        }
        const entry = try lookup.getOrPut(gpa, key);
        if (!entry.found_existing) {
            entry.value_ptr.* = result.chunks.items.len;
            try result.chunks.append(gpa, .{ .origin = chunk_origin, .huge = key.huge, .detail = key.detail });
        }
        const chunk: *Chunk = &result.chunks.items[entry.value_ptr.*];
        switch (block.shape) {
            .box => try addBox(gpa, chunk, &block, chunk_origin, &grid, i),
            .cylinder => try addCylinder(gpa, chunk, &block, chunk_origin),
            .sphere => try addSphere(gpa, chunk, &block, chunk_origin),
        }
    }
    return result;
}

// ===========================================================================
// Tests (`zig build test`)
// ===========================================================================

const testing: type = std.testing;

/// One axis-aligned block, as 24 floats.
fn testBlock(position: [3]f32, size: [3]f32, shape: f32, collide: bool, flags: f32) [FLOATS_PER_BLOCK]f32 {
    return .{
        1, 0, 0, 0, 1, 0, 0, 0, 1, // identity basis
        position[0], position[1], position[2],
        size[0], size[1], size[2],
        0.5, 0.5, 0.5, // color
        0.0, 0.8, 0.0, // metallic, roughness, emission
        shape, if (collide) 1.0 else 0.0, flags,
    };
}

const Totals = struct { verts: usize, indices: usize, collision: usize };

fn totals(result: *const BakeResult) Totals {
    var t: Totals = .{ .verts = 0, .indices = 0, .collision = 0 };
    for (result.chunks.items) |*chunk| {
        t.verts += chunk.verts.items.len;
        t.indices += chunk.idx.items.len;
        t.collision += chunk.collision.items.len;
    }
    return t;
}

fn bakeBlocks(blocks: []const [FLOATS_PER_BLOCK]f32) !BakeResult {
    const flat: []const f32 = @as([*]const f32, @ptrCast(blocks.ptr))[0 .. blocks.len * FLOATS_PER_BLOCK];
    return bake(testing.allocator, flat, blocks.len, 24.0);
}

test "a floating box has six faces" {
    var result: BakeResult = try bakeBlocks(&.{testBlock(.{ 0, 5, 0 }, .{ 1, 1, 1 }, 0, true, 0)});
    defer result.deinit(testing.allocator);
    try testing.expectEqual(Totals{ .verts = 24, .indices = 36, .collision = 36 }, totals(&result));
}

test "a box on the ground loses its bottom face" {
    var result: BakeResult = try bakeBlocks(&.{testBlock(.{ 0, 0.5, 0 }, .{ 1, 1, 1 }, 0, true, 0)});
    defer result.deinit(testing.allocator);
    try testing.expectEqual(Totals{ .verts = 20, .indices = 30, .collision = 30 }, totals(&result));
}

test "touching boxes hide the faces they share" {
    var result: BakeResult = try bakeBlocks(&.{
        testBlock(.{ 0, 5, 0 }, .{ 1, 1, 1 }, 0, true, 0),
        testBlock(.{ 1, 5, 0 }, .{ 1, 1, 1 }, 0, true, 0),
    });
    defer result.deinit(testing.allocator);
    try testing.expectEqual(Totals{ .verts = 40, .indices = 60, .collision = 60 }, totals(&result));
}

test "a detail neighbour hides nothing; a non-colliding one keeps collision" {
    var result: BakeResult = try bakeBlocks(&.{
        testBlock(.{ 0, 5, 0 }, .{ 1, 1, 1 }, 0, true, 0),
        testBlock(.{ 1, 5, 0 }, .{ 1, 1, 1 }, 0, false, 1),
    });
    defer result.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 2), result.chunks.items.len);
    const main: *const Chunk = if (result.chunks.items[0].detail) &result.chunks.items[1] else &result.chunks.items[0];
    try testing.expectEqual(@as(usize, 24), main.verts.items.len);
    try testing.expectEqual(@as(usize, 36), main.collision.items.len);
}

test "a box spanning several grid cells still hides its neighbours" {
    // A 20 m wall (4 grid cells long) with a 1 m box against its middle:
    // the box must find the wall through the cell lists.
    var result: BakeResult = try bakeBlocks(&.{
        testBlock(.{ 0, 5, 0 }, .{ 20, 2, 1 }, 0, true, 0),
        testBlock(.{ 0, 5, 1 }, .{ 1, 1, 1 }, 0, true, 0),
    });
    defer result.deinit(testing.allocator);
    // The small box's -Z face touches the wall: 5 faces left.
    const small: *const Chunk = &result.chunks.items[0];
    try testing.expectEqual(@as(usize, 1), result.chunks.items.len);
    try testing.expectEqual(@as(usize, 24 + 20), small.verts.items.len);
}

test "cylinder and sphere vertex counts" {
    var cylinder: BakeResult = try bakeBlocks(&.{testBlock(.{ 0, 5, 0 }, .{ 1, 2, 1 }, 1, false, 0)});
    defer cylinder.deinit(testing.allocator);
    try testing.expectEqual(Totals{
        .verts = 12 * 4 + 2 * 13,
        .indices = 12 * 6 + 2 * 12 * 3,
        .collision = 0,
    }, totals(&cylinder));

    var sphere: BakeResult = try bakeBlocks(&.{testBlock(.{ 0, 5, 0 }, .{ 1, 1, 1 }, 2, false, 0)});
    defer sphere.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 6 * 12 * 4), totals(&sphere).verts);
}

test "blocks are split into cells, huge blocks into one global chunk" {
    var result: BakeResult = try bakeBlocks(&.{
        testBlock(.{ 1, 5, 1 }, .{ 1, 1, 1 }, 0, false, 0),
        testBlock(.{ 30, 5, 1 }, .{ 1, 1, 1 }, 0, false, 0),
        testBlock(.{ 0, -0.5, 0 }, .{ 100, 1, 100 }, 0, true, 2),
    });
    defer result.deinit(testing.allocator);
    const chunks: []const Chunk = result.chunks.items;
    try testing.expectEqual(@as(usize, 3), chunks.len);
    try testing.expectEqual(Vector3{ .x = 12, .y = 0, .z = 12 }, chunks[0].origin);
    try testing.expectEqual(Vector3{ .x = 36, .y = 0, .z = 12 }, chunks[1].origin);
    try testing.expect(chunks[2].huge);
    try testing.expectEqual(Vector3.ZERO, chunks[2].origin);
}

test "short or empty input is safe" {
    const ten: [10]f32 = @splat(1.0);
    var short: BakeResult = try bake(testing.allocator, &ten, 5, 24.0);
    defer short.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 0), short.chunks.items.len);

    var empty: BakeResult = try bake(testing.allocator, &.{}, 0, 24.0);
    defer empty.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 0), empty.chunks.items.len);
}

test "no leaks when memory runs out" {
    const blocks: [3][FLOATS_PER_BLOCK]f32 = .{
        testBlock(.{ 0, 5, 0 }, .{ 1, 1, 1 }, 0, true, 0),
        testBlock(.{ 0, 5, 0 }, .{ 1, 2, 1 }, 1, true, 0),
        testBlock(.{ 0, 5, 0 }, .{ 1, 1, 1 }, 2, true, 0),
    };
    const flat: []const f32 = @as([*]const f32, @ptrCast(&blocks))[0 .. 3 * FLOATS_PER_BLOCK];
    try testing.checkAllAllocationFailures(testing.allocator, struct {
        fn run(gpa: Allocator, input: []const f32) !void {
            var result: BakeResult = try bake(gpa, input, 3, 24.0);
            result.deinit(gpa);
        }
    }.run, .{flat});
}
