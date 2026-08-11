# PC Health

Монитор состояния Mac для macOS: температуры CPU и GPU, загрузка ядер, память, диски, сеть,
вентиляторы, питание и батарея. Плюс вкладка со **всеми** датчиками, которые машина отдаёт
через `IOHIDEventSystem` и `AppleSMC`.


## Требования

- macOS 14 или новее;
- Xcode 15+ (проверено на macOS 15.7.7, Xcode 26.3, Swift 6.2).

## Запуск

Из корня проекта:

```bash
make run
```

Команда соберёт сборку, упакует её в `.build/release/PC Health.app` и откроет.
Появится окно с дашбордом и иконка в меню-баре с текущей температурой.

Остальные команды:

```bash
make app          # только собрать бандл, не открывать
make install      # скопировать приложение в /Applications
make icon         # перерисовать иконку (Scripts/GenerateIcon.swift)
make screenshots  # пересобрать картинки для README
make clean        # удалить сборку
```

Через Xcode: `open Package.swift` — SwiftPM-пакет открывается как обычный проект. Запускать
всё равно лучше через `make run`: меню-бар и иконка в Dock работают только из `.app`-бандла,
а не из «голого» бинарника в `.build/`.


### Управление

- переключатель **°C / °F** и интервал опроса (1/2/5/10 с) — в тулбаре;
- **⌘R** — обновить сейчас, **⇧⌘P** — пауза/продолжить сбор;
- на вкладке **All sensors** — поиск по имени и SMC-ключу, фильтр по типу, экспорт в CSV.

### Без окна, прямо в терминале

```bash
make dump     # одно измерение текстом
make json     # то же самое в JSON — удобно для скриптов
make bench    # сколько миллисекунд занимает один опрос датчиков
```

```
Apple M4 — Mac16,13, macOS 15.7.7
4P + 6E · 10 threads, 24 GB RAM
sources: HID=true SMC=true

CPU      20.0%  user 12.7% sys 7.3%  load 3.89
GPU      25.0%  AGXAcceleratorG16G (10 cores)
Memory   84.2%  20,21 GB of 24 GB used, swap 5,47 GB
...
Hottest: TCMz — 81.4°C
Sensors found: 349
```

## Как выглядит

**Dashboard** — кольца загрузки и температур, графики, самые горячие датчики, питание, сеть и диск.

![Dashboard](docs/screenshots/dashboard.png)

**CPU** — загрузка по каждому ядру (сначала P-, затем E-ядра), температуры, load average, uptime.

![CPU](docs/screenshots/cpu.png)

**All sensors** — все найденные датчики по группам, с поиском, фильтром и экспортом в CSV.

![All sensors](docs/screenshots/sensors.png)

<details>
<summary><b>Остальные вкладки</b> — GPU, Memory, Storage, Network, Power &amp; Fans</summary>

**GPU** — утилизация, число ядер, видеопамять, температуры.

![GPU](docs/screenshots/gpu.png)

**Memory** — App / Wired / Compressed / Cached / Free, memory pressure, swap.

![Memory](docs/screenshots/memory.png)

**Storage** — скорость чтения и записи, заполненность томов, температуры накопителей.

![Storage](docs/screenshots/storage.png)

**Network** — скорость приёма/передачи и счётчики по интерфейсам.

![Network](docs/screenshots/network.png)

**Power & Fans** — потребление в ваттах, обороты вентиляторов, батарея, силовые линии SMC.

![Power & Fans](docs/screenshots/power.png)

</details>

Скриншоты лежат в [docs/screenshots/](docs/screenshots/) и пересобираются командой
`make screenshots` — приложение само отрисовывает свои вкладки с живыми показаниями.

Данные читаются напрямую из системы: `AppleSMC` и `IOHIDEventSystem` для датчиков,
`host_processor_info` для ядер, `IOAccelerator` для GPU, `host_statistics64` для памяти,
`getifaddrs` для сети, `IOPowerSources` для батареи. Подробности — в комментариях
к файлам в [Sources/PCHealth/Services/](Sources/PCHealth/Services/).

## Заметки

- **Только чтение.** Приложение ничего не пишет в SMC и не управляет вентиляторами.
- **Без App Sandbox.** Песочница закрывает доступ к `AppleSMC`, поэтому бандл собирается без неё.
- **Intel Mac.** Работает: там датчики отдаёт SMC, а `HID=false` в выводе — это норма.
- **Безвентиляторные модели.** На MacBook Air раздел Cooling пишет «Fanless / not reported».
- Опрос стоит ~70 мс, приложение с открытым окном занимает около 2-5 % CPU при интервале 2 с.
