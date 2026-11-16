#include "native_ops.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#define FLOATS_PER_BLOCK 24
#define PI_F 3.14159265358979323846f
#define TAU_F 6.28318530717958647692f

typedef struct {
	int key_x;
	int key_z;
	int huge;
	int detail;
	Vector3 origin;
	Vector3 *verts;
	Vector3 *norms;
	Color *cols;
	Vector2 *uv2;
	int32_t *idx;
	Vector3 *col;
	int vcount;
	int vcap;
	int icount;
	int icap;
	int ccount;
	int ccap;
} Chunk;

typedef struct {
	Chunk *items;
	int count;
	int cap;
} ChunkList;

typedef struct {
	GDExtensionObjectPtr object;
} NativeOps;

static int class_registered = 0;

#define GRID_CELL 8.0f
#define GRID_MIN -96.0f
#define GRID_DIM 24
#define GRID_CELLS (GRID_DIM * GRID_DIM * GRID_DIM)
#define GRID_EPS 0.02f
#ifndef CULL_FACES
#define CULL_FACES 1
#endif

typedef struct {
	float mn[3];
	float mx[3];
	int collide;
	int detail;
	int valid;
} BoxInfo;

typedef struct {
	BoxInfo *boxes;
	int count;
	int *next;
	int *head;
	int *large;
	int large_count;
	int large_cap;
} BoxGrid;

static int cell_index(int x, int y, int z)
{
	if (x < 0) x = 0;
	if (y < 0) y = 0;
	if (z < 0) z = 0;
	if (x >= GRID_DIM) x = GRID_DIM - 1;
	if (y >= GRID_DIM) y = GRID_DIM - 1;
	if (z >= GRID_DIM) z = GRID_DIM - 1;
	return (z * GRID_DIM + y) * GRID_DIM + x;
}

static int block_box(const float *f, BoxInfo *out)
{
	float b[9];
	memcpy(b, f, sizeof(b));
	for (int i = 0; i < 9; i++) {
		float a = fabsf(b[i]);
		if (a > 0.01f && fabsf(a - 1.0f) > 0.01f)
			return 0;
	}
	float hx = f[12] * 0.5f;
	float hy = f[13] * 0.5f;
	float hz = f[14] * 0.5f;
	float ex = fabsf(b[0]) * hx + fabsf(b[3]) * hy + fabsf(b[6]) * hz;
	float ey = fabsf(b[1]) * hx + fabsf(b[4]) * hy + fabsf(b[7]) * hz;
	float ez = fabsf(b[2]) * hx + fabsf(b[5]) * hy + fabsf(b[8]) * hz;
	out->mn[0] = f[9] - ex;
	out->mn[1] = f[10] - ey;
	out->mn[2] = f[11] - ez;
	out->mx[0] = f[9] + ex;
	out->mx[1] = f[10] + ey;
	out->mx[2] = f[11] + ez;
	out->collide = f[22] != 0.0f;
	out->detail = ((int)f[23] & 1) != 0;
	out->valid = 1;
	return 1;
}

static void grid_add_large(BoxGrid *g, int idx)
{
	if (g->large_count >= g->large_cap) {
		int cap = g->large_cap == 0 ? 16 : g->large_cap * 2;
		int *p = (int *)realloc(g->large, (size_t)cap * sizeof(int));
		if (!p)
			return;
		g->large = p;
		g->large_cap = cap;
	}
	g->large[g->large_count++] = idx;
}

static void grid_build(BoxGrid *g)
{
	for (int i = 0; i < GRID_CELLS; i++)
		g->head[i] = -1;
	for (int i = 0; i < g->count; i++) {
		g->next[i] = -1;
		BoxInfo *b = &g->boxes[i];
		if (!b->valid)
			continue;
		float sx = b->mx[0] - b->mn[0];
		float sy = b->mx[1] - b->mn[1];
		float sz = b->mx[2] - b->mn[2];
		if (sx > 30.0f || sy > 30.0f || sz > 30.0f) {
			grid_add_large(g, i);
			continue;
		}
		int x0 = (int)floorf((b->mn[0] - GRID_MIN) / GRID_CELL);
		int y0 = (int)floorf((b->mn[1] - GRID_MIN) / GRID_CELL);
		int z0 = (int)floorf((b->mn[2] - GRID_MIN) / GRID_CELL);
		int x1 = (int)floorf((b->mx[0] - GRID_MIN) / GRID_CELL);
		int y1 = (int)floorf((b->mx[1] - GRID_MIN) / GRID_CELL);
		int z1 = (int)floorf((b->mx[2] - GRID_MIN) / GRID_CELL);
		x0 = x0 < 0 ? 0 : x0; y0 = y0 < 0 ? 0 : y0; z0 = z0 < 0 ? 0 : z0;
		x1 = x1 >= GRID_DIM ? GRID_DIM - 1 : x1;
		y1 = y1 >= GRID_DIM ? GRID_DIM - 1 : y1;
		z1 = z1 >= GRID_DIM ? GRID_DIM - 1 : z1;
		if ((x1 - x0 + 1) * (y1 - y0 + 1) * (z1 - z0 + 1) > 512) {
			grid_add_large(g, i);
			continue;
		}
		for (int z = z0; z <= z1; z++) {
			for (int y = y0; y <= y1; y++) {
				for (int x = x0; x <= x1; x++) {
					int cell = cell_index(x, y, z);
					g->next[i] = g->head[cell];
					g->head[cell] = i;
				}
			}
		}
	}
}

