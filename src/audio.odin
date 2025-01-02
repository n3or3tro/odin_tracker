package main
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import ma "vendor:miniaudio"

// when ODIN_OS == .Linux {
// 	sound_files: [2]cstring = {
// 		"/home/lucas/Music/test_sounds/bless_america/gettysburg.wav",
// 		"/home/lucas/Music/test_sounds/bless_america/preamble.wav",
// 	}
// } else {
// 	sound_files: [2]cstring = {
// 		"C:/Users/n3or3tro/Music/tracker/1.wav",
// 		"C:/Users/n3or3tro/Music/tracker/2.wav",
// 	}
// }

Audio_State :: struct {
	playing:   bool,
	tracks:    [dynamic]^ma.sound_group,
	engine:    ma.engine,
	curr_step: u16, // current step in a sequence
}

SOUND_FILE_LOAD_FLAGS :: u32(ma.sound_flags.DECODE | ma.sound_flags.NO_SPATIALIZATION)
N_AUDIO_GROUPS :: 1


audio_engine := new(ma.engine)
// engine_sounds := make([dynamic]^ma.sound)
engine_sounds: [N_TRACKS]^ma.sound


// For now there will be a fixed amount of channels, but IRL this will be dynamic.
// Channels are a miniaudio idea of basically audio processing groups. Need to dive deeper into this
// as it probably will help in designging the audio processing stuff.
audio_groups: [N_AUDIO_GROUPS]^ma.sound_group


toggle_all_audio_playing :: proc() {
	for sound in engine_sounds {
		if sound != nil {
			if audio_state.playing {
				ma.sound_stop(sound)
			} else {
				ma.sound_start(sound)
			}
		}
	}
}

setup_audio_engine :: proc(engine: ^ma.engine) -> ^ma.engine {
	// Engine config is set by default when you init the engine, but can be manually set.
	res := ma.engine_init(nil, engine)
	assert(res == .SUCCESS)
	sound_group_config := ma.sound_group_config {
		flags = SOUND_FILE_LOAD_FLAGS,
	}
	for i in 0 ..< N_AUDIO_GROUPS {
		audio_groups[i] = new(ma.sound_group)
		res = ma.sound_group_init_ex(engine, &sound_group_config, audio_groups[i])
		assert(res == .SUCCESS)
	}
	return engine
}


set_track_sound :: proc(path: cstring, which: u32) {
	if engine_sounds[which] != nil {
		ma.sound_uninit(engine_sounds[which])
	}
	new_sound := new(ma.sound)
	res := ma.sound_init_from_file(
		audio_engine,
		path,
		SOUND_FILE_LOAD_FLAGS,
		audio_groups[0], // at the moment we only have 1 audio group. This will probs change.
		nil,
		new_sound,
	)
	engine_sounds[which] = new_sound
}

toggle_sound_playing :: proc(sound: ^ma.sound) {
	if sound == nil {
		println(
			"Passed in a 'nil' sound.\nMost likely this track hasn't been loaded with a sound.",
		)
	} else {
		if ma.sound_is_playing(sound) {
			res := ma.sound_stop(sound)
			assert(res == .SUCCESS)
		} else {
			res := ma.sound_start(sound)
			assert(res == .SUCCESS)
		}
	}
}

set_volume :: proc(sound: ^ma.sound, volume: f32) {
	ma.sound_set_volume(sound, volume)
}
