package app

window :: proc(id_string: string, rect: Rect) {
	container(tprintf("{}_container", id_string), rect)
}
