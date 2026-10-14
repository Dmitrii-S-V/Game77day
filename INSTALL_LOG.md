# INSTALL_LOG: пайплайн генерации 3D-ассетов

Проект Godot: `D:\77Days` (вместо `D:\project` из ТЗ). Диск C почти полный, всё на D:.

## Пути

- Python 3.11 (uv): `D:\ai3d\python\cpython-3.11-windows-x86_64-none\python.exe`
- Python для ComfyUI: `D:\ai3d\ComfyUI\venv\Scripts\python.exe`
- Python для SF3D: (ещё не создан)
- ComfyUI: `D:\ai3d\ComfyUI`, порт 8188, запуск `--force-fp32 --lowvram`
- Blender: `D:\ai3d\blender\blender.exe` (4.5.14 LTS portable)
- Godot: `C:\Godot\godot.exe` (4.7.2 stable)
- Проект: `D:\77Days`
- Кэши: `D:\ai3d\cache\{uv,pip,hf,torch}`. Перед работой задавать `UV_CACHE_DIR`, `PIP_CACHE_DIR`, `HF_HOME`, `TORCH_HOME`.

## Этап 0: база (OK)

GPU P106-100 6 ГБ (драйвер 582.66), git 2.56, uv 0.12.23, Godot 4.7.2.
Нет: Python 3.11 (поставлен через uv), MSVC, CUDA Toolkit (нужны для SF3D, см. Этап 3).
Диск: C 9 ГБ, D 98 ГБ, E 176 ГБ.

## Этап 1: Blender, Python 3.11 (OK)

- `blender.exe -b --version` -> Blender 4.5.14 LTS.
- Python 3.11.17 через `uv python install 3.11` в `D:\ai3d\python`.

## Этап 2: ComfyUI (OK)

Запуск (в фоне, PowerShell):
`D:\ai3d\ComfyUI\venv\Scripts\python.exe main.py --force-fp32 --lowvram --disable-pinned-memory --disable-auto-launch --listen 127.0.0.1 --port 8188` (cwd `D:\ai3d\ComfyUI`, `HF_HOME`/`TORCH_HOME` на D:).

