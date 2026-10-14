class_name ColumnInfo
extends RefCounted
## Данные колонки 16x16 м (по размеру чанка): итоговая высота, материал покрытия
## (0 = естественный, иначе дорога/площадка) и флаг "занято" (дорога, город) для растительности.

var h := PackedFloat32Array()
var mat := PackedByteArray()
var blocked := PackedByteArray()
