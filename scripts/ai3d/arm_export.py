"""Blender: экспорт руки со скелетом из assets/src/arm_rig.blend в игру (assets/ready/arm_fp.glb).
Usage: blender -b D:/77Days/assets/src/arm_rig.blend -P arm_export.py"""
import bpy

for o in bpy.context.scene.objects:
    o.select_set(o.type in ("MESH", "ARMATURE"))
# поза — в покой (в игру уходит только исходная поза; сгибы пальцев задаёт игра)
for o in bpy.context.scene.objects:
    if o.type == "ARMATURE":
        for pb in o.pose.bones:
            pb.location = (0, 0, 0)
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.rotation_euler = (0, 0, 0)
            pb.scale = (1, 1, 1)
bpy.ops.export_scene.gltf(filepath="D:/77Days/assets/ready/arm_fp.glb", export_format="GLB", use_selection=True,
                          export_skins=True, export_animations=False, export_yup=False,
                          export_image_format="JPEG", export_jpeg_quality=90)
print("EXPORTED arm_fp.glb")