Найденные проблемы и решения:
- `--disable-dynamic-vram` НЕ использовать: safetensors открывает 6,9 ГБ через `from_file(shared=False)`, это съедает commit-память, на ПК commit почти исчерпан (30,9 из 38,7 ГБ: Unity, Godot и др.), падает с access violation. Рабочий вариант: DynamicVRAM включён + `--disable-pinned-memory` (без него 12,6 ГБ pinned тоже роняют).
- fp32 SDXL не помещается в 6 ГБ, веса стримятся: ~30 с на шаг при 896 px. Поэтому workflow 768x768, 20 шагов (~8-10 мин на картинку). Pascal fp16 медленный (1/64), fp32 обязателен.
- rembg по умолчанию качает bria-rmbg 1 ГБ (некоммерческая лицензия) с GitHub со скоростью 50 КБ/с. Вместо этого `isnet-general-use` (Apache 2.0) из HF-зеркала в `D:\ai3d\cache\u2net\`. Его MD5 (80bb0d66...) не совпадает с пином rembg (fc16ebd8...), два зеркала дают одинаковые байты, формат ONNX (код не исполняется), `MODEL_CHECKSUM_DISABLED=1`.
- Фон удаляется в `gen_image.py` (rembg на CPU), а не нодой в ComfyUI. Workflow: `workflows\txt2img_api.json` (SaveImage, node "7").
- Чекпоинт RealVisXL_V4.0 проверен по SHA256 с HF.

Тест: `scripts\ai3d\gen_image.py --only street_lamp --seed 1234` -> `assets\ai3d_src\street_lamp_color.png` и `street_lamp_nobg.png`. Картинка не чёрная, фонарь целиком, вырез чистый.

## Этап 3: Stable Fast 3D (в процессе)

- Репозиторий склонирован в `D:\ai3d\stable-fast-3d`.
- `texture_baker/setup.py` падает на CPU-сборку при отсутствии CUDA_HOME, значит **CUDA Toolkit не нужен**. Нужен MSVC Build Tools (C++), нужны права администратора.
- MSVC Build Tools 14.44 + SDK 10.0.22621 установлены в `D:\VSBuildTools` (пользователь).
- venv: `D:\ai3d\stable-fast-3d\venv` (Python 3.11, torch 2.14.1+cu126, setuptools 69.5.1). Python для SF3D: `D:\ai3d\stable-fast-3d\venv\Scripts\python.exe`.
- Зависимости по requirements.txt (rembg CPU вместо rembg[gpu]).
- Расширения `uv_unwrapper` и `texture_baker` собраны в CPU-режиме скриптом `D:\ai3d\stable-fast-3d\install_deps.bat`. Три грабли:
  1. torch 2.14 требует C++20: `set CL=/std:c++20`.
  2. Не определялся `TORCH_EXTENSION_NAME`, модуль получал `PyInit_TORCH_EXTENSION_NAME`: `/DTORCH_EXTENSION_NAME=_C` в `CL`.
  3. Перед пересборкой удалять `build\` и `*.egg-info` расширений (иначе берутся старые .obj).
- Проверка: `import uv_unwrapper, texture_baker, sf3d.system` проходит.
- HF логин выполнен пользователем (аккаунт slavade), токен в файлах не хранится. Модель кэшируется в `D:\ai3d\cache\hf`.
- `texture_baker` CPU-only: в `gen_mesh.py` rasterize/interpolate обёрнуты на CPU, инференс на CUDA. 34 с на объект, пик VRAM около 6,1 ГБ (на пределе). fp32 без autocast.
- `run.py` из репозитория не используется (он тянет rembg с GitHub и bf16): свой `scripts\ai3d\gen_mesh.py` берёт готовый вырез.

## Этапы 4-5: скрипты и тест (OK)

Скрипты в `D:\77Days\scripts\ai3d\`:
- `gen_image.py` (python ComfyUI-venv, нужен запущенный ComfyUI), `gen_mesh.py` (python SF3D-venv, ComfyUI выключен), `process.py` + `blender_process.py`, `check.py`, `import_godot.ps1`, `verify_godot.gd`, `run_batch.py`.
- Blender-превью: Workbench, нужен `--gpu-backend vulkan` (OpenGL в -b падает: "No OpenGL vendor detected"). Пути в Blender передавать абсолютными.
- Выходы: `assets\ai3d_src` (картинки), `assets\raw`, `assets\ready`, `assets\preview`, лог `batch_log.md`.

Запуск пакета (сам стартует и останавливает ComfyUI, до 3 попыток с новым seed):
`D:\ai3d\python\cpython-3.11-windows-x86_64-none\python.exe D:\77Days\scripts\ai3d\run_batch.py [objects.json] [--only a,b]`

Результат теста street_lamp (seed 1234, prop_large, cells 1x4x1), весь путь одной командой run_batch.py:
- check.py: 3992 треугольника (бюджет 12000), габариты 0,652 x 3,9 x 0,688 м, y_min=0, UV да, текстура да (средняя яркость 39), флагов нет.
- Godot 4.7.2: импорт OK, AABB (0,652; 3,9; 0,688), min y = 0, uv=true, albedo_texture=true.
- Превью: `assets\preview\street_lamp_{front,side,persp}.png`.

Известные замечания: `C:\assets\preview\` создан по ошибке тестовым запуском с относительным путём (3 PNG), удалить вручную (скрипт не смог, путь защищён). Godot рядом с .glb создаёт `*_0.jpg`/`*_Image_0.jpg` (извлечённые текстуры при импорте).

- venv + torch 2.14.1+cu126, `cuda.is_available()=True`, P106-100, capability (6,1), matmul на GPU работает (нет `no kernel image`).
- ComfyUI-Manager, rembg-comfyui-node, ComfyUI-seamless-tiling в `custom_nodes`.
- rembg 2.0.85 + onnxruntime 1.30 (CPU, не занимает VRAM) в venv ComfyUI.
- Чекпоинт: RealVisXL_V4.0.safetensors (6,46 ГБ, HF SG161222, без входа). Скачивание с докачкой через curl.
