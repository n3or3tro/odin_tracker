package app
import ma "vendor:miniaudio"

sampler :: proc(name: string, rect: Rect) {
	cnt := container(tprintf("{}-container@sampler"), rect).box.rect
	waveform_container := get_top(cnt, {.Percent, 0.95})
	cut_top(&waveform_container, {.Percent, 0.1})
	cut_bottom(&waveform_container, {.Percent, 0.1})
	cut_left(&waveform_container, {.Percent, 0.1})
	cut_right(&waveform_container, {.Percent, 0.1})
	container(tprintf("{}-waveform-container@sampler"), waveform_container)
}

get_pcm_data :: proc(sound: ^ma.sound) -> [dynamic]f32 {
	n_frames: u64
	res := ma.sound_get_length_in_pcm_frames(sound, &n_frames)
	assert(res == .SUCCESS)

	pcm_frames := make([dynamic]f32, n_frames)
	frames_read: u64
	ma.data_source_read_pcm_frames(sound.pDataSource, raw_data(pcm_frames), n_frames, &frames_read)
	return pcm_frames
}