static void grid_free(BoxGrid *g)
{
	free(g->boxes);
	free(g->next);
	free(g->head);
	free(g->large);
	memset(g, 0, sizeof(*g));
}

static int box_covers(const BoxInfo *b, int self, int idx, int axis,
		float plane, int t0, int t1, float fmin0, float fmax0, float fmin1, float fmax1)
{
	(void)self;
	if (!b->valid || idx < 0)
		return 0;
	if (b->mn[axis] > plane + GRID_EPS || b->mx[axis] < plane - GRID_EPS)
		return 0;
	if (b->mn[t0] > fmin0 + GRID_EPS || b->mx[t0] < fmax0 - GRID_EPS)
		return 0;
	if (b->mn[t1] > fmin1 + GRID_EPS || b->mx[t1] < fmax1 - GRID_EPS)
		return 0;
	return 1;
}

static int face_coverage(const BoxGrid *g, int self, int axis, int sign,
		const float *mn, const float *mx)
{
	if (!g || !g->boxes || self < 0)
		return 0;
	const BoxInfo *own = &g->boxes[self];
	if (!own->valid)
		return 0;
	int t0 = axis == 0 ? 1 : 0;
	int t1 = axis == 2 ? 1 : 2;
	float plane = sign > 0 ? own->mx[axis] : own->mn[axis];
	float fmin0 = mn[t0], fmax0 = mx[t0];
	float fmin1 = mn[t1], fmax1 = mx[t1];

	int ranges[3][2];
	int c = (int)floorf((plane - GRID_MIN) / GRID_CELL);
	c = c < 0 ? 0 : (c >= GRID_DIM ? GRID_DIM - 1 : c);
	ranges[axis][0] = c;
	ranges[axis][1] = c;
	ranges[t0][0] = (int)floorf((fmin0 - GRID_MIN) / GRID_CELL);
	ranges[t0][1] = (int)floorf((fmax0 - GRID_MIN) / GRID_CELL);
	ranges[t1][0] = (int)floorf((fmin1 - GRID_MIN) / GRID_CELL);
	ranges[t1][1] = (int)floorf((fmax1 - GRID_MIN) / GRID_CELL);
	for (int a = 0; a < 3; a++) {
		if (ranges[a][0] < 0) ranges[a][0] = 0;
		if (ranges[a][0] >= GRID_DIM) ranges[a][0] = GRID_DIM - 1;
		if (ranges[a][1] < 0) ranges[a][1] = 0;
		if (ranges[a][1] >= GRID_DIM) ranges[a][1] = GRID_DIM - 1;
	}

	int covered = 0;
	for (int z = ranges[2][0]; z <= ranges[2][1] && covered != 3; z++) {
		for (int y = ranges[1][0]; y <= ranges[1][1] && covered != 3; y++) {
			for (int x = ranges[0][0]; x <= ranges[0][1] && covered != 3; x++) {
				int cell = cell_index(x, y, z);
				for (int idx = g->head[cell]; idx >= 0; idx = g->next[idx]) {
					if (idx == self)
						continue;
					if (box_covers(&g->boxes[idx], self, idx, axis, plane, t0, t1,
							fmin0, fmax0, fmin1, fmax1)) {
						if (!g->boxes[idx].detail) covered |= 1;
						if (g->boxes[idx].collide) covered |= 2;
					}
				}
			}
		}
	}
	for (int i = 0; i < g->large_count && covered != 3; i++) {
		int idx = g->large[i];
		if (idx == self)
			continue;
		if (box_covers(&g->boxes[idx], self, idx, axis, plane, t0, t1,
				fmin0, fmax0, fmin1, fmax1)) {
			if (!g->boxes[idx].detail) covered |= 1;
			if (g->boxes[idx].collide) covered |= 2;
		}
	}
	return covered;
}

/* ------------------------------------------------------------------------- */
/* Dynamic mesh arrays                                                       */
/* ------------------------------------------------------------------------- */

static int grow_vertex(Chunk *c)
{
	if (c->vcount < c->vcap)
		return 1;
	int cap = c->vcap == 0 ? 1024 : c->vcap * 2;
	Vector3 *v = (Vector3 *)realloc(c->verts, (size_t)cap * sizeof(Vector3));
	if (!v) return 0;
	c->verts = v;
	Vector3 *n = (Vector3 *)realloc(c->norms, (size_t)cap * sizeof(Vector3));
	if (!n) return 0;
	c->norms = n;
	Color *col = (Color *)realloc(c->cols, (size_t)cap * sizeof(Color));
	if (!col) return 0;
	c->cols = col;
	Vector2 *uv = (Vector2 *)realloc(c->uv2, (size_t)cap * sizeof(Vector2));
	if (!uv) return 0;
	c->uv2 = uv;
	c->vcap = cap;
	return 1;
}

