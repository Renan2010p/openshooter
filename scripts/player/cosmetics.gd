class_name Cosmetics
## Free character customization (the Locker): headwear, hair, face, top,
## legs, shoes and back items.
##
## Every item is a few Block nodes attached to a joint of the [Avatar] (head,
## spine, knees...), so it moves with the animation and is merged into the
## character mesh by the avatar bake: items cost nothing extra to draw.
##
## A "look" is a Dictionary {slot: item id}, for example
##   {"hat": "cap", "hair": "long", "face": "none", "top": "hoodie",
##    "legs": "cargo", "feet": "boots", "back": "backpack"}
## It is saved in Config, sent to the server with the player profile, and
## rebuilt on every computer.
##
## Coordinates: the character looks down -Z. Head blocks are relative to
## Spine/Head (head cube from y = 0 to 0.48, half width 0.24); torso blocks to
## Spine (torso from y = -0.03 to 0.77, half depth 0.2); shoe blocks to each
## Knee (the foot sits around y = -0.37).

## Order of the slots in the Locker.
const SLOTS := ["hat", "hair", "face", "top", "legs", "feet", "back"]
const SLOT_NAMES := {
	"hat": "HEADWEAR", "hair": "HAIR", "face": "FACE", "top": "TOP",
	"legs": "LEGS", "feet": "SHOES", "back": "BACK",
}

## Every item, per slot: [id, name shown in the Locker]. All are free.
const ITEMS := {
	"hat": [["none", "None"], ["santa", "Santa Hat"], ["beanie", "Beanie"], ["cap", "Cap"],
		["helmet", "Helmet"], ["headband", "Headband"], ["cowboy", "Cowboy Hat"], ["headphones", "Headphones"]],
	"hair": [["short", "Short"], ["buzz", "Buzz Cut"], ["spiky", "Spiky"], ["mohawk", "Mohawk"],
		["long", "Long"], ["ponytail", "Ponytail"], ["bald", "Bald"]],
	"face": [["none", "None"], ["sunglasses", "Sunglasses"], ["goggles", "Goggles"], ["bandana", "Bandana"],
		["beard", "Beard"], ["mustache", "Mustache"], ["eyepatch", "Eye Patch"]],
	"top": [["tshirt", "T-Shirt"], ["hoodie", "Hoodie"], ["jacket", "Jacket"], ["vest", "Tactical Vest"],
		["scarf", "Scarf"], ["suit", "Suit & Tie"]],
	"legs": [["pants", "Pants"], ["shorts", "Shorts"], ["cargo", "Cargo Pants"], ["kneepads", "Knee Pads"]],
	"feet": [["sneakers", "Sneakers"], ["boots", "Boots"], ["combat", "Combat Boots"], ["hightops", "High-Tops"],
		["sandals", "Sandals"]],
	"back": [["none", "None"], ["backpack", "Backpack"], ["cape", "Cape"], ["radio", "Radio Pack"]],
}

const DEFAULT_HAIR := Color(0.2, 0.13, 0.08)
## Hair colors bots pick from.
const HAIR_COLORS := [Color(0.2, 0.13, 0.08), Color(0.08, 0.07, 0.06), Color(0.55, 0.35, 0.15),
	Color(0.85, 0.7, 0.4), Color(0.6, 0.18, 0.1), Color(0.75, 0.75, 0.78)]

const BLACK := Color(0.07, 0.07, 0.08)
const DARK := Color(0.16, 0.16, 0.19)
const WHITE := Color(0.93, 0.94, 0.96)
const RED := Color(0.78, 0.09, 0.11)
const OLIVE := Color(0.29, 0.32, 0.2)
const BROWN := Color(0.4, 0.25, 0.13)
const STEEL := Color(0.45, 0.47, 0.5)


# ============================================================================
# Looks
# ============================================================================

## The look of a new player. The Christmas edition starts with the Santa hat.
static func defaults() -> Dictionary:
	var look := {}
	for slot in SLOTS:
		look[slot] = ITEMS[slot][0][0]
	if Holiday.ENABLED:
		look["hat"] = "santa"
	return look


## A copy of `look` with only known slots and items (anything unknown, for
## example from another computer, falls back to the default).
static func sanitize(look: Variant) -> Dictionary:
	var clean := defaults()
	if look is Dictionary:
		for slot in SLOTS:
			var id := str(look.get(slot, ""))
			if has_item(slot, id):
				clean[slot] = id
	return clean


static func has_item(slot: String, id: String) -> bool:
	for item in ITEMS.get(slot, []):
		if item[0] == id:
			return true
	return false


