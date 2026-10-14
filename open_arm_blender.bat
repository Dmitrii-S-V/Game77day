@echo off
rem Открыть руку со скелетом в Blender. Vulkan — потому что монитор на Intel HD 4000 (нет OpenGL 4.3), а рисует P106.
start "" "D:\ai3d\blender\blender.exe" --gpu-backend vulkan "D:\77Days\assets\src\arm_rig.blend"
