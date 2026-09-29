extends Node
## Autoload "Sound": background music and sound effects from the original.
## Missing files are skipped silently (e.g. before art/audio is exported).

const MUSIC_DIR := "res://assets/ea/audio/music"
const SFX_DIR := "res://assets/ea/audio/sfx"
const POOL_SIZE := 6

var _music: AudioStreamPlayer
var _music_name := ""
var _pool: Array[AudioStreamPlayer] = []
var _cache: Dictionary[String, AudioStream] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	add_child(_music)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_pool.append(p)
	# Every button in the game clicks.
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is BaseButton:
			(n as BaseButton).pressed.connect(play.bind("ClickSound01")))


func play(name: String) -> void:
	var stream := _load(SFX_DIR.path_join(name + ".mp3"))
	if stream == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.play()
			return


func music(name: String) -> void:
	if name == _music_name:
		return
	_music_name = name
	var stream := _load(MUSIC_DIR.path_join(name + ".mp3"))
	if stream == null:
		_music.stop()
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_music.stream = stream
	_music.play()


func stop_music() -> void:
	_music_name = ""
	_music.stop()


func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path)
	_cache[path] = stream
	return stream
