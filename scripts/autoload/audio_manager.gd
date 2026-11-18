extends Node
## Server-broadcast presentation feedback: procedural synth SFX, hit-stop,
## camera-shake requests, and floating combat text hooks.
##
## Synthesis uses [AudioStreamGenerator] voices generated on the fly. The
## autoload is safe in headless mode: it keeps the RPC surface alive but skips
## audio output, hit-stop and shake so deterministic tests are unaffected.

signal floating_text_requested(world_position: Vector2, text: String, color: Color)
signal impact_requested(world_position: Vector2, strength: float)

const MIX_RATE: float = 22050.0
const MAX_VOICES: int = 16
const SFX_VOLUME_DB: float = -9.0


class SynthVoice:
	var player: AudioStreamPlayer
	var playback: AudioStreamGeneratorPlayback
	var kind: String = ""
	var time: float = 0.0
	var duration: float = 0.5


var _headless: bool = false
var _voices: Array[SynthVoice] = []
var _hitstop_until_msec: int = 0
var _hitstop_active: bool = false
var _previous_time_scale: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = DisplayServer.get_name() == "headless"


func _process(_delta: float) -> void:
	if _hitstop_active and Time.get_ticks_msec() >= _hitstop_until_msec:
		Engine.time_scale = _previous_time_scale
		_hitstop_active = false
	_advance_voices()


func _exit_tree() -> void:
	if _hitstop_active:
		Engine.time_scale = 1.0
	for voice: SynthVoice in _voices:
		if voice != null and is_instance_valid(voice.player):
			voice.player.stop()
			voice.player.queue_free()
	_voices.clear()
	_hitstop_active = false


# --- Public broadcast API ----------------------------------------------------

## Play a one-shot synth locally on every peer. Server-authoritative.
func broadcast_sfx(kind: String, world_position: Vector2 = Vector2.ZERO) -> void:
	if not multiplayer.has_multiplayer_peer():
		play_sfx(kind)
		return
	if multiplayer.get_peers().is_empty():
		_rpc_sfx(kind, world_position)
	else:
		_rpc_sfx.rpc(kind, world_position)


## Float combat text above a world position on every peer.
func broadcast_text(text: String, world_position: Vector2, color: Color = Color.WHITE) -> void:
	if not multiplayer.has_multiplayer_peer():
		floating_text_requested.emit(world_position, text, color)
		return
	if multiplayer.get_peers().is_empty():
		_rpc_text(text, world_position, color)
	else:
		_rpc_text.rpc(text, world_position, color)


## Hit-stop, camera shake and an impact boom for heavy detonations.
func broadcast_impact(world_position: Vector2, strength: float = 0.7, sfx: String = "np_impact") -> void:
	if not multiplayer.has_multiplayer_peer():
		_apply_impact(world_position, strength, sfx)
		return
	if multiplayer.get_peers().is_empty():
		_rpc_impact(world_position, strength, sfx)
	else:
		_rpc_impact.rpc(world_position, strength, sfx)


# --- RPCs --------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _rpc_sfx(kind: String, world_position: Vector2) -> void:
	play_sfx(kind)
	if kind == "leyline_capture":
		floating_text_requested.emit(world_position, "LEYLINE CAPTURED", Color(0.95, 0.82, 0.35))


@rpc("authority", "call_local", "reliable")
func _rpc_text(text: String, world_position: Vector2, color: Color) -> void:
	floating_text_requested.emit(world_position, text, color)


@rpc("authority", "call_local", "reliable")
func _rpc_impact(world_position: Vector2, strength: float, sfx: String) -> void:
	_apply_impact(world_position, strength, sfx)


func _apply_impact(world_position: Vector2, strength: float, sfx: String) -> void:
	play_sfx(sfx)
	impact_requested.emit(world_position, clampf(strength, 0.0, 1.0))
	if not _headless:
		_trigger_hitstop(strength)


func _trigger_hitstop(strength: float) -> void:
	if Engine.time_scale <= 0.05 and _hitstop_active:
		return
	if not _hitstop_active:
		_previous_time_scale = Engine.time_scale
		_hitstop_active = true
	var milliseconds: int = int(lerpf(30.0, 50.0, clampf(strength, 0.0, 1.0)))
	_hitstop_until_msec = Time.get_ticks_msec() + milliseconds
	Engine.time_scale = 0.02


# --- Procedural synthesis ----------------------------------------------------

