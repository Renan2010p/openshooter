#include "api.h"

#include <string.h>

GDExtensionClassLibraryPtr class_library = NULL;

struct Api api;
struct Constructors constructors;
struct Destructors destructors;
struct Methods methods;

static GDExtensionPtrBuiltInMethod get_resize(GDExtensionVariantType type)
{
	StringName name;
	make_string_name(&name, "resize");
	GDExtensionPtrBuiltInMethod fn = api.variant_get_ptr_builtin_method(type, &name, 848867239);
	destroy_string_name(&name);
	return fn;
}

void make_string(String *out, const char *text)
{
	api.string_new_with_utf8_chars(out, text);
}

void make_string_name(StringName *out, const char *text)
{
	api.string_name_new_with_latin1_chars(out, text, false);
}

void destroy_string(String *value)
{
	destructors.string(value);
}

void destroy_string_name(StringName *value)
{
	destructors.string_name(value);
}

void property_init(OwnedProperty *prop, GDExtensionVariantType type, const char *name)
{
	memset(prop, 0, sizeof(*prop));
	make_string_name(&prop->name, name);
	make_string(&prop->hint, "");
	make_string_name(&prop->class_name, "");
	prop->info.type = type;
	prop->info.name = &prop->name;
	prop->info.class_name = &prop->class_name;
	prop->info.hint = PROPERTY_HINT_NONE;
	prop->info.hint_string = &prop->hint;
	prop->info.usage = PROPERTY_USAGE_DEFAULT;
}

void property_deinit(OwnedProperty *prop)
{
	destroy_string_name(&prop->name);
	destroy_string(&prop->hint);
	destroy_string_name(&prop->class_name);
}

void load_api(GDExtensionInterfaceGetProcAddress get_proc_address)
{
	api.classdb_register_extension_class6 = (GDExtensionInterfaceClassdbRegisterExtensionClass6)get_proc_address("classdb_register_extension_class6");
	api.classdb_unregister_extension_class = (GDExtensionInterfaceClassdbUnregisterExtensionClass)get_proc_address("classdb_unregister_extension_class");
	api.classdb_register_extension_class_method = (GDExtensionInterfaceClassdbRegisterExtensionClassMethod)get_proc_address("classdb_register_extension_class_method");
	api.classdb_construct_object3 = (GDExtensionInterfaceClassdbConstructObject3)get_proc_address("classdb_construct_object3");
	api.object_set_instance = (GDExtensionInterfaceObjectSetInstance)get_proc_address("object_set_instance");

	api.string_name_new_with_latin1_chars = (GDExtensionInterfaceStringNameNewWithLatin1Chars)get_proc_address("string_name_new_with_latin1_chars");
	api.string_new_with_utf8_chars = (GDExtensionInterfaceStringNewWithUtf8Chars)get_proc_address("string_new_with_utf8_chars");

	api.get_variant_from_type_constructor = (GDExtensionInterfaceGetVariantFromTypeConstructor)get_proc_address("get_variant_from_type_constructor");
	api.get_variant_to_type_constructor = (GDExtensionInterfaceGetVariantToTypeConstructor)get_proc_address("get_variant_to_type_constructor");
	api.variant_get_type = (GDExtensionInterfaceVariantGetType)get_proc_address("variant_get_type");
	api.variant_get_ptr_constructor = (GDExtensionInterfaceVariantGetPtrConstructor)get_proc_address("variant_get_ptr_constructor");
	api.variant_get_ptr_destructor = (GDExtensionInterfaceVariantGetPtrDestructor)get_proc_address("variant_get_ptr_destructor");
	api.variant_get_ptr_builtin_method = (GDExtensionInterfaceVariantGetPtrBuiltinMethod)get_proc_address("variant_get_ptr_builtin_method");
	api.variant_destroy = (GDExtensionInterfaceVariantDestroy)get_proc_address("variant_destroy");

	api.array_operator_index = (GDExtensionInterfaceArrayOperatorIndex)get_proc_address("array_operator_index");
	api.dictionary_operator_index = (GDExtensionInterfaceDictionaryOperatorIndex)get_proc_address("dictionary_operator_index");
	api.packed_vector3_array_operator_index = (GDExtensionInterfacePackedVector3ArrayOperatorIndex)get_proc_address("packed_vector3_array_operator_index");
	api.packed_vector2_array_operator_index = (GDExtensionInterfacePackedVector2ArrayOperatorIndex)get_proc_address("packed_vector2_array_operator_index");
	api.packed_color_array_operator_index = (GDExtensionInterfacePackedColorArrayOperatorIndex)get_proc_address("packed_color_array_operator_index");
	api.packed_int32_array_operator_index = (GDExtensionInterfacePackedInt32ArrayOperatorIndex)get_proc_address("packed_int32_array_operator_index");
	api.packed_float32_array_operator_index = (GDExtensionInterfacePackedFloat32ArrayOperatorIndex)get_proc_address("packed_float32_array_operator_index");

	api.mem_alloc = (GDExtensionInterfaceMemAlloc)get_proc_address("mem_alloc");
	api.mem_free = (GDExtensionInterfaceMemFree)get_proc_address("mem_free");

	constructors.from_array = api.get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_ARRAY);
	constructors.from_dictionary = api.get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_DICTIONARY);
	constructors.from_string = api.get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_STRING);
	constructors.from_vector3 = api.get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_VECTOR3);
	constructors.from_bool = api.get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_BOOL);
	constructors.from_packed_vector3 = api.get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY);
	constructors.from_packed_vector2 = api.get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY);
	constructors.from_packed_color = api.get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY);
	constructors.from_packed_int32 = api.get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	constructors.from_packed_float32 = api.get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);

	constructors.to_int = api.get_variant_to_type_constructor(GDEXTENSION_VARIANT_TYPE_INT);
	constructors.to_float = api.get_variant_to_type_constructor(GDEXTENSION_VARIANT_TYPE_FLOAT);
	constructors.to_packed_float32 = api.get_variant_to_type_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);

	destructors.string = api.variant_get_ptr_destructor(GDEXTENSION_VARIANT_TYPE_STRING);
	destructors.string_name = api.variant_get_ptr_destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
	destructors.array = api.variant_get_ptr_destructor(GDEXTENSION_VARIANT_TYPE_ARRAY);
	destructors.dictionary = api.variant_get_ptr_destructor(GDEXTENSION_VARIANT_TYPE_DICTIONARY);
	destructors.packed_vector3 = api.variant_get_ptr_destructor(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY);
	destructors.packed_vector2 = api.variant_get_ptr_destructor(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY);
	destructors.packed_color = api.variant_get_ptr_destructor(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY);
	destructors.packed_int32 = api.variant_get_ptr_destructor(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	destructors.packed_float32 = api.variant_get_ptr_destructor(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);

	methods.array_resize = get_resize(GDEXTENSION_VARIANT_TYPE_ARRAY);
	methods.packed_vector3_resize = get_resize(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY);
	methods.packed_vector2_resize = get_resize(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY);
	methods.packed_color_resize = get_resize(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY);
	methods.packed_int32_resize = get_resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	methods.packed_float32_resize = get_resize(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);
}
