package app
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import ma "vendor:miniaudio"

Audio_State :: struct {
	playing:        bool,
	tracks:         [dynamic]^ma.sound_group,
	curr_step:      u16, // current step in a sequence
	slider_volumes: [10]f32,
	engine:         ^ma.engine,
	engine_sounds:  [N_TRACKS]^ma.sound,

	// for now there will be a fixed amount of channels, but irl this will be dynamic.
	// channels are a miniaudio idea of basically audio processing groups. need to dive deeper into this
	// as it probably will help in designging the audio processing stuff.
	audio_groups:   [N_AUDIO_GROUPS]^ma.sound_group,
}

SOUND_FILE_LOAD_FLAGS: ma.sound_flags = {.DECODE, .NO_SPATIALIZATION}
N_AUDIO_GROUPS :: 1


setup_audio :: proc() -> ^Audio_State {
	audio_state := new(Audio_State)
	engine := new(ma.engine)
	audio_state.slider_volumes = {10, 20, 30, 40, 50, 60, 70, 80, 90, 100}
	// Engine config is set by default when you init the engine, but can be manually set.
	res := ma.engine_init(nil, engine)
	assert(res == .SUCCESS)
	sound_group_config := ma.sound_group_config {
		flags = SOUND_FILE_LOAD_FLAGS,
	}
	for i in 0 ..< N_AUDIO_GROUPS {
		audio_state.audio_groups[i] = new(ma.sound_group)
		res = ma.sound_group_init_ex(engine, &sound_group_config, audio_state.audio_groups[i])
		assert(res == .SUCCESS)
	}
	app.audio_state = audio_state
	audio_state.engine = engine
	return audio_state
}

set_track_sound :: proc(path: cstring, which: u32) {
	if app.audio_state.engine_sounds[which] != nil {
		ma.sound_uninit(app.audio_state.engine_sounds[which])
	}
	new_sound := new(ma.sound)
	res := ma.sound_init_from_file(
		app.audio_state.engine,
		path,
		SOUND_FILE_LOAD_FLAGS,
		app.audio_state.audio_groups[0], // at the moment we only have 1 audio group. This will probs change.
		nil,
		new_sound,
	)
	app.audio_state.engine_sounds[which] = new_sound
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

toggle_all_audio_playing :: proc() {
	for sound in app.audio_state.engine_sounds {
		toggle_sound_playing(sound)
	}
}

play_current_step :: proc() {
	for sound, row in app.audio_state.engine_sounds {
		if sound != nil {
			if app.ui_state.selected_steps[row][app.audio_state.curr_step] {
				ma.sound_stop(sound)
				pitch := ui_state.step_pitches[row][app.audio_state.curr_step]
				ma.sound_set_pitch(sound, pitch / 12)
				ma.sound_seek_to_pcm_frame(sound, 0)
				ma.sound_start(sound)
			}
		}
	}
}
