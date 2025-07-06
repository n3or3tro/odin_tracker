package main
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import s "core:strings"
import "core:time"
import ma "vendor:miniaudio"

Track :: struct {
	sound:     ^ma.sound,
	armed:     bool,
	volume:    f32,
	// PCM data is used only for rendering waveforms atm.
	pcm_data:  struct {
		left_channel:  [dynamic]f32,
		right_channel: [dynamic]f32,
	},
	curr_step: u32,
}

Audio_State :: struct {
	playing:             bool,
	bpm:                 u16,
	tracks:              [dynamic]Track,
	engine:              ^ma.engine,
	// For some reason this thing needs to be globally accessible (at least according to the docs),
	// Perhaps we can localize it later.
	delay:               ma.delay_node,
	// for now there will be a fixed amount of channels, but irl this will be dynamic.
	// channels are a miniaudio idea of basically audio processing groups. need to dive deeper into this
	// as it probably will help in designging the audio processing stuff.
	audio_groups:        [N_AUDIO_GROUPS]^ma.sound_group,
	//
	// last_step_time: time.Time,
	last_step_time_nsec: i64,
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
		set_track_sound("/home/lucas/Music/test_sounds/the-create-vol-4/loops/01-save-the-day.wav", 0)
	}
	app.audio_state.bpm = 120
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


toggle_sound_playing :: proc(sound: ^ma.sound) {
	if sound == nil {
		println("Passed in a 'nil' sound.\nMost likely this track hasn't been loaded with a sound.")
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

play_track_step :: proc(which_track: u32) {
	sound := app.audio_state.tracks[which_track].sound
	step_num := u32(app.audio_state.tracks[which_track].curr_step)

	// this can happen if a track is created and a sound HAS NOT been loaded.
	if sound == nil {
		return
	}

	pitch_box, volume_box, send1_box, send2_box := get_substeps_input_from_step(step_num, which_track)

	println("trying to play_track_step()")
	println(pitch_box, volume_box, send1_box, send2_box)
	// Assumes all values in the step are valid, which should be the case when a user 'enables' a step.
	pitch := pitch_difference("C3", pitch_box.value.?.(string)) / 12
	volume := f32(volume_box.value.?.(u32))

	// need to figure out sends.
	if app.ui_state.selected_steps[which_track][step_num] {
		ma.sound_stop(sound)
		pitch := ui_state.step_pitches[which_track][step_num]
		ma.sound_set_pitch(sound, pitch / 12)
		ma.sound_set_volume(sound, volume / 100)
		ma.sound_seek_to_pcm_frame(sound, 0)
		ma.sound_start(sound)
	}
}

// returns number of semitones between 2 notes.
pitch_difference :: proc(from: string, to: string) -> f32 {
	chromatic_scale := make(map[string]int, context.temp_allocator)
	chromatic_scale["C"] = 0
	chromatic_scale["C#"] = 1
	chromatic_scale["D"] = 2
	chromatic_scale["D#"] = 3
	chromatic_scale["E"] = 4
	chromatic_scale["F"] = 5
	chromatic_scale["F#"] = 6
	chromatic_scale["G"] = 7
	chromatic_scale["G#"] = 8
	chromatic_scale["A"] = 9
	chromatic_scale["A#"] = 10
	chromatic_scale["B"] = 11

	from_octave := strconv.atoi(from[len(from) - 1:])
	to_octave := strconv.atoi(to[len(to) - 1:])

	octave_diff := from_octave - to_octave

	from_is_sharp := s.contains(from, "#")
	to_is_sharp := s.contains(to, "#")

	from_note := from_is_sharp ? chromatic_scale[from[0:2]] : chromatic_scale[from[0:1]]
	to_note := to_is_sharp ? chromatic_scale[to[0:2]] : chromatic_scale[to[0:1]]

	octave_diff_in_semitones := octave_diff * 12
	total_diff := octave_diff_in_semitones - (-1 * (from_note - to_note))
	return f32(total_diff)
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
// This indirection is here coz I was thinking about cachine the pcm wav rendering data, 
// since it's a little expensive to re-calc every frame.
get_track_pcm_data :: proc(track: u32) -> (left_channel, right_channel: [dynamic]f32) {
	return app.audio_state.tracks[track].pcm_data.left_channel,
		app.audio_state.tracks[track].pcm_data.right_channel
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

	// might have weird off by one errors further in the system. CBF figuring out the math
	// so we just add + 1 the capacity for now 
	left_channel := make([dynamic]f32, frames_read / 2 + 1)
	right_channel := make([dynamic]f32, frames_read / 2 + 1)
	lc_pointer: u64 = 0
	rc_pointer: u64 = 1
	i := 0
	for rc_pointer < frames_read {
		left_channel[i] = buf[lc_pointer]
		right_channel[i] = buf[rc_pointer]
		i += 1
		lc_pointer += 2
		rc_pointer += 2
	}
	app.audio_state.tracks[track].pcm_data.left_channel = left_channel
	app.audio_state.tracks[track].pcm_data.right_channel = right_channel
}
