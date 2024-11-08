package main
/* code to play 1 sound file */

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
