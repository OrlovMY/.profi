# Recipe: Qualcomm EDL (9008) провижинг с macOS

## Условия применения
Провижинг Qualcomm-устройства через EDL (9008, Sahara/Firehose) с **macOS-хоста** инструментом `bkerler/edl` (python). Парный к Windows-рецепту [[qualcomm-edl-provisioning-windows]] — те же инварианты по разделам/лоадеру/BCB, отличается ТОЛЬКО хост-настройка. Валидировано на UFI MSM8916 / Android 4.4.4, провижинер `USB-Dongle-UFI/tools/provisioner/provision.py` (2026-06-20, dry-run end-to-end).

## Главное отличие от Windows: драйвер НЕ нужен
- **WinUSB/Zadig/pnputil/libwdi — НЕ применимы и НЕ нужны.** На macOS libusb открывает интерфейс 9008 напрямую. В `provision.py` `_edl_driver_service()` на не-Windows возвращает `"winusb"` без проверки — гард драйвера пропускается. Это убирает весь самый хрупкий слой Windows-провижина.

## Зависимости хоста (brew)
```
brew install android-platform-tools   # adb
brew install lsusb                     # ⚠ обязателен: provision.py зовёт `lsusb` для детекта 9008 (на macOS его нет из коробки)
brew install libusb                    # нужен edl для USB
brew install python@3.12               # ⚠ edl-deps НЕ собираются на 3.13+ (pyusb/capstone/keystone)
brew install go                        # для сборки api_server (ARMv7)
```

## edl + изолированный venv (КРИТИЧНО для двух граблей)
```
git clone --depth 1 https://github.com/bkerler/edl tools/edl
cd tools/edl && git submodule update --init      # тянет Loaders/ с рабочим firehose
python3.12 -m venv .venv
.venv/bin/pip install -r requirements.txt         # pyusb, pyserial, pycryptodome, capstone, keystone-engine, certifi, …
.venv/bin/python edl.py --help                    # smoke: должен показать Usage
```

### Грабля 1 — venv-python, НЕ системный python3
`provision.py` вызывает edl через `sys.executable`. Значит **сам provision.py надо запускать тем питоном, где стоят edl-deps** (venv 3.12), иначе edl упадёт на отсутствии pyusb. brew-python3 по умолчанию = свежий (3.13+), где deps не собираются. Раннер `provision-macos.sh` (с 1.9) сам предпочитает `tools/edl/.venv/bin/python`, если он есть.

### Грабля 2 — SSL CERTIFICATE_VERIFY_FAILED при fetch APK
brew-Python не видит системный CA-стор → `urllib` падает `CERTIFICATE_VERIFY_FAILED` на fetch APK/админки с сервера. Фикс: направить urllib на бандл `certifi` (он ставится как зависимость edl):
```
export SSL_CERT_FILE=$(.venv/bin/python -m certifi)
```
`provision.py` (с 1.9) делает это сам при старте, если `SSL_CERT_FILE` не задан и `certifi` импортируется — отдельная установка не нужна.

## Сборка api_server (ARMv7)
```
cd replacement
CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 go build -trimpath -ldflags='-s -w' -o build/api_server .
```
⚠ Собирать **весь пакет** (`.`), НЕ `server.go` — логика разнесена (`device_pwd.go`/`emmc_health.go`/`net_policy.go`).

## Канонная команда (Mac)
```
cd USB-Dongle-UFI/tools/provisioner
./provision-macos.sh --no-gui --yes --code <10-знач-код-тенанта>          # DRY-RUN (по умолчанию)
./provision-macos.sh --no-gui --yes --code <код> --commit                 # БОЕВОЙ (реальный flash)
```
Раннер сам берёт venv-python и ставит SSL_CERT_FILE. `--check` — только проверка зависимостей.

## Пре-флайт живого модема
- Питание **≥2 A** (powered-hub / Y-кабель). На 500 mA порту LTE-радио даёт брауноут → USB/adb рвётся посреди провижина (паспорт `usb-power-flap`).
- Вход в EDL: выключить модем → вскрыть корпус → зажать EDL-кнопку → вставить USB удерживая. Проверка: `lsusb | grep -i 05c6:9008`.
- Перед `--commit` полезно read-only сверить профиль: `.venv/bin/python ../edl/edl.py printgpt --loader <fhprg_peek.bin> --memory eMMC` → HWID/sector должны совпасть с `known_devices.json` (провижинер сам делает это в device_profile_guard и СТОП при расхождении).