static int grow_collision(Chunk *c)
{
	if (c->ccount + 3 <= c->ccap)
		return 1;
	int cap = c->ccap == 0 ? 3072 : c->ccap * 2;
	Vector3 *p = (Vector3 *)realloc(c->col, (size_t)cap * sizeof(Vector3));
	if (!p) return 0;
	c->col = p;
	c->ccap = cap;
	return 1;
}

static int grow_index(Chunk *c)
{
	if (c->icount < c->icap)
		return 1;
	int cap = c->icap == 0 ? 3072 : c->icap * 2;
	int32_t *p = (int32_t *)realloc(c->idx, (size_t)cap * sizeof(int32_t));
	if (!p) return 0;
	c->idx = p;
	c->icap = cap;
	return 1;
}

static void add_vertex(Chunk *c, Vector3 p, Vector3 n, Color col, Vector2 uv)
{
	if (!grow_vertex(c)) return;
	c->verts[c->vcount] = p;
	c->norms[c->vcount] = n;
	c->cols[c->vcount] = col;
	c->uv2[c->vcount] = uv;
	c->vcount++;
}

static void add_index(Chunk *c, int32_t index)
{
	if (!grow_index(c)) return;
	c->idx[c->icount++] = index;
}

static void add_collision_tri(Chunk *c, Vector3 a, Vector3 b, Vector3 d)
{
	float ux = b.x - a.x, uy = b.y - a.y, uz = b.z - a.z;
	float vx = d.x - a.x, vy = d.y - a.y, vz = d.z - a.z;
	float cx = uy * vz - uz * vy;
	float cy = uz * vx - ux * vz;
	float cz = ux * vy - uy * vx;
	if (cx * cx + cy * cy + cz * cz < 1e-10f) return;
	if (!grow_collision(c)) return;
	c->col[c->ccount++] = a;
	c->col[c->ccount++] = b;
	c->col[c->ccount++] = d;
}

static void chunk_free(Chunk *c)
{
	free(c->verts);
	free(c->norms);
	free(c->cols);
	free(c->uv2);
	free(c->idx);
	free(c->col);
	memset(c, 0, sizeof(*c));
}

static Chunk *find_chunk(ChunkList *list, int kx, int kz, int huge, int detail, Vector3 origin)
{
	for (int i = 0; i < list->count; i++) {
		Chunk *c = &list->items[i];
		if (c->key_x == kx && c->key_z == kz && c->huge == huge && c->detail == detail)
			return c;
	}
	if (list->count >= list->cap) {
		int cap = list->cap == 0 ? 32 : list->cap * 2;
		Chunk *items = (Chunk *)realloc(list->items, (size_t)cap * sizeof(Chunk));
		if (!items) return NULL;
		list->items = items;
		list->cap = cap;
	}
	Chunk *c = &list->items[list->count++];
	memset(c, 0, sizeof(*c));
	c->key_x = kx;
	c->key_z = kz;
	c->huge = huge;
	c->detail = detail;
	c->origin = origin;
	return c;
}

/* ------------------------------------------------------------------------- */
/* Geometry                                                                  */
/* ------------------------------------------------------------------------- */

static Vector3 xf_point(const float *b, Vector3 o, Vector3 co, float px, float py, float pz)
{
	Vector3 r;
	r.x = o.x + b[0] * px + b[3] * py + b[6] * pz - co.x;
	r.y = o.y + b[1] * px + b[4] * py + b[7] * pz - co.y;
	r.z = o.z + b[2] * px + b[5] * py + b[8] * pz - co.z;
	return r;
}

static Vector3 xf_normal(const float *b, float nx, float ny, float nz)
{
	float x = b[0] * nx + b[3] * ny + b[6] * nz;
	float y = b[1] * nx + b[4] * ny + b[7] * nz;
	float z = b[2] * nx + b[5] * ny + b[8] * nz;
	float len = sqrtf(x * x + y * y + z * z);
	if (len <= 0.00001f) {
		Vector3 up = { 0, 1, 0 };
		return up;
	}
	Vector3 r = { x / len, y / len, z / len };
	return r;
}

static Vector3 add_vec(Vector3 p, Vector3 co)
{
	Vector3 r = { p.x + co.x, p.y + co.y, p.z + co.z };
	return r;
}

static const int FACE_AXIS[6] = { 2, 2, 0, 0, 1, 1 };
static const int FACE_SIGN[6] = { 1, -1, 1, -1, 1, -1 };

static const float FACE_N[6][3] = {
	{ 0, 0, 1 }, { 0, 0, -1 },
	{ 1, 0, 0 }, { -1, 0, 0 },
	{ 0, 1, 0 }, { 0, -1, 0 },
};

