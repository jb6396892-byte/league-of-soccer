extends Node
## One music stream and short event cues; agent/simulation sessions never play audio.
var enabled := true
var muted := false
var music: AudioStreamPlayer
var goal: AudioStreamPlayer
var ui: AudioStreamPlayer
var hover_time := 0
var cues := {}


func _ready() -> void:
	if not enabled:
		return
	for file in ["click_001", "click_003", "confirmation_002"]:
		cues[file] = load("res://assets/audio/" + file + ".wav")
	music = AudioStreamPlayer.new()
	var loop: AudioStreamWAV = load("res://assets/audio/stadium_loop.wav").duplicate()
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = roundi(loop.get_length() * loop.mix_rate)
	music.stream = loop
	music.volume_db = -22
	add_child(music)
	goal = AudioStreamPlayer.new()
	goal.stream = load("res://assets/audio/goal_celebration.wav")
	goal.volume_db = -9
	add_child(goal)
	ui = AudioStreamPlayer.new()
	ui.volume_db = -15
	add_child(ui)
	music.play()


func play_goal(_team: int) -> void:
	if enabled and not muted:
		goal.play()


func play_ui(kind: String = "click") -> void:
	if not enabled or muted:
		return
	if kind == "hover":
		if Time.get_ticks_msec() - hover_time < 90:
			return
		hover_time = Time.get_ticks_msec()
	ui.stream = cues["click_003" if kind == "hover" else ("confirmation_002" if kind == "confirm" else "click_001")]
	ui.play()


func toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)
