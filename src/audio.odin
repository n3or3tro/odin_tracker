package main
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import ma "vendor:miniaudio"

Audio_State :: struct {
	playing: bool,
	tracks:  [dynamic]^ma.sound_group,
	engine:  ma.engine,
}

SOUND_FILE_LOAD_FLAGS :: u32(ma.sound_flags.DECODE | ma.sound_flags.NO_SPATIALIZATION)
sound_files: [2]cstring = {
	"/home/lucas/Music/test_sounds/bless_america/gettysburg.wav",
	"/home/lucas/Music/test_sounds/bless_america/preamble.wav",
}

audio_engine := new(ma.engine)
engine_sounds := make([dynamic]^ma.sound)
// For now there will be a fixed amount of channels, but IRL this will be dynamic.
audio_channels: [4]^ma.sound_group


// since we don't have a gui for playing sounds, the engine will just load 2 tracks when created.
setup_audio_engine :: proc(engine: ^ma.engine) -> ^ma.engine {
	// Engine config is set by default when you init the engine, but can be manually set.
	res := ma.engine_init(nil, engine)
	assert(res == .SUCCESS)
	sound_group_config := ma.sound_group_config {
		flags = SOUND_FILE_LOAD_FLAGS,
	}
	for i in 0 ..< 4 {
		audio_channels[i] = new(ma.sound_group)
		res = ma.sound_group_init_ex(engine, &sound_group_config, audio_channels[i])
		assert(res == .SUCCESS)
	}
	return engine
}

load_files :: proc() {
	sound0: ^ma.sound = new(ma.sound)
	sound1: ^ma.sound = new(ma.sound)
	res := ma.sound_init_from_file(
		audio_engine,
		sound_files[0],
		SOUND_FILE_LOAD_FLAGS,
		audio_channels[0],
		nil,
		sound0,
	)
	assert(res == .SUCCESS)
	res = ma.sound_init_from_file(
		audio_engine,
		sound_files[1],
		SOUND_FILE_LOAD_FLAGS,
		audio_channels[1],
		nil,
		sound1,
	)
	assert(res == .SUCCESS)
	append_elem(&engine_sounds, sound0)
	append_elem(&engine_sounds, sound1)
}


toggle_sound :: proc(sound: ^ma.sound) {
	if ma.sound_is_playing(sound) {
		res := ma.sound_stop(sound)
		assert(res == .SUCCESS)
	} else {
		res := ma.sound_start(sound)
		assert(res == .SUCCESS)
	}
}

change_volume :: proc(sound: ^ma.sound, volume: f32) {
	ma.sound_group_set_volume(audio_channels[0], volume)
	ma.sound_group_get_volume(audio_channels[0])
	ma.sound_set_volume(sound, volume)
}