## Пост-проверка (после успешного провижина)
- Агент в логах: `CpeApiClient checkin admin_snapshot` + LTE up (`NetworkController connected={data}`) = энролл состоялся.
- В MDMy-админке у устройства `admin_build` должен равняться build развёрнутой админки (напр. 26), **НЕ 0**. Если 0 — провижинер <1.10 не писал `/data/local/tmp/BUILD` (его читает `api_server otaReadBuild()`); при провижине OTA не было → маркер отсутствовал. Фикс: provisioner ≥1.10 пишет `BUILD` в `deploy_stack`; на уже-провиженном устройстве — `adb shell "echo <build> > /data/local/tmp/BUILD"`.
- adb после провижина периодически рвётся (USB-композит `rndis,adb` пере-композируется) — `adb kill-server && adb start-server`.

## Грабли провижина (уроки live-сессии 2026-06-20/21)
- **vendor-cleanup ДОЛЖЕН ждать api_server + верифицировать.** Шаг чистки вендор-апов идёт через root-канал api_server; после ребута регистрации priv-app api_server может быть ещё не поднят → `pm disable` молча не выполняется, вендор-апы остаются, а лог ложно говорит «отключено N». Фикс (provisioner ≥1.11): `_wait_api()` + проверка `pm list packages -d` + честный отчёт. Общий принцип: **любой шаг через api_server сначала дожидается его готовности и верифицирует результат, не репортит успех вслепую.**
- **AP-SSID меняется только серверным `setWifiConfig` (hostapd), НЕ агентской `wifi_config`** — последняя на CPE идёт через `WifiManager` (station-режим) и конфликтует с hostapd-AP (два hostapd за wlan0). Не путать каналы.
- **Термо-потолок UFI — аппаратный.** Под сустейн-нагрузкой thermal-engine душит CPU 800→200 МГц → разом отваливаются админка/ICMP/WAN, само-recovery при остывании. Софт-throttle download'а на этом ядре НЕвозможен (нет ifb/ingress-police; br0=noqueue, wlan0=mq, renice не берётся). Лечится только охлаждением. Не диагностировать перегрев как «падение стека/сети» (LED: красный строб).
- **adb после провижина периодически рвётся** (USB-композит rndis,adb) — `adb kill-server && adb start-server`. Не путать с «устройство умерло».

## Hard rules (как и на Windows)
- Прошивать ТОЛЬКО `boot`; ⛔ НИКОГДА modem/persist/fsg/efs (IMEI).
- Чистка /data — ТОЛЬКО BCB→recovery (`--wipe`), не raw-erase.
- Flash/reboot — ТОЛЬКО на модеме. Тест на железе — с владельцем, он флэшит сам.
- read-back-verify после записи; профиль-guard перед записью (шить только known_devices).

## Источник
USB-Dongle-UFI provisioner, валидация на Mac (macOS 12, Intel) 2026-06-20: brew-deps + venv(3.12) + api_server ARMv7. Провижинер доведён до 1.9 (авто-SSL + venv-раннер).
**Live `--commit` подтверждён end-to-end на железе** (свежий сток UFI, adb-serial `2303f575`, EDL HWID `0x007050e1`, код тенанта 10-знач.): EDL→profile-guard MATCH→flash boot+read-back verify→deploy→priv-app APK (vc47)→agent (uid=system)→**checkin на сервер по LTE (Beeline 4G)** = энролл состоялся. Грабли в окне верификации провижинера (api_server поднялся >240с + adb-флап на ре-энумерации USB rndis,adb) — НЕ реальный фейл: перепроверка через ~2 мин показала `LIVE=ok:uid0` + `CpeApiClient checkin`. На Mac post-provision adb периодически рвётся (USB-композит rndis,adb) — лечится `adb kill-server && adb start-server`.
