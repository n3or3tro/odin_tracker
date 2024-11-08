package main
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import ma "vendor:miniaudio"
import sdl "vendor:sdl2"
import smixer "vendor:sdl2/mixer"


// For simplicity, this example requires the device to use floating point samples.
SAMPLE_FORMAT :: ma.format.f32
CHANNEL_COUNT: u64 : 2
SAMPLE_RATE: u64 : 48000
decoder_count: u32
// decoders: ^[dynamic]ma.decoder = new()
decoders: [20]ma.decoder
// ended_decoders: ^[dynamic]bool
ended_decoders: [20]bool
stop_event: ma.event // <---- signaled by the audio thread, waited on by main thread.


all_decoders_at_end :: proc() -> bool {
	for i: u32 = 0; i < decoder_count; i += 1 {
		if ended_decoders[i] == false {
			return false
		}
	}
	return true
}

data_callback :: proc(device: ^ma.device, output, input: rawptr, frame_count: u64) {
	output_f32 := cast(^[4096]f32)(output)

	// assert(device.playback.playback_format == SAMPLE_FORMAT)

	for i: u32 = 0; i < decoder_count; i += 1 {
		if !ended_decoders[i] {
			frames_read := read_and_mix_pcm_frames(&decoders[i], output_f32, cast(u32)frame_count)
			if frames_read < frame_count {
				ended_decoders[i] = true
			}
		}
	}
	/*
    If at the end all of our decoders are at the end we need to stop. We cannot stop the device in the callback. Instead we need to
    signal an event to indicate that it's stopped. The main thread will be waiting on the event, after which it will stop the device.
    */
	if (all_decoders_at_end()) {
		ma.event_signal(&stop_event)
	}
}
// Size of types is weird in this code... it was copied from miniaudio.io examples.
// Types of this function are strange in general. Definitely need to clean up once I understand
// what's going on.
read_and_mix_pcm_frames :: proc(
	decoder: ^ma.decoder,
	output: ^[4096]f32,
	frame_count: u32,
) -> u64 {
	result: ma.result
	temp: [4096]f32
	// vvv this code is suss
	/*---> */temp_capacity_in_frames: u64 = len(temp) / CHANNEL_COUNT // <----
	// ^^^ this code is suss
	total_frames_read: u64 = 0

	for total_frames_read < cast(u64)frame_count {
		sample: u64
		frames_read_this_iteration: u64
		frames_remaining_total: u64 = cast(u64)frame_count - total_frames_read
		frames_to_read_this_iteration := temp_capacity_in_frames
		if frames_to_read_this_iteration > frames_remaining_total {
			frames_to_read_this_iteration = frames_remaining_total
		}
		result = ma.decoder_read_pcm_frames(
			decoder,
			cast(rawptr)&temp,
			frames_to_read_this_iteration,
			&frames_read_this_iteration,
		)
		if result == .SUCCESS || frames_read_this_iteration == 0 {
			break
		}
		// mix frames together
		for i: u64 = 0; i < frames_read_this_iteration * cast(u64)CHANNEL_COUNT; i += 1 {
			index: u64 = total_frames_read * CHANNEL_COUNT + i
			output[index] += temp[i]
		}
		// clip audio (adding sounds can cause sample values to peak)
		// todo 
		// ----------------

		total_frames_read += frames_read_this_iteration
		if frames_read_this_iteration < frames_to_read_this_iteration {
			break
		}

	}
	return total_frames_read
}

