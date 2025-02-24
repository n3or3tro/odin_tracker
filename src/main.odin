package main
// import "app"
import "core:c/libc"
import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:thread"
import "core:time"
import ma "vendor:miniaudio"

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

load_app_api :: proc(path: string) -> App_API {
	lib, ok := dynlib.load_library(path)
	if !ok {
		printfln("Failed loading app shared library: %s", path)
		println(dynlib.last_error())
		panic("^^^")
	}
	curr_changed_time, _ := os.last_write_time_by_name(path)
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
		dll_time     = curr_changed_time,
	}
	if api.init == nil ||
	   api.update == nil ||
	   api.shutdown == nil ||
	   api.memory == nil ||
	   api.hot_reloaded == nil {
		dynlib.unload_library(api.lib)
		fmt.println("App DLL missing required procedure")
		panic("^^^")
	}
	return api
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
	app_api := load_app_api("app.so")
	app_api.init()

	for {
		if app_api.update() == false {
			break
		}

		dll_time, err := os.last_write_time_by_name(lib_name)
		should_reload := err == os.ERROR_NONE && app_api.dll_time != dll_time

		if should_reload {
			app_memory := app_api.memory()
			dynlib.unload_library(app_api.lib)
			time.sleep(time.Millisecond * 500)
			app_api := load_app_api("app.so")
			app_api.hot_reloaded(app_memory)
			should_reload = false
		}
	}

}