## A random look (for bots).
static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var look := {}
	for slot in SLOTS:
		var items: Array = ITEMS[slot]
		look[slot] = items[rng.randi() % items.size()][0]
	return look


# ============================================================================
# Building the items
# ============================================================================

## Adds the items of `look` to `avatar` (before it is baked). `colors` holds
## the player's "shirt", "pants", "skin" and "hair" colors, used for items that
## should match the outfit.
static func apply(avatar: Avatar, look: Dictionary, colors: Dictionary) -> void:
	look = sanitize(look)
	# The default hair and eyebrows follow the hair color.
	for path in ["Spine/Head/Hair", "Spine/Head/Nape", "Spine/Head/EyebrowL", "Spine/Head/EyebrowR"]:
		var b := avatar.get_node_or_null(path) as Block
		if b:
			b.tint = Block.Tint.HAIR
	_build_hair(avatar, look.hair)
	_build_hat(avatar, look.hat, colors)
	_build_face(avatar, look.face)
	_build_top(avatar, look.top, colors)
	_build_legs(avatar, look.legs, colors)
	_build_feet(avatar, look.feet)
	_build_back(avatar, look.back)


## One block of an item.
static func _add(parent: Node3D, pos: Vector3, size: Vector3, color: Color,
		tint := Block.Tint.NONE, shape := Block.Shape.BOX) -> Block:
	var b := Block.new()
	b.position = pos
	b.size = size
	b.color = color
	b.tint = tint
	b.shape = shape
	b.collide = false
	parent.add_child(b)
	return b


## Removes default blocks an item replaces (they are not baked yet).
static func _remove(avatar: Avatar, paths: Array) -> void:
	for path in paths:
		var node := avatar.get_node_or_null(path)
		if node:
			node.get_parent().remove_child(node)
			node.free()


static func _hair(parent: Node3D, pos: Vector3, size: Vector3) -> Block:
	return _add(parent, pos, size, DEFAULT_HAIR, Block.Tint.HAIR)


static func _build_hair(avatar: Avatar, id: String) -> void:
	if id == "short":
		return  # the avatar's own Hair and Nape blocks
	_remove(avatar, ["Spine/Head/Hair", "Spine/Head/Nape"])
	var h := avatar.head
	match id:
		"buzz":
			_hair(h, Vector3(0, 0.49, 0.0), Vector3(0.49, 0.025, 0.49))
			_hair(h, Vector3(0, 0.38, 0.243), Vector3(0.49, 0.2, 0.01))
		"spiky":
			_hair(h, Vector3(0, 0.5, 0.02), Vector3(0.5, 0.08, 0.5))
			_hair(h, Vector3(0, 0.36, 0.22), Vector3(0.5, 0.26, 0.08))
			for spike in [Vector3(-0.15, 0.58, -0.12), Vector3(0.0, 0.6, -0.15), Vector3(0.15, 0.58, -0.1),
					Vector3(-0.1, 0.59, 0.08), Vector3(0.1, 0.6, 0.1), Vector3(0.0, 0.58, 0.2)]:
				_hair(h, spike, Vector3(0.1, 0.1, 0.1))
		"mohawk":
			_hair(h, Vector3(0, 0.57, 0.03), Vector3(0.1, 0.16, 0.48))
			_hair(h, Vector3(0, 0.3, 0.245), Vector3(0.1, 0.3, 0.02))
		"long":
			_hair(h, Vector3(0, 0.5, 0.02), Vector3(0.5, 0.08, 0.5))
			_hair(h, Vector3(0, 0.2, 0.24), Vector3(0.52, 0.64, 0.08))
			_hair(h, Vector3(-0.255, 0.28, 0.05), Vector3(0.03, 0.36, 0.38))
			_hair(h, Vector3(0.255, 0.28, 0.05), Vector3(0.03, 0.36, 0.38))
		"ponytail":
			_hair(h, Vector3(0, 0.5, 0.02), Vector3(0.5, 0.08, 0.5))
			_hair(h, Vector3(0, 0.36, 0.22), Vector3(0.5, 0.26, 0.08))
			_add(h, Vector3(0, 0.42, 0.29), Vector3(0.1, 0.06, 0.06), RED)
			_hair(h, Vector3(0, 0.24, 0.31), Vector3(0.12, 0.3, 0.1))
		"bald":
			pass


