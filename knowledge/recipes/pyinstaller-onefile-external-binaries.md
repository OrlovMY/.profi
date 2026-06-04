# Recipe: PyInstaller onefile — упаковка Python-инструмента + внешние бинари/DLL/данные

## Условия применения
Нужен один `.exe` (Windows) из Python-CLI/GUI, который тащит с собой сторонние утилиты (внешние CLI-бинарники, прошивки, образы, архивы, нативные .dll-бэкенды). Оператору даём один файл.

## Суть (рабочая последовательность)
1. **`.spec`-файл, запуск из КОРНЯ проекта** (пути в spec — относительно cwd):
   `pyinstaller --noconfirm --distpath out/dist --workpath out/build tools/build.spec`
   ⚠ ВСЕГДА указывай `--distpath` — по умолчанию PyInstaller кладёт exe в `./dist`, затирая/засоряя рабочую папку (частая грабля, особенно если там лежит вшиваемый артефакт).
2. **Внешние бинарники** (`adb.exe`, утилита) → в `binaries=[(src, '.')]` (корень бандла) или `datas` если запускаешь как внешний процесс (не загружаешь как модуль).
3. **Нативные DLL-бэкенды** (libusb-1.0.dll и т.п.): положить в КОРЕНЬ бандла (`binaries.append((dll, '.'))`) + **runtime-hook**, добавляющий `sys._MEIPASS` в DLL-search-path, иначе `NoBackendError`/не найдётся:
   ```python
   # rthook_libusb.py
   import os, sys
   if hasattr(sys, '_MEIPASS'): os.add_dll_directory(sys._MEIPASS)
   ```
   В spec: `EXE(..., runtime_hooks=['tools/rthook_libusb.py'])`.
4. **Данные** (образы/архивы/скрипты/лоадеры) → `datas=[(src, dest_subdir)]`. Резолв в коде:
   ```python
   FROZEN = getattr(sys, 'frozen', False)
   def res(*p): return os.path.join(sys._MEIPASS if FROZEN else REPO, *p)
   ```
5. **Вшитый CLI-инструмент без отдельного python** (onefile = один интерпретатор): пере-вход в СЕБЯ.
   `[sys.executable, '__tool__'] if FROZEN else [sys.executable, 'tool.py']`; в `main()`:
   `if sys.argv[1]=='__tool__': sys.argv=['tool.py']+sys.argv[2:]; runpy.run_path(TOOL_PY, run_name='__main__')`.
6. **GUI-режим**: `console=False` (windowed) — но тогда stdout может быть None: оборачивай `print` в try/except, лог через GUI-callback.
7. **UTF-8 окружение** для дочерних процессов с прогресс-барами: выставь `PYTHONIOENCODING=utf-8`/`PYTHONUTF8=1` и читай вывод `subprocess.run(..., encoding='utf-8', errors='replace')` — иначе символы рамок/`█` крашат запись под cp1252 (RU-Windows).
8. **Проверка бандла без запуска GUI** (что всё вшито):
   ```python
   from PyInstaller.archive.readers import CArchiveReader
   names=list(CArchiveReader('app.exe').toc.keys())
   ```
   + извлечение файла из exe для сверки sha256 (`r.extract('name')`).

## Антипаттерны
- ❌ Сборка без `--distpath` → exe падает в `./dist` рядом с вшиваемым артефактом, путаница/мусор.
- ❌ DLL только в `datas` без rthook → backend не находится в рантайме.
- ❌ Полагаться на системный пакет (напр. `usb1`) — `Hidden import 'usb1' not found` норма, если используешь альтернативный бэкенд; не паникуй, но проверь что РАБОЧИЙ бэкенд вшит.
- ❌ Тестировать только `--help` у windowed-exe (stdout None) — проверяй инспекцией PKG или dry-run.
- ❌ Считать «собралось = работает на железе»: real I/O (USB-flash и т.п.) через frozen-exe тестируй отдельно — пути/бэкенды во frozen ведут иначе.

## Источник
Подтверждено на практике: onefile-exe с вшитым CLI-инструментом (пере-вход через `__tool__`), внешними бинарниками (adb), нативным libusb-бэкендом (rthook), образами и архивами в datas (~41 МБ). Подводные камни: грабля `--distpath`, UTF-8 для прогресс-бара дочернего процесса.
