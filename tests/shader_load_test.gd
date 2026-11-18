extends SceneTree
## Loads each presentation shader so parse/compile errors fail CI.

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var paths: Array[String] = [
		"res://shaders/fog_of_war.gdshader",
		"res://shaders/reality_marble.gdshader",
		"res://shaders/presence_concealment.gdshader",
	]
	var failures: int = 0
	for path: String in paths:
		var shader: Shader = load(path) as Shader
		if shader == null:
			failures += 1
			push_error("SHADER LOAD FAILED: %s" % path)
			continue
		if shader.code.is_empty():
			failures += 1
			push_error("SHADER EMPTY: %s" % path)
			continue
		print("  PASS  shader parses: %s" % path)
	if failures == 0:
		print("SHADER LOAD TEST PASSED")
		quit(0)
	else:
		print("SHADER LOAD TEST FAILED (%d)" % failures)
		quit(1)
