class_name AvatarRig
extends Node3D
## A 3D worker (components/avatar/Avatar): the Collada model embedded in the
## original client, dressed from an outfit. Clothes share one 128 x 128
## texture (each piece pasted into its TEXTURE_AREA); the head, hair and hats
## have their own; skin and hair are tinted; the face features are painted
## onto the head. Animations are frame ranges of the model's one 30 fps clip.

const MODEL_PATH := "res://assets/ea/avatar3d/avatar.dae"
const SETTINGS_PATH := "res://assets/ea/avatar3d/avatar_settings.xml"
const TEXTURE_DIR := "res://assets/ea/avatar3d/"
const FPS := 30.0
const ATLAS_SIZE := 128

static var _model: PackedScene
static var _settings: Dictionary = {}

var outfit: Dictionary = AvatarPortrait.DEFAULT_OUTFIT
var _root: Node3D
var _player: AnimationPlayer
var _meshes: Dictionary[String, MeshInstance3D] = {}
var _anim := "idle"
var _range := Vector2(1100, 1168)
var _time := 0.0
var _tool := ""
var _loop := true


static func load_settings() -> Dictionary:
	if not _settings.is_empty():
		return _settings
	var parser := XMLParser.new()
	if parser.open(SETTINGS_PATH) != OK:
		return {}
	var anims := {}
	var elements := {}
	var current := ""
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		match parser.get_node_name():
			"ANIMATION":
				anims[parser.get_named_attribute_value_safe("name")] = {
					"start": int(parser.get_named_attribute_value_safe("start")),
					"end": int(parser.get_named_attribute_value_safe("end")),
					"tool": parser.get_named_attribute_value_safe("tool"),
				}
			"ELEMENT":
				current = parser.get_named_attribute_value_safe("name")
				elements[current] = {"group": parser.get_named_attribute_value_safe("group"),
					"material": parser.get_named_attribute_value_safe("material")}
			"TEXTURE_AREA":
				if current != "":
					elements[current]["area"] = Rect2i(int(parser.get_named_attribute_value_safe("x")), int(parser.get_named_attribute_value_safe("y")),
						int(parser.get_named_attribute_value_safe("width")), int(parser.get_named_attribute_value_safe("height")))
	_settings = {"animations": anims, "elements": elements}
	return _settings


static func available() -> bool:
	return ResourceLoader.exists(MODEL_PATH)


func setup(look: Dictionary) -> void:
	outfit = look
	if _model == null:
		_model = load(MODEL_PATH)
	load_settings()
	_root = _model.instantiate() as Node3D
	add_child(_root)
	for m: Node in _root.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		mesh.visible = false
		_meshes[String(mesh.name)] = mesh
	var players := _root.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_player = players[0] as AnimationPlayer
		_player.play("default")
		_player.pause()
	_dress()
	play("idle")


func _mesh(element: String) -> MeshInstance3D:
	return _meshes.get(element.trim_prefix("_"), null)


func _id(part: String) -> int:
	return int(outfit.get(part, AvatarPortrait.DEFAULT_OUTFIT.get(part, 0)))


func _setting(part: String) -> int:
	return int(outfit.get("settings", {}).get(part, AvatarPortrait.DEFAULT_OUTFIT["settings"].get(part, 0)))


## Updates what's shown and the textures (updateShirt, updatePants,
## updateHair, updateSkinParts).
func _dress() -> void:
	var skin: Dictionary = AvatarColors.SKIN[mini(AvatarPortrait.digit(_setting("head"), 10000), AvatarColors.SKIN.size() - 1)]
	var hair_tone: Dictionary = AvatarColors.HAIR[mini(AvatarPortrait.digit(_setting("hair"), 10000), AvatarColors.HAIR.size() - 1)]
	var top := _id("top")
	var bottom := _id("bottom")
	var skirt := _is_skirt(bottom)
	var body := Image.create(ATLAS_SIZE, ATLAS_SIZE, false, Image.FORMAT_RGBA8)
	body.fill(Color.WHITE)
	_paste(body, "shirt", "shirt_%d" % top)
	_paste(body, "sleeve_left", "sleeve_%d" % top)
	_paste(body, "pants", "pants_%d" % (58 if skirt else bottom))
	if skirt:
		_paste(body, "skirt", "skirt_%d" % bottom)
	_paste(body, "_armLeft", "arm", skin)
	_paste(body, "shoesLeft", "shoe", skin)
	var body_mat := _material(ImageTexture.create_from_image(body))
	for piece: String in ["shirt", "sleeve_left", "sleeve_right", "pants", "armLeft", "armRight", "shoesLeft", "shoesRight"]:
		_show(piece, body_mat)
	if skirt:
		_show("skirt", body_mat)
	var hat := _id("hat")
	if hat > 0 and hat != AvatarPortrait.NO_HAT and _mesh("hat_%d" % hat) != null:
		_show("hat_%d" % hat, _material(_texture("hat_%d" % hat)))
		var alt := int(GameData.catalog.avatar_item(_id("hair")).get("raw", {}).get("ai", "1"))
		_show("hairhat_%d" % maxi(1, alt), _material(_texture("hairhat_%d" % maxi(1, alt), hair_tone)))
	elif _mesh("hair_%d" % _id("hair")) != null:
		_show("hair_%d" % _id("hair"), _material(_texture("hair_%d" % _id("hair"), hair_tone)))
	var head := "face_%d" % _id("head")
	if _mesh(head) == null:
		head = "face_68"
	_show(head, _material(_texture("face", skin)))
	_paint_face(head, skin)


