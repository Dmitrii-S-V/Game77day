extends SceneTree
## Средний цвет каждого растения атласа диких растений (flora_wild.png, 9x8 ячеек 256 px) -> data/blocks/flora_wild.json:
## lum (яркость), sat (насыщенность), white — почти белое/серое растение (плохо вырезано из белого фона, в игре не ставится).
## C:\Godot\godot.exe --headless --path D:\77Days --script res://tools/flora_lum.gd

const JSON_PATH := "res://data/blocks/flora_wild.json"
const ATLAS := "res://assets/textures/flora_wild.png"
const CELL := 256
const COLS := 9
## Белёсые и с белой каймой от фона (≥10% почти белых пикселей или на глаз): не ставятся в мир.
const REMOVE := [0, 1, 3, 5, 6, 7, 9, 12, 13, 16, 17, 18, 19, 22, 23, 24, 27, 28, 32, 33, 36, 39, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 58, 59, 61, 63, 64, 67, 68]


func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(ATLAS))
	img.convert(Image.FORMAT_RGBA8)
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(JSON_PATH))
	var n_white := 0
	for it: Dictionary in d["items"]:
		if String(it["atlas"]) != "wild":
			continue
		var c := int(it["cell"])
		var x0 := (c % COLS) * CELL
		var y0 := (c / COLS) * CELL
		var acc := Vector3.ZERO
		var k := 0.0
		for y in range(y0, y0 + CELL, 2):
			for x in range(x0, x0 + CELL, 2):
				var p := img.get_pixel(x, y)
				if p.a < 0.5:
					continue
				acc += Vector3(p.r, p.g, p.b)
				k += 1.0
		acc /= maxf(k, 1.0)
		var mx := maxf(acc.x, maxf(acc.y, acc.z))
		var mn := minf(acc.x, minf(acc.y, acc.z))
		var lum := acc.dot(Vector3(0.3, 0.59, 0.11))
		var sat := (mx - mn) / maxf(mx, 0.001)
		it["lum"] = snappedf(lum, 0.001)
		it["sat"] = snappedf(sat, 0.001)
		it["white"] = (lum > 0.5 and sat < 0.35) or c in REMOVE
		if it["white"]:
			n_white += 1
			print("белое: ячейка %d %s lum %.2f sat %.2f" % [c, it["kind"], lum, sat])
	var f := FileAccess.open(JSON_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	print("белых растений: ", n_white)
	quit()
