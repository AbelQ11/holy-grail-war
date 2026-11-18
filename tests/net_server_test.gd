extends SceneTree
## Authoritative server harness for the Milestone 3 network test.
## Run: godot --headless --path . --port=7796 --script res://tests/net_server_test.gd

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame

	var scene: PackedScene = load("res://scenes/arena.tscn") as PackedScene
	var arena: Node2D = scene.instantiate() as Node2D
	root.add_child(arena)
	await process_frame
	await process_frame

	# Host uses an explicit Master and Servant Class (the Spirit is rolled secretly).
	arena.request_summon("shirou_emiya", ServantData.ServantClass.SABER, Roster.RollMode.SPECIFIC)
	await process_frame
	arena.request_deploy()
	await process_frame
	await process_frame

	var host_master: MasterController = arena.get_local_master()
	var host_servant: ServantController = arena.get_local_servant()
	if host_master == null or host_servant == null:
		push_error("NET SERVER TEST FAILED: host duo did not spawn")
		quit(1)
		return
	if host_master.master_data.master_id != "shirou_emiya" or host_servant.servant_data.servant_class != ServantData.ServantClass.SABER:
		push_error("NET SERVER TEST FAILED: host class-only summon resolved incorrectly")
		quit(1)
		return

	# Capture a Leyline before the client joins to exercise late-join sync.
	var west_leyline: LeylineNode = arena.get_leylines()[0]
	host_servant.position = west_leyline.global_position
	await create_timer(2.9).timeout
	if west_leyline.owner_peer_id != 1:
		push_error("NET SERVER TEST FAILED: host did not capture the western Leyline")
		quit(1)
		return

	print("NET SERVER TEST READY: host Shirou + Saber-class Servant deployed; LeylineWest captured")
	await create_timer(20.0).timeout
	print("NET SERVER TEST COMPLETE")
	quit(0)
