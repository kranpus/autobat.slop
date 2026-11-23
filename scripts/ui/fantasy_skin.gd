class_name FantasySkin
extends RefCounted
## The fantasy look, drawn in code at startup (cached): dark wood panels with
## gold trim, parchment, a stone background, scroll rods, and the Cinzel
## heading font (SIL Open Font License, assets/licenses/Cinzel_OFL.txt).
## Everything is generated from noise, so there are no extra image files to
## ship apart from the font and the sword cursor (Kenney, CC0).

const GOLD := Color("d9b45a")
const GOLD_DARK := Color("7a5a22")
const WOOD := Color("2b2119")
const WOOD_LIGHT := Color("3a2d22")
const INK := Color("3a2716")
const INK_DIM := Color("6e5536")
const INK_GOOD := Color("2f6a2c")
const INK_ACCENT := Color("8a5a12")
const INK_BAD := Color("8e2420")
const PARCHMENT := Color("e4cf9f")

static var _cache := {}


static func _cached(key: String, maker: Callable) -> Variant:
	if not _cache.has(key):
		_cache[key] = maker.call()
	return _cache[key]


static func _noise(seed_v: int, freq: float, octaves: int = 3) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = octaves
	return n


# --- fonts ------------------------------------------------------------------------

## Cinzel, a Roman-inscription face, for headings, tabs and big buttons.
static func heading_font(bold: bool = true) -> Font:
	return _cached("font_%s" % bold, func():
		var base := load("res://assets/fonts/Cinzel.ttf") as FontFile
		var f := FontVariation.new()
		f.base_font = base
		# (The weight axis needs its numeric OpenType tag; the name is ignored.)
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700 if bold else 500}
		# Symbols and arrows Cinzel lacks come from the default font chain.
		var fallback: Font = ThemeDB.fallback_font
		if fallback:
			f.fallbacks = [fallback]
		return f)


# --- textures ---------------------------------------------------------------------

## A 9-slice frame: wood inside, a gold trim, studs in the corners.
## tone: 0 dark panel, 1 lighter card, 2 button, 3 button hover, 4 button
## pressed, 5 disabled button, 6 gold (call-to-action) button.
static func frame_texture(tone: int) -> Texture2D:
	return _cached("frame_%d" % tone, func():
		var size := 96
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		# Grain for the centre tile: seamless noise smeared sideways (wrapping
		# around), so the tiled middle of a big panel shows no seams.
		var inner := size - 16
		var raw := _noise(11 + tone, 0.06, 3).get_seamless_image(inner, inner, false, false, 0.1, true)
		var grain := PackedFloat32Array()
		grain.resize(inner * inner)
		for gy in inner:
			for gx in inner:
				var acc := 0.0
				for k in range(-5, 6):
					acc += raw.get_pixel(posmod(gx + k, inner), gy).r
				grain[gy * inner + gx] = acc / 11.0 * 2.0 - 1.0
		var base: Color = [WOOD, WOOD_LIGHT, Color("3b2e22"), Color("4a3a2b"), Color("251c14"), Color("2a2622"), Color("c9a24a")][tone]
		var trim := GOLD if tone != 5 else Color("6d6352")
		if tone == 6:
			trim = Color("fff0b0")
		for y in size:
			for x in size:
				# Wood grain runs sideways: stretch the noise horizontally.
				var g := grain[posmod(y - 8, inner) * inner + posmod(x - 8, inner)] * 0.8
				var c := base.lightened(g * 0.12) if g > 0.0 else base.darkened(-g * 0.18)
				if tone == 6:
					c = base.lerp(Color("f2d27a"), clampf(1.0 - float(y) / float(size), 0.0, 1.0) * 0.6).lightened(g * 0.05)
				var edge := mini(mini(x, y), mini(size - 1 - x, size - 1 - y))
				if edge == 0:
					c = Color(0.05, 0.04, 0.03)
				elif edge <= 2:
					# Bevelled gold: brighter on the top/left.
					var lit := 0.25 if (x < size / 2 and y < size / 2) else -0.2
					c = trim.lightened(lit) if lit > 0.0 else trim.darkened(-lit)
				elif edge == 3:
					c = c.darkened(0.45)
				img.set_pixel(x, y, c)
		# Gold studs in the corners.
		for corner in [Vector2i(6, 6), Vector2i(size - 7, 6), Vector2i(6, size - 7), Vector2i(size - 7, size - 7)]:
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var d := absi(dx) + absi(dy)
					if d <= 2:
						img.set_pixel(corner.x + dx, corner.y + dy, trim.lightened(0.3) if d == 0 else trim)
		return ImageTexture.create_from_image(img))