func play_sfx(kind: String) -> void:
	if _headless:
		return
	if _voices.size() >= MAX_VOICES:
		var oldest: SynthVoice = _voices.pop_front()
		if oldest != null and is_instance_valid(oldest.player):
			oldest.player.queue_free()
	var voice: SynthVoice = SynthVoice.new()
	var generator: AudioStreamGenerator = AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.18
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = generator
	player.volume_db = SFX_VOLUME_DB
	add_child(player)
	player.play()
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		player.queue_free()
		return
	voice.player = player
	voice.playback = playback
	voice.kind = kind
	voice.duration = _duration_for(kind)
	_voices.append(voice)


func _advance_voices() -> void:
	if _voices.is_empty():
		return
	var index: int = _voices.size() - 1
	while index >= 0:
		var voice: SynthVoice = _voices[index]
		if voice == null or not is_instance_valid(voice.player):
			_voices.remove_at(index)
			index -= 1
			continue
		var pushed: int = 0
		while voice.playback.can_push_buffer(1) and pushed < 2048:
			var sample: float = 0.0
			if voice.time < voice.duration:
				sample = _sample_for(voice.kind, voice.time)
			voice.playback.push_frame(Vector2(sample, sample * 0.94))
			voice.time += 1.0 / MIX_RATE
			pushed += 1
		if voice.time >= voice.duration + 0.08:
			voice.player.stop()
			voice.player.queue_free()
			_voices.remove_at(index)
		index -= 1


func _duration_for(kind: String) -> float:
	match kind:
		"sword_clash":
			return 0.30
		"beam_charge", "np_telegraph":
			return 0.50
		"leyline_capture":
			return 0.62
		"command_spell":
			return 0.70
		"np_impact":
			return 0.85
		"trump_impact":
			return 0.75
		"ui_click":
			return 0.09
	return 0.35


func _sample_for(kind: String, t: float) -> float:
	match kind:
		"sword_clash":
			var env: float = exp(-t * 24.0)
			var metal: float = sin(TAU * 1730.0 * t) * 0.5
			metal += sin(TAU * 2590.0 * t + 0.7) * 0.32
			metal += sin(TAU * 3910.0 * t + 1.3) * 0.18
			var thud: float = sin(TAU * 92.0 * t) * exp(-t * 15.0) * 0.35
			return (metal * env + thud) * 0.55
		"beam_charge", "np_telegraph":
			var ratio: float = clampf(t / 0.5, 0.0, 1.0)
			var frequency: float = 190.0 + 1180.0 * ratio * ratio
			var rise: float = 0.15 + ratio * 0.45
			var tremolo: float = 0.7 + 0.3 * sin(TAU * 13.0 * t)
			return sin(TAU * frequency * t) * rise * tremolo * 0.4
		"leyline_capture":
			var notes: Array[float] = [392.0, 523.25, 659.25]
			var step: int = int(t / 0.14) % notes.size()
			var local: float = fmod(t, 0.14)
			var pluck: float = sin(TAU * notes[step] * local) * exp(-local * 11.0) * 0.45
			var chord: float = (sin(TAU * 196.0 * t) + sin(TAU * 392.0 * t)) * exp(-t * 2.2) * 0.12
			return pluck + chord
		"command_spell":
			var boom: float = sin(TAU * 82.0 * t) * exp(-t * 5.5) * 0.6
			var decree: float = sin(TAU * (430.0 + 760.0 * t) * t) * exp(-t * 3.2) * 0.28
			var crack: float = sin(TAU * 2100.0 * t) * exp(-t * 30.0) * 0.18
			return boom + decree + crack
		"np_impact":
			var low: float = sin(TAU * 54.0 * t) * exp(-t * 4.2) * 0.7
			var body: float = sin(TAU * 128.0 * t) * exp(-t * 6.0) * 0.3
			var crack: float = sin(TAU * 2700.0 * t) * exp(-t * 35.0) * 0.22
			return low + body + crack
		"trump_impact":
			var sweep: float = 96.0 - 58.0 * clampf(t / 0.6, 0.0, 1.0)
			var boom: float = sin(TAU * sweep * t) * exp(-t * 4.6) * 0.6
			var spark: float = sin(TAU * 1500.0 * t) * exp(-t * 22.0) * 0.2
			return boom + spark
		"ui_click":
			return sin(TAU * 880.0 * t) * exp(-t * 46.0) * 0.25
	return 0.0