/* Clockwise when seen from outside, matching Godot's front-face winding. */
static const float FACE_CORNERS[6][4][3] = {
	{ { -1, 1, 1 }, { 1, 1, 1 }, { -1, -1, 1 }, { 1, -1, 1 } },       /* +Z */
	{ { 1, 1, -1 }, { -1, 1, -1 }, { 1, -1, -1 }, { -1, -1, -1 } },   /* -Z */
	{ { 1, 1, 1 }, { 1, 1, -1 }, { 1, -1, 1 }, { 1, -1, -1 } },       /* +X */
	{ { -1, 1, -1 }, { -1, 1, 1 }, { -1, -1, -1 }, { -1, -1, 1 } },   /* -X */
	{ { 1, 1, 1 }, { -1, 1, 1 }, { 1, 1, -1 }, { -1, 1, -1 } },       /* +Y */
	{ { -1, -1, 1 }, { 1, -1, 1 }, { -1, -1, -1 }, { 1, -1, -1 } },   /* -Y */
};

static void add_box(Chunk *c, const float *basis, Vector3 o, Vector3 co, Vector3 size,
		Color col, Vector2 attrs, int collide, const BoxGrid *grid, int self)
{
	float hx = size.x * 0.5f;
	float hy = size.y * 0.5f;
	float hz = size.z * 0.5f;
	int axis_aligned = CULL_FACES && grid != NULL && grid->boxes != NULL && self >= 0 && grid->boxes[self].valid;
	const BoxInfo *bi = axis_aligned ? &grid->boxes[self] : NULL;

	for (int f = 0; f < 6; f++) {
		int axis = FACE_AXIS[f];
		int sign = FACE_SIGN[f];
		int coverage = 0;
		if (axis_aligned)
			coverage = face_coverage(grid, self, axis, sign, bi->mn, bi->mx);
		int skip_render = (coverage & 1) != 0;
		int skip_collision = (coverage & 2) != 0;
		if (axis_aligned && axis == 1 && sign < 0 && bi->mn[1] <= 0.05f)
			skip_render = skip_collision = 1;
		if (skip_render && (!collide || skip_collision))
			continue;

		Vector3 world[4];
		int base = c->vcount;
		for (int k = 0; k < 4; k++) {
			const float *corner = FACE_CORNERS[f][k];
			Vector3 p = xf_point(basis, o, co, corner[0] * hx, corner[1] * hy, corner[2] * hz);
			world[k] = add_vec(p, co);
			if (!skip_render) {
				Vector3 n = xf_normal(basis, FACE_N[f][0], FACE_N[f][1], FACE_N[f][2]);
				add_vertex(c, p, n, col, attrs);
			}
		}
		if (!skip_render) {
			add_index(c, base);
			add_index(c, base + 1);
			add_index(c, base + 2);
			add_index(c, base + 1);
			add_index(c, base + 3);
			add_index(c, base + 2);
		}
		if (collide && !skip_collision) {
			add_collision_tri(c, world[0], world[1], world[2]);
			add_collision_tri(c, world[1], world[3], world[2]);
		}
	}
}