static func _is_skirt(item_id: int) -> bool:
	return int(GameData.catalog.avatar_item(item_id).get("type", 0)) == 12


func _show(element: String, mat: Material) -> void:
	var m := _mesh(element)
	if m == null:
		return
	m.visible = true
	m.material_override = mat


static func _material(tex: Texture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return mat


static func _image(name: String) -> Image:
	var tex: Texture2D = load(TEXTURE_DIR + name + ".jpg") if ResourceLoader.exists(TEXTURE_DIR + name + ".jpg") else null
	if tex == null:
		return null
	var img := tex.get_image().duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


static func _texture(name: String, tone: Dictionary = {}) -> Texture2D:
	var img := _image(name)
	if img == null:
		return null
	if tone.is_empty():
		return ImageTexture.create_from_image(img)
	return ColorMatrix.tinted_texture(name, img, tone)


## Avatar3DElement.applyMaterialToUV: a piece's texture into its area.
func _paste(atlas: Image, element: String, texture: String, tone: Dictionary = {}) -> void:
	var area: Rect2i = load_settings()["elements"].get(element, {}).get("area", Rect2i())
	var img := _image(texture)
	if img == null or area.size == Vector2i.ZERO:
		return
	if not tone.is_empty():
		img = ColorMatrix.apply_to_image(img, ColorMatrix.from_adjustment(tone))
	atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), area.position)


## updateSkinParts: the face features drawn at a quarter size over the head.
func _paint_face(head: String, skin: Dictionary) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 256)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var portrait := AvatarPortrait.create(outfit, true)
	portrait.position = Vector2(128, 75)
	vp.add_child(portrait)
	add_child(vp)
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var features := vp.get_texture().get_image()
	vp.queue_free()
	features.resize(64, 64, Image.INTERPOLATE_BILINEAR)
	var face := _image("face")
	if face == null:
		return
	face = ColorMatrix.apply_to_image(face, ColorMatrix.from_adjustment(skin))
	face.resize(64, 64)
	face.blend_rect(features, Rect2i(0, 0, 64, 64), Vector2i.ZERO)
	var m := _mesh(head)
	if m != null:
		m.material_override = _material(ImageTexture.create_from_image(face))


## Plays a named animation (playSequenceByName), showing its tool.
func play(anim: String, loop: bool = true) -> void:
	var a: Dictionary = load_settings()["animations"].get(anim, {})
	if a.is_empty():
		return
	_anim = anim
	_loop = loop
	_range = Vector2(a["start"], a["end"])
	_time = _range.x / FPS
	if _tool != "":
		var old := _mesh(_tool)
		if old != null:
			old.visible = false
	_tool = a["tool"]
	if _tool != "":
		var element: Dictionary = load_settings()["elements"].get(_tool, {})
		var m := _mesh(_tool)
		if m != null:
			m.material_override = _material(_texture(str(element.get("material", _tool.trim_prefix("_")))))
			m.visible = true
	_pose()


func current_animation() -> String:
	return _anim


func _process(delta: float) -> void:
	if _player == null:
		return
	_time += delta
	var end := _range.y / FPS
	if _time > end:
		_time = _range.x / FPS if _loop else end
	_pose()


func _pose() -> void:
	if _player != null:
		_player.seek(_time, true)
