#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "gdextension_interface.h"

#if !defined(GDE_EXPORT)
#if defined(_WIN32)
#define GDE_EXPORT __declspec(dllexport)
#elif defined(__GNUC__)
#define GDE_EXPORT __attribute__((visibility("default")))
#else
#define GDE_EXPORT
#endif
#endif

/* Opaque Godot values. Sizes come from extension_api.json (64-bit, float_64 build). */
typedef struct { _Alignas(8) uint8_t data[8]; } String;
typedef struct { _Alignas(8) uint8_t data[8]; } StringName;
typedef struct { _Alignas(8) uint8_t data[8]; } Array;
typedef struct { _Alignas(8) uint8_t data[8]; } Dictionary;
typedef struct { _Alignas(8) uint8_t data[16]; } PackedVector3Array;
typedef struct { _Alignas(8) uint8_t data[16]; } PackedVector2Array;
typedef struct { _Alignas(8) uint8_t data[16]; } PackedColorArray;
typedef struct { _Alignas(8) uint8_t data[16]; } PackedInt32Array;
typedef struct { _Alignas(8) uint8_t data[16]; } PackedFloat32Array;
typedef struct { _Alignas(8) uint8_t data[24]; } Variant;

typedef struct { float x, y, z; } Vector3;
typedef struct { float x, y; } Vector2;
typedef struct { float r, g, b, a; } Color;

typedef enum {
	PROPERTY_HINT_NONE = 0,
	PROPERTY_USAGE_STORAGE = 2,
	PROPERTY_USAGE_EDITOR = 4,
	PROPERTY_USAGE_DEFAULT = PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR,
} PropertyUsageFlags;