static func _build_hat(avatar: Avatar, id: String, colors: Dictionary) -> void:
	var h := avatar.head
	var shirt: Color = colors.get("shirt", Color.GRAY)
	match id:
		"santa":
			_add(h, Vector3(0, 0.53, 0), Vector3(0.54, 0.12, 0.54), WHITE)
			_add(h, Vector3(0, 0.65, 0.02), Vector3(0.46, 0.14, 0.46), RED)
			_add(h, Vector3(0, 0.77, 0.07), Vector3(0.34, 0.12, 0.34), RED)
			_add(h, Vector3(0, 0.87, 0.13), Vector3(0.22, 0.1, 0.22), RED)
			_add(h, Vector3(0, 0.93, 0.21), Vector3(0.12, 0.08, 0.14), RED)
			_add(h, Vector3(0, 0.95, 0.3), Vector3(0.14, 0.14, 0.14), WHITE, Block.Tint.NONE, Block.Shape.SPHERE)
		"beanie":
			_add(h, Vector3(0, 0.47, 0), Vector3(0.54, 0.08, 0.54), shirt.darkened(0.25))
			_add(h, Vector3(0, 0.56, 0.01), Vector3(0.5, 0.14, 0.5), shirt.darkened(0.1))
			_add(h, Vector3(0, 0.65, 0.01), Vector3(0.12, 0.06, 0.12), WHITE)
		"cap":
			_add(h, Vector3(0, 0.54, 0.02), Vector3(0.52, 0.12, 0.5), shirt)
			_add(h, Vector3(0, 0.495, -0.33), Vector3(0.44, 0.03, 0.2), shirt.darkened(0.3))
			_add(h, Vector3(0, 0.61, 0.02), Vector3(0.06, 0.03, 0.06), shirt.darkened(0.3))
		"helmet":
			_add(h, Vector3(0, 0.56, 0), Vector3(0.56, 0.2, 0.56), OLIVE)
			_add(h, Vector3(0, 0.46, 0), Vector3(0.6, 0.05, 0.6), OLIVE.darkened(0.2))
			_add(h, Vector3(0, 0.58, -0.285), Vector3(0.2, 0.08, 0.02), OLIVE.darkened(0.35))
		"headband":
			_add(h, Vector3(0, 0.42, 0), Vector3(0.5, 0.07, 0.5), RED)
			_add(h, Vector3(0.06, 0.38, 0.27), Vector3(0.05, 0.14, 0.02), RED)
		"cowboy":
			_add(h, Vector3(0, 0.52, 0), Vector3(0.82, 0.03, 0.82), BROWN)
			_add(h, Vector3(0, 0.63, 0.02), Vector3(0.44, 0.2, 0.44), BROWN)
			_add(h, Vector3(0, 0.56, 0.02), Vector3(0.45, 0.05, 0.45), DARK)
		"headphones":
			_add(h, Vector3(0, 0.58, 0), Vector3(0.52, 0.04, 0.09), DARK)
			_add(h, Vector3(-0.265, 0.45, 0), Vector3(0.04, 0.22, 0.06), DARK)
			_add(h, Vector3(0.265, 0.45, 0), Vector3(0.04, 0.22, 0.06), DARK)
			_add(h, Vector3(-0.27, 0.28, 0), Vector3(0.07, 0.18, 0.18), RED)
			_add(h, Vector3(0.27, 0.28, 0), Vector3(0.07, 0.18, 0.18), RED)


static func _build_face(avatar: Avatar, id: String) -> void:
	var h := avatar.head
	match id:
		"sunglasses":
			_add(h, Vector3(-0.1, 0.3, -0.255), Vector3(0.14, 0.08, 0.02), BLACK)
			_add(h, Vector3(0.1, 0.3, -0.255), Vector3(0.14, 0.08, 0.02), BLACK)
			_add(h, Vector3(0, 0.32, -0.255), Vector3(0.08, 0.02, 0.02), BLACK)
			_add(h, Vector3(-0.247, 0.32, -0.13), Vector3(0.02, 0.02, 0.24), BLACK)
			_add(h, Vector3(0.247, 0.32, -0.13), Vector3(0.02, 0.02, 0.24), BLACK)
		"goggles":
			_add(h, Vector3(0, 0.31, 0), Vector3(0.51, 0.06, 0.51), DARK)
			_add(h, Vector3(-0.1, 0.3, -0.262), Vector3(0.15, 0.11, 0.04), Color(0.95, 0.55, 0.1))
			_add(h, Vector3(0.1, 0.3, -0.262), Vector3(0.15, 0.11, 0.04), Color(0.95, 0.55, 0.1))
		"bandana":
			_add(h, Vector3(0, 0.13, -0.252), Vector3(0.5, 0.16, 0.03), RED)
			_add(h, Vector3(0, 0.04, -0.255), Vector3(0.2, 0.06, 0.03), RED)
			_add(h, Vector3(0, 0.15, 0), Vector3(0.5, 0.05, 0.5), RED)
		"beard":
			_hair(h, Vector3(0, 0.1, -0.24), Vector3(0.44, 0.16, 0.04))
			_hair(h, Vector3(0, 0.03, -0.2), Vector3(0.3, 0.06, 0.1))
			_hair(h, Vector3(-0.235, 0.17, -0.1), Vector3(0.03, 0.22, 0.26))
			_hair(h, Vector3(0.235, 0.17, -0.1), Vector3(0.03, 0.22, 0.26))
		"mustache":
			_hair(h, Vector3(0, 0.205, -0.255), Vector3(0.22, 0.04, 0.02))
		"eyepatch":
			_add(h, Vector3(-0.1, 0.3, -0.255), Vector3(0.13, 0.13, 0.02), BLACK)
			_add(h, Vector3(0, 0.37, 0), Vector3(0.5, 0.025, 0.5), BLACK)


