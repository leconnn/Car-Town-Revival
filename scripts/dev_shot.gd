class_name DevShot
extends RefCounted
## Testing aid: with `-- shot=<path> [shot_frames=N]` on the command line,
## saves a screenshot after N frames and quits.


static func maybe_capture(node: Node) -> void:
	var args := {}
	for a: String in OS.get_cmdline_user_args():
		var parts := a.split("=", true, 1)
		if parts.size() == 2:
			args[parts[0]] = parts[1]
	if not args.has("shot"):
		return
	var frames := int(args.get("shot_frames", "10"))
	for i in frames:
		await node.get_tree().process_frame
	node.get_viewport().get_texture().get_image().save_png(args["shot"])
	node.get_tree().quit()
