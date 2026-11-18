extends SceneTree
## Headless checks for the presentation layer: shader-backed overlays exist,
## minimap snapshots are populated, Command Spell sigils track charges, NP
## telegraphs wind up before damage, and the audio autoload is null-safe.

var _failures: int = 0
var _text_events: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	var arena: Node2D = await _make_arena()
	arena.request_summon("shirou_emiya", ServantData.ServantClass.SABER, Roster.RollMode.SPECIFIC)
	await process_frame
	arena.request_deploy()
	await process_frame
	await process_frame

	var servant: ServantController = arena.get_local_servant()
	var master: MasterController = arena.get_local_master()
	_check(servant != null and master != null, "presentation test spawns a host duo")
	if servant == null or master == null:
		await _drop_arena(arena)
		_finish()
		return

	var telegraphs: Node = arena.get_node_or_null("Players/NpTelegraphs")
	_check(telegraphs != null, "additive NP telegraph layer is mounted under Players")
	_check(arena.get("_minimap") != null, "tactical minimap is mounted")
	_check(arena.get("_sigils") != null, "Command Spell sigils are mounted in the HUD")

	var snapshot: Dictionary = arena.get_minimap_snapshot()
	_check(snapshot.get("units", []).size() >= 2, "minimap snapshot includes Master and Servant icons")
	_check(snapshot.get("leylines", []).size() == 3, "minimap snapshot includes all three Leylines")
	_check((snapshot.get("camera_rect", Rect2()) as Rect2).size.x > 0.0, "minimap snapshot carries the camera view rect")

	var sigils: CommandSpellSigils = arena.get("_sigils") as CommandSpellSigils
	_check(sigils.charges_left == 3 and not sigils.signature_used, "sigils start with all three charges and the signature slot active")
	master._server_use_command_spell()
	await process_frame
	_check(sigils.charges_left == 2, "sigils drop to two charges after a Command Spell")
	_check(sigils.signature_used, "slot 1 consumes the Master's Signature Command Spell")
	_check((sigils.get("_shatter_start") as Dictionary).has(2), "spent sigil starts its shatter animation")

	servant.mana = servant.max_mana
	servant._server_use_noble_phantasm(Vector2.RIGHT)
	await process_frame
	_check(bool(servant.get("_pending_np_active")), "Noble Phantasm enters a telegraphed windup")
	var entries: Array = telegraphs.get("_entries") as Array
	_check(entries.size() >= 1, "NP windup publishes a ground telegraph")
	await create_timer(0.75).timeout
	_check(not bool(servant.get("_pending_np_active")), "NP detonates after the windup")

	var audio: Node = root.get_node_or_null("AudioManager")
	_check(audio != null, "AudioManager autoload is registered")
	if audio != null:
		audio.connect("floating_text_requested", Callable(self, "_on_text"))
		audio.call("broadcast_text", "TEST", Vector2.ZERO, Color.WHITE)
		audio.call("broadcast_sfx", "sword_clash", Vector2.ZERO)
		audio.call("broadcast_impact", Vector2.ZERO, 0.5, "np_impact")
		await process_frame
		_check(_text_events == 1, "combat-text broadcast reaches the presentation hook")
		_check(Engine.time_scale == 1.0, "headless impact broadcasting leaves time_scale untouched")

	await _drop_arena(arena)
	_finish()


func _on_text(_world_position: Vector2, _text: String, _color: Color) -> void:
	_text_events += 1


func _make_arena() -> Node2D:
	var scene: PackedScene = load("res://scenes/arena.tscn") as PackedScene
	var arena: Node2D = scene.instantiate() as Node2D
	root.add_child(arena)
	await process_frame
	await process_frame
	return arena


func _drop_arena(arena: Node2D) -> void:
	arena.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		push_error("  FAIL  %s" % label)


func _finish() -> void:
	if _failures == 0:
		print("PRESENTATION TEST PASSED")
		quit(0)
	else:
		print("PRESENTATION TEST FAILED (%d failure(s))" % _failures)
		quit(1)
