package main
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import ma "vendor:miniaudio"

Track :: struct {
	sound:     ^ma.sound,
	armed:     bool,
	volume:    f32,
	// PCM data is used only for rendering waveforms atm.
	pcm_data:  [dynamic]f32,
	curr_step: u16,
}

Audio_State :: struct {
	tracks:       [dynamic]Track,
	engine:       ^ma.engine,
	// for now there will be a fixed amount of channels, but irl this will be dynamic.
	// channels are a miniaudio idea of basically audio processing groups. need to dive deeper into this
	// as it probably will help in designging the audio processing stuff.
	audio_groups: [N_AUDIO_GROUPS]^ma.sound_group,
	playing:      bool,
	// For some reason this thing needs to be globally accessible (at least according to the docs),
	// Perhaps we can localize it later.
	delay:        ma.delay_node,
}

SOUND_FILE_LOAD_FLAGS: ma.sound_flags = {.DECODE, .NO_SPATIALIZATION}
N_AUDIO_GROUPS :: 1


setup_audio :: proc() -> ^Audio_State {
	audio_state := new(Audio_State)
	audio_state.tracks = make([dynamic]Track)
	engine := new(ma.engine)

	for i in 0 ..< N_TRACKS {
		append(&audio_state.tracks, Track{})
		audio_state.tracks[i].volume = f32(i + (i * 10))
		audio_state.tracks[i].armed = true
	}

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

	init_delay(0.5, 0.3)
	when ODIN_OS == .Windows {
		println("c:\\Music\\tracker\\3.wav loading...")
		set_track_sound("c:\\users\\n3or3tro\\Music\\tracker\\3.wav", 0)
	} else {
		set_track_sound(
			"/home/lucas/Music/test_sounds/the-create-vol-4/loops/01-save-the-day.wav",
			0,
		)
	}
	return audio_state
}

set_track_sound :: proc(path: cstring, which: u32) {
	if app.audio_state.tracks[which].sound != nil {
		ma.sound_uninit(app.audio_state.tracks[which].sound)
	}
	new_sound := new(ma.sound)

	// need to connect sound into node graph

	res := ma.sound_init_from_file(
		app.audio_state.engine,
		path,
		SOUND_FILE_LOAD_FLAGS,
		// At the moment we only have 1 audio group. This will probs change.
		app.audio_state.audio_groups[0],
		nil,
		new_sound,
	)
	if res != .SUCCESS {
		println(res)
		panic("fuck")
	}
	// assert(res == .SUCCESS)

	ma.node_attach_output_bus(cast(^ma.node)new_sound, 0, cast(^ma.node)&app.audio_state.delay, 0)

	app.audio_state.tracks[which].sound = new_sound
}

init_delay :: proc(delay_time: f32, decay_time: f32) {
	channels := ma.engine_get_channels(app.audio_state.engine)
	sample_rate := ma.engine_get_sample_rate(app.audio_state.engine)
	config := ma.delay_node_config_init(
		channels,
		sample_rate,
		u32(f32(sample_rate) * delay_time),
		decay_time,
	)
	println(config)
	res := ma.delay_node_init(
		ma.engine_get_node_graph(app.audio_state.engine),
		&config,
		nil,
		&app.audio_state.delay,
	)
	if res != .SUCCESS {
		println(res)
		panic("")
	}

	res = ma.node_attach_output_bus(
		cast(^ma.node)(&app.audio_state.delay),
		0,
		ma.engine_get_endpoint(app.audio_state.engine),
		0,
	)
	assert(res == .SUCCESS)
}

turn_on_delay :: proc() {
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
	for track in app.audio_state.tracks {
		toggle_sound_playing(track.sound)
	}
}

play_track_step :: proc(which: u32) {
	sound := app.audio_state.tracks[which].sound
	curr_step := app.audio_state.tracks[which].curr_step
	if sound != nil {
		if app.ui_state.selected_steps[which][curr_step] {
			ma.sound_stop(sound)
			pitch := ui_state.step_pitches[which][curr_step]
			ma.sound_set_pitch(sound, pitch / 12)
			ma.sound_seek_to_pcm_frame(sound, 0)
			ma.sound_start(sound)
		}
	}
}

// This is here coz I was thinking about cachine the pcm wav rendering data, 
// since it's a little expensive to re-calc every frame.
get_track_pcm_data :: proc(track: u32) -> [dynamic]f32 {
	return app.audio_state.tracks[track].pcm_data
}

store_track_pcm_data :: proc(track: u32) {
	sound := app.audio_state.tracks[track].sound
	n_frames: u64
	res := ma.sound_get_length_in_pcm_frames(sound, &n_frames)
	assert(res == .SUCCESS)

	// Code will break if you pass in a .wav file that doesn't have 2 channels.
	buf := make([dynamic]f32, n_frames * 2, context.temp_allocator) // assuming stereo
	defer delete(buf)

	frames_read: u64

	data_source := ma.sound_get_data_source(sound)
	res = ma.data_source_read_pcm_frames(data_source, raw_data(buf), n_frames, &frames_read)
	assert(res == .SUCCESS || res == .AT_END)

	// pcm_frames := make([dynamic]f32, frames_read)
	app.audio_state.tracks[track].pcm_data = make([dynamic]f32, frames_read)
	pcm_frames := app.audio_state.tracks[track].pcm_data
	// Gets left channel (interleaved stereo: L R L R ...)
	for i in 0 ..< frames_read {
		pcm_frames[i] = buf[i * 2]
	}
}
