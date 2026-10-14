extends SceneTree
## Длительности звуковых файлов (отладка): -- <файл1> <файл2> ...


func _init() -> void:
	for p in OS.get_cmdline_user_args():
		var s: AudioStream = null
		match p.get_extension().to_lower():
			"wav": s = AudioStreamWAV.load_from_file(p)
			"ogg": s = AudioStreamOggVorbis.load_from_file(p)
			"mp3": s = AudioStreamMP3.load_from_file(p)
		print("LEN %.2f %s" % [s.get_length() if s != null else -1.0, p.get_file()])
	quit()