static func _build_top(avatar: Avatar, id: String, colors: Dictionary) -> void:
	var s := avatar.spine
	var shirt: Color = colors.get("shirt", Color.GRAY)
	match id:
		"hoodie":
			_add(s, Vector3(0, 0.66, 0.21), Vector3(0.52, 0.26, 0.12), shirt.darkened(0.15))
			_add(s, Vector3(0, 0.16, -0.205), Vector3(0.42, 0.16, 0.02), shirt.darkened(0.2))
			_add(s, Vector3(-0.06, 0.6, -0.205), Vector3(0.025, 0.18, 0.02), WHITE)
			_add(s, Vector3(0.06, 0.6, -0.205), Vector3(0.025, 0.18, 0.02), WHITE)
		"jacket":
			_add(s, Vector3(0, 0.76, 0), Vector3(0.5, 0.08, 0.44), DARK)
			_add(s, Vector3(-0.13, 0.58, -0.208), Vector3(0.14, 0.32, 0.03), DARK)
			_add(s, Vector3(0.13, 0.58, -0.208), Vector3(0.14, 0.32, 0.03), DARK)
			_add(s, Vector3(0, 0.37, -0.205), Vector3(0.03, 0.76, 0.02), STEEL)
		"vest":
			_add(s, Vector3(0, 0.42, -0.215), Vector3(0.58, 0.5, 0.05), OLIVE)
			_add(s, Vector3(0, 0.42, 0.215), Vector3(0.58, 0.5, 0.05), OLIVE)
			_add(s, Vector3(-0.2, 0.72, 0), Vector3(0.12, 0.06, 0.44), OLIVE)
			_add(s, Vector3(0.2, 0.72, 0), Vector3(0.12, 0.06, 0.44), OLIVE)
			for x in [-0.17, 0.0, 0.17]:
				_add(s, Vector3(x, 0.24, -0.255), Vector3(0.13, 0.15, 0.06), OLIVE.darkened(0.25))
		"scarf":
			_add(s, Vector3(0, 0.75, 0), Vector3(0.48, 0.11, 0.46), RED)
			_add(s, Vector3(0.12, 0.58, -0.225), Vector3(0.1, 0.26, 0.03), RED)
			_add(s, Vector3(0.12, 0.46, -0.225), Vector3(0.1, 0.03, 0.03), WHITE)
		"suit":
			# The whole upper body turns into a dark suit (no shirt color).
			var suit := Color(0.12, 0.14, 0.2)
			for path in ["Spine/Log", "Spine/Collar", "Spine/ArmL/Sleeve", "Spine/ArmR/Sleeve",
					"Spine/ArmL/ShoulderJoint", "Spine/ArmR/ShoulderJoint",
					"Spine/ArmL/Elbow/ElbowJoint", "Spine/ArmR/Elbow/ElbowJoint"]:
				var b := avatar.get_node_or_null(path) as Block
				if b:
					b.tint = Block.Tint.NONE
					b.color = suit
			_add(s, Vector3(0, 0.6, -0.205), Vector3(0.16, 0.32, 0.02), WHITE)
			_add(s, Vector3(0, 0.52, -0.215), Vector3(0.06, 0.34, 0.02), RED)


