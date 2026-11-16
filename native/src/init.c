#include "api.h"
#include "native_ops.h"

static void initialize(void *userdata, GDExtensionInitializationLevel level)
{
	(void)userdata;
	if (level != GDEXTENSION_INITIALIZATION_SCENE)
		return;
	native_ops_register();
}

static void deinitialize(void *userdata, GDExtensionInitializationLevel level)
{
	(void)userdata;
	if (level != GDEXTENSION_INITIALIZATION_SCENE)
		return;
	native_ops_unregister();
}

GDExtensionBool GDE_EXPORT openshooter_native_init(
		GDExtensionInterfaceGetProcAddress get_proc_address,
		GDExtensionClassLibraryPtr library,
		GDExtensionInitialization *initialization)
{
	class_library = library;
	load_api(get_proc_address);
	initialization->initialize = initialize;
	initialization->deinitialize = deinitialize;
	initialization->userdata = NULL;
	initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
	return 1;
}
