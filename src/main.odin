package main
// import "app"
import "core:c/libc"
import "core:dynlib"
import "core:fmt"
// import os "core:os/os2"
import os "core:os"

println :: fmt.println
printfln :: fmt.printfln
printf :: fmt.printf
aprintf :: fmt.aprintf

when ODIN_OS == .Windows {
	lib_name := "app.dll"
}
when ODIN_OS == .Linux {
	lib_name := "app.so"
} else {
	lib_name := "app.so"
}

cwd :: "/home/lucas/NewComp/MUSIC_SOFTWARE/GUIs/current_main_project/"

App_API :: struct {
	init:         proc(),
	update:       proc() -> bool,
	shutdown:     proc(),
	memory:       proc() -> rawptr,
	hot_reloaded: proc(_: rawptr),

	// The loaded DLL handle
	lib:          dynlib.Library,

	/* Used to compare write date on disk vs when
	app API was created. */
	dll_time:     os.File_Time,
	api_version:  u32,
}


load_app_api :: proc(api_version: u32) -> (App_API, bool) {
	dll_time, err := os.last_write_time_by_name(lib_name)
	if err != os.ERROR_NONE {
		printf("Could not fetch last write date of %s", lib_name)
		return {}, false
	}
	when ODIN_OS == .Windows {
		dll_name := aprintf("app_%d.dll", api_version)
		cpy_cmd := fmt.caprintf("copy %s %s", lib_name, dll_name)
	} else {
		dll_name := aprintf("app_%d.so", api_version)
		cpy_cmd := fmt.caprintf("cp %s %s", lib_name, dll_name)
	}
	if libc.system(cpy_cmd) != 0 {
		printfln("Failed to copy %s to %s", lib_name, dll_name)
		return {}, false
	} else {
		chmod_cmd := fmt.caprintf("chmod u+rwx %s", dll_name)
		if libc.system(chmod_cmd) != 0 {
			printfln("Failed to set rwx on %s", dll_name)
			return {}, false
		}

	}

	lib, ok := dynlib.load_library(dll_name)
	if !ok {
		printfln("Failed loading app shared library: %s", dll_name)
		println(dynlib.last_error())
		return {}, false
	}
	api := App_API {
		init         = cast(proc())(dynlib.symbol_address(lib, "app_init") or_else nil),
		update       = cast(proc() -> bool)(dynlib.symbol_address(lib, "app_update") or_else nil),
		shutdown     = cast(proc())(dynlib.symbol_address(lib, "app_shutdown") or_else nil),
		memory       = cast(proc(
		) -> rawptr)(dynlib.symbol_address(lib, "app_memory") or_else nil),
		hot_reloaded = cast(proc(
			_: rawptr,
		))(dynlib.symbol_address(lib, "app_hot_reloaded") or_else nil),
		lib          = lib,
		dll_time     = dll_time,
		api_version  = api_version,
	}
	if api.init == nil ||
	   api.update == nil ||
	   api.shutdown == nil ||
	   api.memory == nil ||
	   api.hot_reloaded == nil {
		dynlib.unload_library(api.lib)
		fmt.println("App DLL missing required procedure")
		return {}, false
	}
	return api, true
}

unload_app_api :: proc(api: App_API) {
	if api.lib != nil {
		dynlib.unload_library(api.lib)
	}

	when ODIN_OS == .Windows {
		del_cmd := fmt.caprintf("del app_%d.dll", api.api_version)
	} else {
		del_cmd := fmt.caprintf("rm app_%d.so", api.api_version)
	}
	if libc.system(del_cmd) != 0 {
		printf("Failed to remove app_%d.dll copy", api.api_version)
	}
}

main :: proc() {
	api_version: u32 = 0
	app_api, ok := load_app_api(api_version)
	if !ok {
		fmt.println("Failed to load APP API")
		return
	}
	api_version += 1
	app_api.init()

	for {
		if app_api.update() == false {
			break
		}

		dll_time, err := os.last_write_time_by_name(lib_name)
		should_reload := err == os.ERROR_NONE && app_api.dll_time != dll_time

		if should_reload {
			new_api, ok := load_app_api(api_version)
			if ok {
				app_memory := app_api.memory()
				unload_app_api(app_api)

				app_api = new_api

				app_api.hot_reloaded(app_memory)
				api_version += 1
			}
		}
	}
	app_api.shutdown()
	unload_app_api(app_api)
}