setup_and_play :: proc(files_to_play: [dynamic]string) {
	result: ma.result
	decoder_config: ma.decoder_config
	device_config: ma.device_config
	device: ^ma.device = new(ma.device)
	i_decoder: u32

	decoder_count = cast(u32)len(files_to_play)
	// decoders = new([dynamic]ma.decoder)
	// ended_decoders = new([dynamic]bool)

	// In this example, all decoders need to have the same output format.
	decoder_config = ma.decoder_config_init(
		SAMPLE_FORMAT,
		cast(u32)CHANNEL_COUNT,
		cast(u32)SAMPLE_RATE,
	)
	for i: u32 = 0; i < decoder_count; i += 1 {
		println("decoder_count: ", decoder_count)
		println("i: ", i)
		result = ma.decoder_init_file(
			strings.clone_to_cstring(files_to_play[i_decoder]),
			&decoder_config,
			&decoders[i_decoder],
		)
		// println(decoders[i_decoder])
		if result != .SUCCESS {
			fmt.printf("Failed to load file: %s", files_to_play[i])
		}
		ended_decoders[i_decoder] = false
	}
	// Create only a single device. The decoders will be mixed together in the callback. In this example the data format needs to be the same as the decoders. */
	device_config = ma.device_config_init(ma.device_type.playback)
	device_config.playback.format = SAMPLE_FORMAT
	device_config.playback.channels = cast(u32)CHANNEL_COUNT
	device_config.sampleRate = cast(u32)SAMPLE_RATE
	device_config.dataCallback = cast(ma.device_data_proc)data_callback
	device_config.pUserData = nil

	if ma.device_init(nil, &device_config, device) != .SUCCESS {
		panic("Failed to open playback device")
	}
	/*
    We can't stop in the audio thread so we instead need to use an event. 
	We wait on this thread in the main thread, and signal it in the audio thread. 
	This needs to be done before starting the device. We need a context to initialize the event, 
	which we can get from the device. Alternatively you can initialize a context separately, 
	but we don't need to do that for this example.
    */
	ma.event_init(&stop_event)

	/* Now we start playback and wait for the audio thread to tell us to stop. */
	if ma.device_start(device) != .SUCCESS {
		ma.device_uninit(device)
		for i_decoder = 0; i_decoder < decoder_count; i_decoder += 1 {
			ma.decoder_uninit(&decoders[i_decoder])
		}
		panic("Failed to start playback device.\n")
	}

	fmt.printf("Waiting for playback to complete...\n")
	ma.event_wait(&stop_event)

	/* Getting here means the audio thread has signaled that the device should be stopped. */
	ma.device_uninit(device)

	for i_decoder: u32 = 0; i_decoder < decoder_count; i_decoder += 1 {
		ma.decoder_uninit(&decoders[i_decoder])
	}
}


// data_callback :: proc(device: ^ma.device, output, input: rawptr, frame_count: u64) {
// 	decoder := cast(^ma.decoder)(device.pUserData)
// 	if decoder == nil {
// 		panic("data_callback(): Decoder is nil")
// 	}
// 	f32_output := cast(^[4096]f32)(output)
// 	f32_input := cast(^[4096]f32)(input)
// 	frames_read := read_and_mix_pcm_frames(decoder, f32_output, cast(u32)frame_count)
// 	if frames_read < frame_count {
// 		// todo
// 		// ----------------
// 	}
// }

// setup_audio :: proc() -> ^ma.context_type {
// 	ctx: ^ma.context_type = new(ma.context_type)
// 	devices_info: [^]ma.device_info
// 	n_devices: u32
// 	i_device: u32

// 	if ma.context_init(nil, 0, nil, ctx) != .SUCCESS {
// 		panic("Failed to initialize miniaudio context")
// 	}
// 	if ma.context_get_devices(ctx, &devices_info, &n_devices, nil, nil) != .SUCCESS {
// 		panic("failed to get info on audio devices")
// 	}
// 	for device in 0 ..< n_devices {
// 		fmt.printf("%s\n", devices_info[device].name)
// 	}
// 	return ctx
// }


// play_sound :: proc(path: string) {
// 	data_callback :: proc(device: ^ma.device, output, input: rawptr, frame_count: u64) {
// 		// todo	
// 		decoder := cast(^ma.decoder)(device.pUserData)
// 		if decoder == nil {
// 			panic("data_callback(): Decoder is nil")
// 		}
// 		ma.decoder_read_pcm_frames(decoder, output, frame_count, nil)
// 	}
// 	decoder: ma.decoder
// 	// Cloning to cstring everytime is not efficient.
// 	res := ma.decoder_init_file(strings.clone_to_cstring(path), nil, &decoder)
// 	println(res)
// 	if res != .SUCCESS {
// 		panic("Failed to load file")
// 	}

// 	device_config := ma.device_config_init(ma.device_type.playback)
// 	device_config.playback.format = decoder.outputFormat
// 	device_config.playback.channels = decoder.outputChannels
// 	device_config.sampleRate = decoder.outputSampleRate
// 	device_config.pUserData = &decoder
// 	device_config.dataCallback = cast(ma.device_data_proc)data_callback

// 	device: ma.device
// 	if ma.device_init(nil, &device_config, &device) != .SUCCESS {
// 		panic("Failed to open playback device")
// 	}
// 	if ma.device_start(&device) != .SUCCESS {
// 		panic("Failed to start playback device")
// 	}
// 	println("Press [Enter] to stop the program")
// 	buf: [1]byte
// 	os.read(os.stdin, buf[:])
// }
