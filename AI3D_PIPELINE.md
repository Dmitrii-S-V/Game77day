# AI3D: генерация 3D-пропсов для 77Days (памятка для других диалогов)

Локальный пайплайн, уже установлен и проверен. Подробности установки и грабли: `INSTALL_LOG.md`.

## Что делает
`промпт -> картинка (ComfyUI, SDXL) -> вырез фона (rembg) -> Stable Fast 3D -> Blender (упрощение, нормали, подгонка под ячейки, превью) -> .glb в проекте Godot`

Результат: `assets/ready/<name>.glb` (с UV и текстурой), превью `assets/preview/<name>_{front,side,persp}.png`, лог `batch_log.md`.

## Запуск пакета
1. Описать объекты в `D:\77Days\objects.json`:
```json
[{"name": "street_lamp",
  "prompt": "old street lamp post, rusty metal, full length, entire object visible from base to top, single object, centered, plain white background, 3/4 view, soft studio lighting, game asset",
  "kind": "prop_large", "cells": [1, 4, 1], "seed": 1234}]
```
`kind`: `prop_small` (до 2000 треуг.), `prop_medium` (5000), `prop_large` (12000). `cells` в осях Godot: [x, y (вверх), z], 1 ед. = 1 м = 1 блок. Поле `seed` необязательно.

2. Запустить (сам поднимает и останавливает ComfyUI, до 3 попыток с новым seed на плохих результатах):
```
D:\ai3d\python\cpython-3.11-windows-x86_64-none\python.exe D:\77Days\scripts\ai3d\run_batch.py [objects.json] [--only a,b] [--attempts 3] [--no-import]
```
Время: картинка около 8-10 минут, меш около 35 секунд. Конец прогона: `Summary: ready=N failed=M`, затем импорт в Godot.

## Скрипты (`D:\77Days\scripts\ai3d\`)
| Файл | Роль | Python |
|---|---|---|
| `gen_image.py` | промпт -> картинка + вырез фона (ComfyUI должен быть запущен) | `D:\ai3d\ComfyUI\venv\Scripts\python.exe` |
| `gen_mesh.py` | картинка -> `assets/raw/<name>.glb` (ComfyUI выключен) | `D:\ai3d\stable-fast-3d\venv\Scripts\python.exe` |
| `process.py` + `blender_process.py` | Blender: decimate, нормали, масштаб в ячейки, origin по центру низа, превью | любой / blender |
| `check.py` | отчёт: треугольники, габариты, UV, текстура, флаги (код 1 при проблемах) | python SF3D |
| `import_godot.ps1`, `verify_godot.gd` | импорт в Godot и проверка AABB | godot |
| `run_batch.py` | оркестратор всего | любой |

Пути: Blender `D:\ai3d\blender\blender.exe` (4.5.14), Godot `C:\Godot\godot.exe` (4.7.2), ComfyUI `D:\ai3d\ComfyUI`, SF3D `D:\ai3d\stable-fast-3d`.

## Свои картинки (ChatGPT, Nano Banana и т. д.)
Положить непрозрачный PNG в `assets/ai3d_src/<name>_color.png` и запускать `gen_image.py` без `--force` (вырежет фон и пропустит ComfyUI). `run_batch.py` пока всегда перерисовывает локально: поле `"image"` для внешних файлов не реализовано.
Требования к картинке: один предмет целиком, ровный белый фон, без пола и теней, вид 3/4, от 768 px.

## Ограничения
- SF3D принимает ОДНУ картинку. Лист ракурсов или коллаж даёт мусор. Мультивью только через Hunyuan3D-2mv (не установлен, на 6 ГБ под вопросом).
- Куча мусора и подобные сцены: генерировать отдельные пропсы, собирать кодом (идея `compose.py`: разброс с поворотами и опционально Blender-физика, объединение в один .glb или `MultiMeshInstance3D` в Godot). Пока не реализовано.
- ComfyUI и SF3D никогда одновременно (6 ГБ VRAM, P106-100, только fp32).
- ComfyUI запускать только с `--force-fp32 --lowvram --disable-pinned-memory` (DynamicVRAM включён). Память ПК почти на пределе: при `access violation` закрыть лишнее.
- Blender-превью требуют `--gpu-backend vulkan` и абсолютных путей.
- Токен Hugging Face в файлах не хранится (логин делал пользователь).