## Aged parchment with darker, slightly ragged edges.
static func parchment_texture() -> Texture2D:
	return _cached("parchment", func():
		var w := 320
		var h := 320
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var fibre := _noise(3, 0.05, 4)
		var stain := _noise(7, 0.012, 2)
		var rag := _noise(21, 0.2, 1)
		for y in h:
			for x in w:
				var n := fibre.get_noise_2d(x, y)
				var s := stain.get_noise_2d(x, y)
				var c := PARCHMENT.darkened(0.06 + n * 0.08 + maxf(0.0, s) * 0.18)
				var edge := float(mini(mini(x, y), mini(w - 1 - x, h - 1 - y)))
				var burn := 14.0 + rag.get_noise_2d(x, y) * 6.0
				if edge < burn:
					c = c.darkened((1.0 - edge / burn) * 0.45)
				img.set_pixel(x, y, c)
		return ImageTexture.create_from_image(img))


## Dark stone for the screen background (tiles seamlessly).
static func stone_texture() -> Texture2D:
	return _cached("stone", func():
		var n := _noise(5, 0.02, 5)
		var img := n.get_seamless_image(256, 256, false, false, 0.1, true)
		img.convert(Image.FORMAT_RGBA8)
		for y in 256:
			for x in 256:
				var v := img.get_pixel(x, y).r
				img.set_pixel(x, y, Color("15171d").lerp(Color("262a33"), v * v))
		return ImageTexture.create_from_image(img))


## A wooden scroll rod with gold end caps (9-slice: the caps keep their shape).
static func rod_texture() -> Texture2D:
	return _cached("rod", func():
		var w := 96
		var h := 22
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var grain := _noise(9, 0.08, 2)
		for y in h:
			# Round shading: light along the middle, dark at the top and bottom.
			var shade := 1.0 - absf(float(y) - h * 0.45) / (h * 0.55)
			for x in w:
				var cap := x < 12 or x >= w - 12
				var c: Color
				if cap:
					c = GOLD_DARK.lerp(GOLD.lightened(0.25), shade)
					if x == 0 or x == w - 1 or y == 0 or y == h - 1:
						c = Color(0.05, 0.04, 0.03)
				else:
					var g := grain.get_noise_2d(float(x) * 0.3, y)
					c = Color("3b2717").lerp(Color("8a6037"), shade * 0.9).lightened(g * 0.08)
					if y <= 2 or y >= h - 3:
						c = c.darkened(0.5)
				img.set_pixel(x, y, c)
		return ImageTexture.create_from_image(img))


# --- style boxes ------------------------------------------------------------------

static func frame_box(tone: int, margin: float = 10.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = frame_texture(tone)
	sb.set_texture_margin_all(8)
	sb.set_content_margin_all(margin)
	# Tile the wood rather than stretching it into streaks on big panels.
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return sb


static func parchment_box(margin: float = 18.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = parchment_texture()
	sb.set_texture_margin_all(24)
	sb.set_content_margin_all(margin)
	# Parchment stretches (soft enough not to show it) rather than tiling,
	# which would show seams.
	return sb


## A red wax-seal button for the scroll ("Attack").
static func seal_button_boxes() -> Dictionary:
	var out := {}
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color("7a1f1c"), "hover": Color("972a24"), "pressed": Color("5a1512"), "disabled": Color("6b5a4a")}[state]
		sb.border_color = Color("3b0d0b")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(14)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		sb.shadow_color = Color(0.2, 0.08, 0.02, 0.35)
		sb.shadow_size = 3
		out[state] = sb
	return out