static void add_cylinder(Chunk *c, const float *basis, Vector3 o, Vector3 co, Vector3 size,
		Color col, Vector2 attrs, int collide)
{
	const int seg = 12;
	float r = size.x * 0.5f;
	float hy = size.y * 0.5f;
	Vector3 up = { 0, 1, 0 };
	Vector3 down = { 0, -1, 0 };
	int base_side = c->vcount;
	for (int s = 0; s < seg; s++) {
		float a0 = (float)s / (float)seg * TAU_F;
		float a1 = (float)(s + 1) / (float)seg * TAU_F;
		float s0 = sinf(a0), c0 = cosf(a0);
		float s1 = sinf(a1), c1 = cosf(a1);
		Vector3 p0 = xf_point(basis, o, co, s0 * r, hy, c0 * r);
		Vector3 p1 = xf_point(basis, o, co, s1 * r, hy, c1 * r);
		Vector3 p2 = xf_point(basis, o, co, s1 * r, -hy, c1 * r);
		Vector3 p3 = xf_point(basis, o, co, s0 * r, -hy, c0 * r);
		Vector3 n0 = xf_normal(basis, s0, 0, c0);
		Vector3 n1 = xf_normal(basis, s1, 0, c1);
		int b = c->vcount;
		add_vertex(c, p0, n0, col, attrs);
		add_vertex(c, p1, n1, col, attrs);
		add_vertex(c, p2, n1, col, attrs);
		add_vertex(c, p3, n0, col, attrs);
		add_index(c, b); add_index(c, b + 1); add_index(c, b + 2);
		add_index(c, b); add_index(c, b + 2); add_index(c, b + 3);
		if (collide) {
			add_collision_tri(c, add_vec(p0, co), add_vec(p1, co), add_vec(p2, co));
			add_collision_tri(c, add_vec(p0, co), add_vec(p2, co), add_vec(p3, co));
		}
	}
	(void)base_side;

	int top_center = c->vcount;
	add_vertex(c, xf_point(basis, o, co, 0, hy, 0), xf_normal(basis, up.x, up.y, up.z), col, attrs);
	int top_rim = c->vcount;
	for (int s = 0; s < seg; s++) {
		float a = (float)s / (float)seg * TAU_F;
		add_vertex(c, xf_point(basis, o, co, sinf(a) * r, hy, cosf(a) * r), xf_normal(basis, 0, 1, 0), col, attrs);
	}
	for (int s = 0; s < seg; s++) {
		int a = top_rim + s;
		int b = top_rim + (s + 1) % seg;
		add_index(c, top_center); add_index(c, b); add_index(c, a);
		if (collide) {
			Vector3 ca = add_vec(c->verts[top_center], co);
			Vector3 pa = add_vec(c->verts[a], co);
			Vector3 pb = add_vec(c->verts[b], co);
			add_collision_tri(c, ca, pb, pa);
		}
	}

	int bot_center = c->vcount;
	add_vertex(c, xf_point(basis, o, co, 0, -hy, 0), xf_normal(basis, down.x, down.y, down.z), col, attrs);
	int bot_rim = c->vcount;
	for (int s = 0; s < seg; s++) {
		float a = (float)s / (float)seg * TAU_F;
		add_vertex(c, xf_point(basis, o, co, sinf(a) * r, -hy, cosf(a) * r), xf_normal(basis, 0, -1, 0), col, attrs);
	}
	for (int s = 0; s < seg; s++) {
		int a = bot_rim + s;
		int b = bot_rim + (s + 1) % seg;
		add_index(c, bot_center); add_index(c, a); add_index(c, b);
		if (collide) {
			Vector3 ca = add_vec(c->verts[bot_center], co);
			Vector3 pa = add_vec(c->verts[a], co);
			Vector3 pb = add_vec(c->verts[b], co);
			add_collision_tri(c, ca, pa, pb);
		}
	}
}

static void add_sphere(Chunk *c, const float *basis, Vector3 o, Vector3 co, Vector3 size,
		Color col, Vector2 attrs, int collide)
{
	const int seg = 12;
	const int rings = 6;
	float radius = size.x * 0.5f;
	float half_h = size.y * 0.5f;
	for (int r = 0; r < rings; r++) {
		float phi0 = (float)r / (float)rings * PI_F;
		float phi1 = (float)(r + 1) / (float)rings * PI_F;
		float y0 = cosf(phi0) * half_h;
		float y1 = cosf(phi1) * half_h;
		float rad0 = sinf(phi0) * radius;
		float rad1 = sinf(phi1) * radius;
		for (int s = 0; s < seg; s++) {
			float a0 = (float)s / (float)seg * TAU_F;
			float a1 = (float)(s + 1) / (float)seg * TAU_F;
			float sa0 = sinf(a0), ca0 = cosf(a0);
			float sa1 = sinf(a1), ca1 = cosf(a1);
			Vector3 p00 = xf_point(basis, o, co, sa0 * rad0, y0, ca0 * rad0);
			Vector3 p01 = xf_point(basis, o, co, sa1 * rad0, y0, ca1 * rad0);
			Vector3 p10 = xf_point(basis, o, co, sa0 * rad1, y1, ca0 * rad1);
			Vector3 p11 = xf_point(basis, o, co, sa1 * rad1, y1, ca1 * rad1);
			Vector3 n00 = xf_normal(basis, sa0 * sinf(phi0), cosf(phi0), ca0 * sinf(phi0));
			Vector3 n01 = xf_normal(basis, sa1 * sinf(phi0), cosf(phi0), ca1 * sinf(phi0));
			Vector3 n10 = xf_normal(basis, sa0 * sinf(phi1), cosf(phi1), ca0 * sinf(phi1));
			Vector3 n11 = xf_normal(basis, sa1 * sinf(phi1), cosf(phi1), ca1 * sinf(phi1));
			int b = c->vcount;
			add_vertex(c, p00, n00, col, attrs);
			add_vertex(c, p01, n01, col, attrs);
			add_vertex(c, p11, n11, col, attrs);
			add_vertex(c, p10, n10, col, attrs);
			if (r != 0) {
				add_index(c, b); add_index(c, b + 1); add_index(c, b + 2);
				add_index(c, b); add_index(c, b + 2); add_index(c, b + 3);
				if (collide) {
					add_collision_tri(c, add_vec(p00, co), add_vec(p01, co), add_vec(p11, co));
					add_collision_tri(c, add_vec(p00, co), add_vec(p11, co), add_vec(p10, co));
				}
			}
			if (r != rings - 1) {
				add_index(c, b + 1); add_index(c, b + 2); add_index(c, b + 3);
				if (collide)
					add_collision_tri(c, add_vec(p01, co), add_vec(p11, co), add_vec(p10, co));
			}
		}
	}
}

