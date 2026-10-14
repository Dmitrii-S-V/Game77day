class_name ChunkData
extends RefCounted
## Данные одного чанка: плотность (>0 = твёрдое) и материал в каждом узле сетки.

var dens := PackedFloat32Array()
var mat := PackedByteArray()
var edited := false
