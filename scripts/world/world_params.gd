class_name WorldParams
extends RefCounted
## Параметры генерации мира (меню "Новый мир").

var seed_value := 1337
var size := 2048          # кратно 1024
var towns := 8
var pois := 12
var rivers := 3
var lakes := 4
var pct_mountain := 20
var pct_hill := 30
var pct_plain := 50
var pct_burn := 18        # доля карты — биом «выжженная земля»


## Доли гор / холмов / равнин, нормированные к сумме 1 (x = горы, y = холмы, z = равнины).
func shares() -> Vector3:
	var s := float(pct_mountain + pct_hill + pct_plain)
	if s <= 0.0:
		return Vector3(0.2, 0.3, 0.5)
	return Vector3(pct_mountain / s, pct_hill / s, pct_plain / s)


static func seed_from_text(txt: String) -> int:
	var t := txt.strip_edges()
	if t.is_empty():
		return 1337
	if t.is_valid_int():
		return t.to_int()
	return absi(hash(t)) % 2000000000


func summary() -> String:
	return "seed %d, %d м, города %d, POI %d, реки %d, озёра %d, горы/холмы/равнины %d/%d/%d%%" % [
		seed_value, size, towns, pois, rivers, lakes, pct_mountain, pct_hill, pct_plain]