/* ------------------------------------------------------------------------- */
/* Mesher                                                                    */
/* ------------------------------------------------------------------------- */

static ChunkList bake_geometry(PackedFloat32Array *data, int block_count, float cell)
{
	ChunkList list = { 0 };
	if (block_count <= 0)
		return list;
	const float *values = api.packed_float32_array_operator_index(data, 0);
	if (!values)
		return list;

	BoxGrid grid = { 0 };
	grid.count = block_count;
	grid.boxes = (BoxInfo *)calloc((size_t)block_count, sizeof(BoxInfo));
	grid.next = (int *)malloc((size_t)block_count * sizeof(int));
	grid.head = (int *)malloc((size_t)GRID_CELLS * sizeof(int));
	if (grid.boxes && grid.next && grid.head) {
		for (int block = 0; block < block_count; block++) {
			const float *f = values + block * FLOATS_PER_BLOCK;
			if ((int)f[21] == 0)
				block_box(f, &grid.boxes[block]);
		}
		grid_build(&grid);
	} else {
		free(grid.boxes);
		free(grid.next);
		free(grid.head);
		memset(&grid, 0, sizeof(grid));
	}

	for (int block = 0; block < block_count; block++) {
		const float *f = values + block * FLOATS_PER_BLOCK;
		float basis[9];
		memcpy(basis, f, sizeof(basis));
		Vector3 origin = { f[9], f[10], f[11] };
		Vector3 size = { f[12], f[13], f[14] };
		Color col = { f[15], f[16], f[17], f[19] };
		float metallic = f[18];
		float emission = f[20];
		int shape = (int)f[21];
		int collide = f[22] != 0.0f;
		int flags = (int)f[23];
		int detail = (flags & 1) != 0;
		int huge = (flags & 2) != 0;

		int kx = 0, kz = 0;
		Vector3 co = { 0, 0, 0 };
		if (!huge) {
			kx = (int)floorf(origin.x / cell);
			kz = (int)floorf(origin.z / cell);
			co.x = ((float)kx + 0.5f) * cell;
			co.y = 0;
			co.z = ((float)kz + 0.5f) * cell;
		}
		Chunk *c = find_chunk(&list, kx, kz, huge, huge ? 0 : detail, co);
		if (!c)
			continue;
		Vector2 attrs = { metallic, emission };
		if (shape == 0)
			add_box(c, basis, origin, co, size, col, attrs, collide, &grid, block);
		else if (shape == 1)
			add_cylinder(c, basis, origin, co, size, col, attrs, collide);
		else
			add_sphere(c, basis, origin, co, size, col, attrs, collide);
	}
	grid_free(&grid);
	return list;
}

/* ------------------------------------------------------------------------- */
/* Godot value helpers                                                       */
/* ------------------------------------------------------------------------- */

static void dict_set_packed(Dictionary *dict, const char *key, GDExtensionVariantType type,
		GDExtensionVariantFromTypeConstructorFunc from, void *value)
{
	(void)type;
	String s;
	make_string(&s, key);
	Variant kv;
	constructors.from_string(&kv, &s);
	destroy_string(&s);
	Variant *slot = api.dictionary_operator_index(dict, &kv);
	api.variant_destroy(&kv);
	if (slot)
		from(slot, value);
}

static void dict_set_vector3(Dictionary *dict, const char *key, Vector3 value)
{
	String s;
	make_string(&s, key);
	Variant kv;
	constructors.from_string(&kv, &s);
	destroy_string(&s);
	Variant *slot = api.dictionary_operator_index(dict, &kv);
	api.variant_destroy(&kv);
	if (slot)
		constructors.from_vector3(slot, &value);
}

static void dict_set_bool(Dictionary *dict, const char *key, int value)
{
	String s;
	make_string(&s, key);
	Variant kv;
	constructors.from_string(&kv, &s);
	destroy_string(&s);
	Variant *slot = api.dictionary_operator_index(dict, &kv);
	api.variant_destroy(&kv);
	if (slot) {
		uint8_t b = value ? 1 : 0;
		constructors.from_bool(slot, &b);
	}
}

