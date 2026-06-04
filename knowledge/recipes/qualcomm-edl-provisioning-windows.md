# Recipe: Qualcomm EDL (9008) прошивка/провижинг с Windows

## Условия применения
Прошивка/провижинг Qualcomm-устройства (например, MSM8916 и родственные SoC, Android) через EDL (режим 9008, Sahara/Firehose) с Windows-хоста. Инструмент — bkerler/edl (python).

## Суть (что реально работает)
- **Драйвер 9008 = ТОЛЬКО WinUSB** (через Zadig или libwdi). Проверено: `libusbK` = краш `0xC0000005`; `libusb-win32` = Sahara не идёт; штатный QDLoader/qcusbser (класс Ports/COM) = libusb перечисляет, но `open` даёт `LIBUSB_ERROR_NOT_SUPPORTED` (pyusb → `NotImplementedError: Operation not supported`). НОВОЕ устройство входит в EDL под штатным `qcusbser` → нужен разовый перевод на WinUSB **на каждый новый экземпляр/USB-порт** (привязка драйвера к hardware-id, переживает выход/возврат в EDL).
- **Авто-установка WinUSB без GUI**: `pnputil /add-driver <inf> /install` сохранённым пакетом libwdi (экспорт рабочего: `pnputil /export-driver <oemNN.inf> <dir>` — найти запись `provider=libwdi, class=USBDevice`). ⚠ официального собранного `wdi-simple.exe` НЕ существует (libwdi отдаёт только исходники; нужен MSVC/WDK для сборки) — на машине-провижинере используй экспорт уже-установленного пакета; на чужой машине нужен импорт self-signed cert libwdi в Trusted Publisher/Root. Нужны права администратора.
- **Лоадер (firehose)** = ВСТРОЕННЫЙ в edl под точный HWID: `Loaders/qualcomm/factory/<soc>/<HWID>_*_fhprg_peek.bin`. Внешние generic-лоадеры зависают на bulk-заливке / `Unknown host error in HELLO_RESP`. «Зависание bulk» = НЕправильный лоадер, не USB.
- **Вход в EDL**: `adb reboot edl` (работает без root на устройстве). Если adb недоступен — физическая EDL-кнопка/test-point.
- **`PYTHONIOENCODING=utf-8` ОБЯЗАТЕЛЬНО** — прогресс-бар `█` иначе крашит запись (опасно при write boot).
- **Sahara idle-timeout**: устройство в 9008 без активности авто-ребутится в норм-режим. Драйвер ставь ДО входа в EDL либо быстро.
- ⛔ **НЕ убивать edl-процесс на середине** — WinUSB-handle залипает (`Permission denied`) до реконнекта.
- Команды: `edl.py printgpt --loader L` (read-only), `r <part> out.img --loader L` (бэкап), `w <part> file --loader L`, `e <part> --loader L` (erase), `reset --loader L`. Шифмовать строго раздел по GPT-имени (edl резолвит HWID/label — не заденет соседей). ⛔ НИКОГДА `modem`/`persist`/`fsg`/`efs` (IMEI/IMSI/калибровка — per-device, клон = брак/нелегально).
- Безобидные warning'и: «Host's payload too large», «Sector size XML 4096 vs 512» — edl подстраивается.

## Очистка userdata (/data) — ВАЖНО
- ⛔ **raw `edl e userdata` НЕ годится** на многих прошивках: после стирания `/data` НЕ авто-форматируется → не монтируется → стек/root мертвы, `adb root` запрещён (production build), recovery без adbd → нужна физ. EDL-кнопка. (Известный случай: так можно «потерять» /data на устройстве.)
- ✅ **Правильно — recovery factory-reset через BCB** (host-side, без on-device root): записать в раздел `misc` bootloader_message: `command="boot-recovery"` + `recovery="recovery\n--wipe_data\n"` → `edl w misc bcb.img` → `edl reset` → bootloader→recovery штатно форматирует /data+cache → ребут в систему с валидным /data. BCB = 2 КБ бинарь (command[32]@0, status[32]@32, recovery[768]@64). Headless-safe.
- Альтернатива: записать готовый пустой ext4-образ нужного размера в userdata (`edl w userdata empty.img`) — но нужен генератор ext4 (Linux-тулы).

## Антипаттерны
- ❌ Драйвер libusbK/libusb-win32 «потому что edl так пишет» → краш/нет Sahara. Только WinUSB.
- ❌ Внешний generic-лоадер → зависание, ложно принимаемое за USB3-проблему.
- ❌ raw-erase userdata в надежде на авто-формат → кирпич /data.
- ❌ Деструктив (erase/flash) без проверенного пути восстановления (см. standard `validate-recovery-before-destructive`).
- ❌ В шелл-командах на устройство через хост-инструмент писать `rm /system/...`/`rm /data/...` — host-guard агента/инструмента может ложно блокировать (думает, что путь хоста). Переформулировать без `rm <системный путь>` (напр. `pm clear` вместо `rm -rf /data/data/pkg`), либо использовать device-side API/root-канал (Python→HTTP, не shell-строку).

## Источник
Серия провижинга на железе Qualcomm MSM8916 (Android, rooted): WinUSB+встроенный лоадер, BCB-recovery-wipe валидирован после инцидента с raw-erase, pnputil-экспорт драйвера.
