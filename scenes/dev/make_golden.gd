extends Node
## Writes tests/fixtures/golden/*.json from GoldenScenarios (see there).


func _ready() -> void:
	var scenarios := GoldenScenarios.all()
	for name: String in scenarios:
		var transcript := GoldenScenarios.run(scenarios[name])
		var path := GoldenScenarios.DIR.path_join(name + ".json")
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(transcript, " ", false))
		f.close()
		print("wrote ", path)
	get_tree().quit()