static Array chunks_to_array(ChunkList *list)
{
	Array out;
	api.variant_get_ptr_constructor(GDEXTENSION_VARIANT_TYPE_ARRAY, 0)(&out, NULL);
	int valid = 0;
	for (int i = 0; i < list->count; i++) {
		if (list->items[i].vcount > 0)
			valid++;
	}
	int64_t count = valid;
	GDExtensionConstTypePtr args[1] = { &count };
	int64_t resize_result = 0;
	methods.array_resize(&out, args, &resize_result, 1);

	int slot_index = 0;
	for (int i = 0; i < list->count; i++) {
		Chunk *c = &list->items[i];
		if (c->vcount == 0)
			continue;

		PackedVector3Array pv3;
		PackedVector3Array pn3;
		PackedColorArray pcol;
		PackedVector2Array puv2;
		PackedInt32Array pidx;
		PackedVector3Array pfaces;
		api.variant_get_ptr_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, 0)(&pv3, NULL);
		api.variant_get_ptr_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, 0)(&pn3, NULL);
		api.variant_get_ptr_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, 0)(&pcol, NULL);
		api.variant_get_ptr_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY, 0)(&puv2, NULL);
		api.variant_get_ptr_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, 0)(&pidx, NULL);
		api.variant_get_ptr_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, 0)(&pfaces, NULL);

		int64_t nv = c->vcount;
		int64_t ni = c->icount;
		int64_t nc = c->ccount;
		int64_t rr = 0;
		GDExtensionConstTypePtr a1[1] = { &nv };
		GDExtensionConstTypePtr a2[1] = { &ni };
		GDExtensionConstTypePtr a3[1] = { &nc };
		methods.packed_vector3_resize(&pv3, a1, &rr, 1);
		methods.packed_vector3_resize(&pn3, a1, &rr, 1);
		methods.packed_color_resize(&pcol, a1, &rr, 1);
		methods.packed_vector2_resize(&puv2, a1, &rr, 1);
		methods.packed_int32_resize(&pidx, a2, &rr, 1);
		methods.packed_vector3_resize(&pfaces, a3, &rr, 1);

		Vector3 *dv = (Vector3 *)api.packed_vector3_array_operator_index(&pv3, 0);
		Vector3 *dn = (Vector3 *)api.packed_vector3_array_operator_index(&pn3, 0);
		Color *dc = (Color *)api.packed_color_array_operator_index(&pcol, 0);
		Vector2 *du = (Vector2 *)api.packed_vector2_array_operator_index(&puv2, 0);
		int32_t *di = (int32_t *)api.packed_int32_array_operator_index(&pidx, 0);
		Vector3 *dcol = (Vector3 *)api.packed_vector3_array_operator_index(&pfaces, 0);
		for (int k = 0; k < c->vcount; k++) {
			dv[k] = c->verts[k];
			dn[k] = c->norms[k];
			dc[k] = c->cols[k];
			du[k] = c->uv2[k];
		}
		for (int k = 0; k < c->icount; k++)
			di[k] = c->idx[k];
		for (int k = 0; k < c->ccount; k++)
			dcol[k] = c->col[k];

		Dictionary dict;
		api.variant_get_ptr_constructor(GDEXTENSION_VARIANT_TYPE_DICTIONARY, 0)(&dict, NULL);
		dict_set_vector3(&dict, "origin", c->origin);
		dict_set_bool(&dict, "huge", c->huge);
		dict_set_bool(&dict, "detail", c->detail);
		dict_set_packed(&dict, "vertices", GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, constructors.from_packed_vector3, &pv3);
		dict_set_packed(&dict, "normals", GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, constructors.from_packed_vector3, &pn3);
		dict_set_packed(&dict, "colors", GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, constructors.from_packed_color, &pcol);
		dict_set_packed(&dict, "uv2", GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY, constructors.from_packed_vector2, &puv2);
		dict_set_packed(&dict, "indices", GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, constructors.from_packed_int32, &pidx);
		dict_set_packed(&dict, "collision", GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, constructors.from_packed_vector3, &pfaces);

		Variant *slot = api.array_operator_index(&out, slot_index++);
		if (slot)
			constructors.from_dictionary(slot, &dict);

		destructors.dictionary(&dict);
		destructors.packed_vector3(&pv3);
		destructors.packed_vector3(&pn3);
		destructors.packed_color(&pcol);
		destructors.packed_vector2(&puv2);
		destructors.packed_int32(&pidx);
		destructors.packed_vector3(&pfaces);
	}
	return out;
}

/* ------------------------------------------------------------------------- */
/* Method callbacks                                                          */
/* ------------------------------------------------------------------------- */

static void call_ping(void *userdata, GDExtensionClassInstancePtr instance,
		const GDExtensionConstVariantPtr *args, GDExtensionInt argc,
		GDExtensionVariantPtr ret, GDExtensionCallError *err)
{
	(void)userdata;
	(void)instance;
	(void)args;
	if (argc != 0) {
		err->error = GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
		err->expected = 0;
		return;
	}
	String s;
	make_string(&s, "pong-c");
	constructors.from_string(ret, &s);
	destroy_string(&s);
}

