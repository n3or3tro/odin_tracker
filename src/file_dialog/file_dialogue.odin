package file_dialog
import "core:c"
import "core:fmt"
import "core:sys/posix"
println :: fmt.println

file_dialog :: proc(multiselect: bool = false) -> ([dynamic]string, bool) {
	paths := make([dynamic]string)
	fp := posix.popen("zenity --file-selection --multiple", "r\x00")
	if fp == nil {
		panic("Could not run zenity!")
	}

	in_line: [500]u8
	for {
		posix.fgets(raw_data(in_line[:]), size_of(in_line), fp)
		println(in_line)
	}
	return paths, true
}

// dir_dialog :: proc(multiselect: bool = false) -> [dynamic]string {

// }

// save_file :: proc() -> [dynamic]string {
// }