static func _build_legs(avatar: Avatar, id: String, colors: Dictionary) -> void:
	var pants: Color = colors.get("pants", Color.DIM_GRAY)
	match id:
		"shorts":
			# Bare lower legs.
			for leg in ["LegL", "LegR"]:
				for part in ["Knee/Shin", "Knee/KneeJoint"]:
					var b := avatar.get_node_or_null("%s/%s" % [leg, part]) as Block
					if b:
						b.tint = Block.Tint.SKIN
		"cargo":
			_add(avatar.leg_l, Vector3(-0.17, -0.26, 0), Vector3(0.03, 0.14, 0.18), pants.darkened(0.25))
			_add(avatar.leg_r, Vector3(0.17, -0.26, 0), Vector3(0.03, 0.14, 0.18), pants.darkened(0.25))
		"kneepads":
			_add(avatar.knee_l, Vector3(0, 0, -0.165), Vector3(0.3, 0.2, 0.05), BLACK)
			_add(avatar.knee_r, Vector3(0, 0, -0.165), Vector3(0.3, 0.2, 0.05), BLACK)


static func _build_feet(avatar: Avatar, id: String) -> void:
	if id == "sneakers":
		return  # the avatar's own Shoe and Sole blocks
	_remove(avatar, ["LegL/Knee/Shoe", "LegL/Knee/Sole", "LegR/Knee/Shoe", "LegR/Knee/Sole"])
	for knee in [avatar.knee_l, avatar.knee_r]:
		match id:
			"boots":
				_add(knee, Vector3(0, -0.27, 0), Vector3(0.34, 0.26, 0.36), BROWN)
				_add(knee, Vector3(0, -0.37, -0.04), Vector3(0.35, 0.14, 0.44), BROWN)
				_add(knee, Vector3(0, -0.435, -0.04), Vector3(0.36, 0.03, 0.45), DARK)
			"combat":
				_add(knee, Vector3(0, -0.24, 0), Vector3(0.35, 0.32, 0.36), BLACK)
				_add(knee, Vector3(0, -0.37, -0.04), Vector3(0.36, 0.14, 0.45), BLACK)
				_add(knee, Vector3(0, -0.435, -0.04), Vector3(0.37, 0.03, 0.46), DARK)
				for y in [-0.16, -0.22, -0.28]:
					_add(knee, Vector3(0, y, -0.183), Vector3(0.14, 0.015, 0.01), STEEL)
			"hightops":
				_add(knee, Vector3(0, -0.3, 0), Vector3(0.34, 0.2, 0.35), WHITE)
				_add(knee, Vector3(0, -0.37, -0.04), Vector3(0.35, 0.14, 0.44), WHITE)
				_add(knee, Vector3(0, -0.435, -0.04), Vector3(0.36, 0.03, 0.45), RED)
				_add(knee, Vector3(0, -0.33, 0), Vector3(0.355, 0.04, 0.2), RED)
			"sandals":
				_add(knee, Vector3(0, -0.4, -0.04), Vector3(0.3, 0.08, 0.4), DEFAULT_HAIR, Block.Tint.SKIN)
				_add(knee, Vector3(0, -0.385, -0.12), Vector3(0.32, 0.04, 0.06), BROWN)
				_add(knee, Vector3(0, -0.44, -0.04), Vector3(0.34, 0.03, 0.44), BROWN)


static func _build_back(avatar: Avatar, id: String) -> void:
	var s := avatar.spine
	match id:
		"backpack":
			_add(s, Vector3(0, 0.42, 0.3), Vector3(0.5, 0.56, 0.2), OLIVE.darkened(0.1))
			_add(s, Vector3(0, 0.24, 0.41), Vector3(0.36, 0.2, 0.04), OLIVE.darkened(0.3))
			_add(s, Vector3(-0.18, 0.5, -0.205), Vector3(0.06, 0.42, 0.02), OLIVE.darkened(0.3))
			_add(s, Vector3(0.18, 0.5, -0.205), Vector3(0.06, 0.42, 0.02), OLIVE.darkened(0.3))
		"cape":
			_add(s, Vector3(0, 0.3, 0.225), Vector3(0.66, 0.9, 0.03), RED)
			_add(s, Vector3(0, 0.75, 0.0), Vector3(0.5, 0.06, 0.44), RED.darkened(0.3))
		"radio":
			_add(s, Vector3(0, 0.45, 0.29), Vector3(0.38, 0.42, 0.17), DARK)
			_add(s, Vector3(0, 0.5, 0.38), Vector3(0.2, 0.1, 0.02), Color(0.3, 0.8, 0.4))
			_add(s, Vector3(0.13, 0.9, 0.3), Vector3(0.025, 0.5, 0.025), BLACK)