static void call_bake_map(void *userdata, GDExtensionClassInstancePtr instance,
		const GDExtensionConstVariantPtr *args, GDExtensionInt argc,
		GDExtensionVariantPtr ret, GDExtensionCallError *err)
{
	(void)userdata;
	(void)instance;
	if (argc != 3) {
		err->error = argc < 3 ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS : GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
		err->expected = 3;
		return;
	}
	if (api.variant_get_type(args[0]) != GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY ||
			api.variant_get_type(args[1]) != GDEXTENSION_VARIANT_TYPE_INT ||
			api.variant_get_type(args[2]) != GDEXTENSION_VARIANT_TYPE_FLOAT) {
		err->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
		err->argument = 0;
		return;
	}

	PackedFloat32Array data;
	constructors.to_packed_float32(&data, (GDExtensionVariantPtr)args[0]);
	int64_t block_count = 0;
	double cell = 64.0;
	constructors.to_int(&block_count, (GDExtensionVariantPtr)args[1]);
	constructors.to_float(&cell, (GDExtensionVariantPtr)args[2]);

	ChunkList chunks = bake_geometry(&data, (int)block_count, (float)cell);
	Array out = chunks_to_array(&chunks);
	constructors.from_array(ret, &out);

	destructors.array(&out);
	for (int i = 0; i < chunks.count; i++)
		chunk_free(&chunks.items[i]);
	free(chunks.items);
	destructors.packed_float32(&data);
}

/* ------------------------------------------------------------------------- */
/* Class registration                                                        */
/* ------------------------------------------------------------------------- */

static GDExtensionObjectPtr create_instance(void *class_userdata, GDExtensionBool notify_postinitialize)
{
	(void)class_userdata;
	(void)notify_postinitialize;
	StringName parent;
	make_string_name(&parent, "RefCounted");
	GDExtensionObjectPtr object = api.classdb_construct_object3(&parent);
	destroy_string_name(&parent);
	if (!object)
		return NULL;

	NativeOps *self = (NativeOps *)api.mem_alloc(sizeof(NativeOps));
	if (!self)
		return object;
	self->object = object;

	StringName class_name;
	make_string_name(&class_name, "NativeOps");
	api.object_set_instance(object, &class_name, self);
	destroy_string_name(&class_name);
	return object;
}

static void free_instance(void *class_userdata, GDExtensionClassInstancePtr instance)
{
	(void)class_userdata;
	if (instance)
		api.mem_free(instance);
}

static void bind_method(const char *name, GDExtensionClassMethodCall call,
		int has_return, GDExtensionVariantType return_type,
		int arg_count, const GDExtensionVariantType *arg_types, const char **arg_names)
{
	StringName method_name;
	make_string_name(&method_name, name);

	OwnedProperty ret;
	if (has_return)
		property_init(&ret, return_type, "");

	OwnedProperty args[4];
	GDExtensionPropertyInfo infos[4];
	GDExtensionClassMethodArgumentMetadata meta[4];
	for (int i = 0; i < arg_count; i++) {
		property_init(&args[i], arg_types[i], arg_names[i]);
		infos[i] = args[i].info;
		meta[i] = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
	}

	GDExtensionClassMethodInfo info;
	memset(&info, 0, sizeof(info));
	info.name = &method_name;
	info.call_func = call;
	info.ptrcall_func = NULL;
	info.method_flags = GDEXTENSION_METHOD_FLAGS_DEFAULT;
	info.has_return_value = has_return ? 1 : 0;
	info.return_value_info = has_return ? &ret.info : NULL;
	info.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
	info.argument_count = (uint32_t)arg_count;
	info.arguments_info = arg_count > 0 ? infos : NULL;
	info.arguments_metadata = arg_count > 0 ? meta : NULL;

	StringName class_name;
	make_string_name(&class_name, "NativeOps");
	api.classdb_register_extension_class_method(class_library, &class_name, &info);
	destroy_string_name(&class_name);

	for (int i = 0; i < arg_count; i++)
		property_deinit(&args[i]);
	if (has_return)
		property_deinit(&ret);
	destroy_string_name(&method_name);
}

void native_ops_register(void)
{
	if (class_registered)
		return;
	class_registered = 1;

	StringName class_name;
	StringName parent_name;
	make_string_name(&class_name, "NativeOps");
	make_string_name(&parent_name, "RefCounted");

	GDExtensionClassCreationInfo6 info;
	memset(&info, 0, sizeof(info));
	info.is_virtual = 0;
	info.is_abstract = 0;
	info.is_exposed = 1;
	info.is_runtime = 0;
	info.icon_path = NULL;
	info.create_instance_func = create_instance;
	info.free_instance_func = free_instance;

	api.classdb_register_extension_class6(class_library, &class_name, &parent_name, &info);

	bind_method("ping", call_ping, 1, GDEXTENSION_VARIANT_TYPE_STRING, 0, NULL, NULL);

	const GDExtensionVariantType bake_args[3] = {
		GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY,
		GDEXTENSION_VARIANT_TYPE_INT,
		GDEXTENSION_VARIANT_TYPE_FLOAT,
	};
	const char *bake_names[3] = { "data", "count", "cell" };
	bind_method("bake_map", call_bake_map, 1, GDEXTENSION_VARIANT_TYPE_ARRAY, 3, bake_args, bake_names);

	destroy_string_name(&parent_name);
	destroy_string_name(&class_name);
}

void native_ops_unregister(void)
{
	if (!class_registered)
		return;
	class_registered = 0;
	StringName class_name;
	make_string_name(&class_name, "NativeOps");
	api.classdb_unregister_extension_class(class_library, &class_name);
	destroy_string_name(&class_name);
}
