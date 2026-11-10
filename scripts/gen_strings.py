#!/usr/bin/env python3
"""Generates Sources/Islet/Resources/Localizable.xcstrings (en + ru).

The .xcstrings file is the source of truth shipped with the app; this script
just keeps it easy to edit. Each entry: key -> (comment, en, ru).
Plural entries use dicts of CLDR categories.
"""
import json, os

S = {
    # Menu bar
    "menu.expand": ("Status menu: open the island panel", "Expand Island", "Развернуть островок"),
    "menu.collapse": ("Status menu: close the island panel", "Collapse Island", "Свернуть островок"),
    "menu.settings": ("Status menu", "Settings…", "Настройки…"),
    "menu.about": ("Status menu", "About Islet", "Об Islet"),
    "menu.quit": ("Status menu", "Quit Islet", "Выйти из Islet"),
    "menu.hidden": ("Status menu: island hidden because the screen has no room", "Island hidden: not enough space", "Островок скрыт: недостаточно места"),
    # Accessibility
    "a11y.expand": ("VoiceOver hint / tooltip on the compact island", "Click to expand", "Нажмите, чтобы развернуть"),
    "a11y.collapse": ("Collapse button label", "Collapse", "Свернуть"),
    # Modules
    "module.clock": ("Module name", "Clock", "Часы"),
    "module.media": ("Module name", "Now Playing", "Сейчас играет"),
    "module.timer": ("Module name", "Timer", "Таймер"),
    "module.battery": ("Module name", "Battery", "Аккумулятор"),
    "module.shelf": ("Module name: temporary file shelf", "Shelf", "Полка"),
    "clock.week": ("Label above ISO week number", "Week", "Неделя"),
    "media.nothing": ("Empty state", "Nothing playing", "Ничего не играет"),
    "media.hint": ("Empty state detail", "Start music in Apple Music or Spotify.", "Включите музыку в Apple Music или Spotify."),
    "media.playing": ("Playback state", "Playing", "Играет"),
    "media.paused": ("Playback state", "Paused", "Пауза"),
    "timer.start": ("Button", "Start", "Старт"),
    "timer.pause": ("Button", "Pause", "Пауза"),
    "timer.reset": ("Button", "Reset", "Сброс"),
    "timer.done": ("Timer finished", "Time's up", "Время вышло"),
    "timer.minutes": ("Preset button; %d = minutes", "%d min", "%d мин"),
    "battery.charging": ("Battery state", "Charging", "Заряжается"),
    "battery.plugged": ("Battery state", "Connected to power", "Подключено к питанию"),
    "battery.onBattery": ("Battery state", "On battery", "От аккумулятора"),
    "battery.none": ("No internal battery", "No battery", "Нет аккумулятора"),
    "shelf.empty": ("Empty shelf title", "Drop files here", "Перетащите файлы сюда"),
    "shelf.hint": ("Empty shelf detail", "Files stay on the shelf until you drag them out or quit.", "Файлы лежат на полке, пока вы их не перетащите или не закроете приложение."),
    "shelf.clear": ("Button", "Clear", "Очистить"),
    "shelf.reveal": ("Context menu", "Show in Finder", "Показать в Finder"),
    "shelf.remove": ("Context menu / VoiceOver action", "Remove from Shelf", "Убрать с полки"),
    "shelf.count": ("Number of files on the shelf; %d = count",
                    {"one": "%d file", "other": "%d files"},
                    {"one": "%d файл", "few": "%d файла", "many": "%d файлов", "other": "%d файла"}),
    # Splash
    "splash.tagline": ("Splash subtitle", "A quiet island for your Mac", "Тихий островок для вашего Mac"),
    "splash.madeBy": ("Splash credit; %@ = author handle", "made by %@", "сделано %@"),
    # Settings
    "settings.title": ("Window title", "Settings", "Настройки"),
    "settings.appearance": ("Sidebar", "Appearance", "Оформление"),
    "settings.language": ("Sidebar", "Language", "Язык"),
    "settings.display": ("Sidebar", "Display", "Дисплей"),
    "settings.behavior": ("Sidebar", "Behavior", "Поведение"),
    "settings.about": ("Sidebar", "About", "О программе"),
    "appearance.theme": ("Section header", "Theme", "Тема"),
    "theme.obsidian": ("Theme name", "Obsidian", "Обсидиан"),
    "theme.pearl": ("Theme name", "Pearl", "Жемчуг"),
    "theme.adaptive": ("Theme name", "Adaptive", "Адаптивная"),
    "appearance.wallpaper": ("Toggle", "Use wallpaper color in Adaptive", "Брать цвет из обоев для «Адаптивной»"),
    "appearance.wallpaper.hint": ("Toggle hint", "Album artwork comes first, then the wallpaper of the island's screen, then the base palette.", "Сначала обложка, затем обои экрана островка, затем базовая палитра."),
    "appearance.preview": ("Section header", "Preview", "Превью"),
    "appearance.opaque": ("Shown when Reduce Transparency is on", "Reduce Transparency is on: surfaces are solid.", "Включено «Уменьшить прозрачность»: поверхности непрозрачные."),
    "language.system": ("Language option", "Same as System", "Как в системе"),
    "language.note": ("Language hint", "Only complete translations are listed. The choice applies immediately.", "Показаны только полные переводы. Выбор применяется сразу."),
    "display.choose": ("Picker label", "Show island on", "Показывать островок на"),
    "display.auto": ("Picker option", "Automatic", "Автоматически"),
    "display.note": ("Hint", "Automatic prefers a screen with a camera notch, then the main screen. If the chosen display is disconnected, Islet switches back and restores it on reconnect.", "Автоматически выбирается экран с вырезом, затем основной. Если выбранный дисплей отключён, Islet вернётся к автовыбору и восстановит его при подключении."),
    "display.status.notch": ("Status", "Notch detected: island sits under the camera housing.", "Вырез найден: островок под камерой."),
    "display.status.floating": ("Status", "No notch: island floats as a capsule.", "Выреза нет: островок — плавающая капсула."),
    "display.status.unknown": ("Status", "Screen geometry unknown: using the floating capsule.", "Геометрия неизвестна: плавающая капсула."),
    "display.status.hidden": ("Status", "Not enough room: island is hidden, use the menu bar.", "Мало места: островок скрыт, используйте меню."),
    "behavior.preview": ("Toggle", "Preview on hover", "Предпросмотр при наведении"),
    "behavior.delay": ("Slider label; %d = milliseconds", "Hover delay: %d ms", "Задержка наведения: %d мс"),
    "behavior.splash": ("Toggle", "Show splash screen at launch", "Показывать заставку при запуске"),
    "behavior.shortcut": ("Hint", "⌃⌥Space opens the island, ⌥Space opens the command bar, Esc closes.", "⌃⌥Пробел открывает островок, ⌥Пробел — командную строку, Esc закрывает."),
    "about.version": ("%@ = version", "Version %@", "Версия %@"),
    "about.madeBy": ("%@ = author", "Made by %@", "Сделано %@"),
    "about.license": ("License line", "Free and open source · MIT License", "Бесплатно и с открытым кодом · Лицензия MIT"),
    "about.github": ("Link", "Source code on GitHub", "Исходный код на GitHub"),
    "module.home": ("Tab", "Home", "Главная"),
    "module.clipboard": ("Tab", "Clipboard", "Буфер"),
    "module.notes": ("Tab", "Notes & Timer", "Заметки и таймер"),
    "module.weather": ("Tab", "Weather", "Погода"),
    "module.command": ("Tab: command bar", "Command", "Команда"),
    "media.previous": ("Button", "Previous", "Назад"),
    "media.next": ("Button", "Next", "Вперёд"),
    "media.play": ("Button", "Play", "Играть"),
    "media.pause": ("Button", "Pause", "Пауза"),
    "toast.copied": ("Toast title", "Copied", "Скопировано"),
    "toast.shelf": ("Toast title", "Put on the shelf", "Положено на полку"),
    "toast.inClipboard": ("Toast subtitle", "In the clipboard", "В буфере обмена"),
    "toast.pasteHint": ("Toast subtitle", "Press ⌘V to paste", "Нажмите ⌘V, чтобы вставить"),
    "toast.done": ("Toast title", "Done — in the clipboard", "Готово — уже в буфере"),
    "toast.emptyClipboard": ("Toast title", "Clipboard is empty", "Буфер пуст"),
    "toast.copyFirst": ("Toast subtitle", "Copy some text first", "Сначала скопируйте текст"),
    "action.screenshot": ("Quick action", "Screenshot", "Скриншот"),
    "action.picker": ("Quick action", "Color picker", "Пипетка"),
    "action.layout": ("Quick action: ghbdtn → привет", "Fix layout", "Раскладка"),
    "action.translit": ("Quick action", "Transliterate", "Транслит"),
    "action.upper": ("Quick action", "UPPERCASE", "ВЕРХНИЙ"),
    "action.timer5": ("Quick action", "Timer 5 min", "Таймер 5 мин"),
    "dock.add": ("Button", "Add app", "Добавить программу"),
    "dock.remove": ("Context menu", "Remove from island", "Убрать с острова"),
    "clipboard.search": ("Placeholder", "Search history", "Поиск по истории"),
    "clipboard.clear": ("Button", "Clear (keeps pinned)", "Очистить (закреплённые останутся)"),
    "clipboard.empty": ("Empty state", "Nothing copied yet", "Пока ничего не скопировано"),
    "clipboard.hint": ("Empty state", "Everything you copy shows up here. Password managers are skipped.", "Всё, что вы копируете, появится здесь. Менеджеры паролей пропускаются."),
    "clipboard.pin": ("Button", "Pin", "Закрепить"),
    "clipboard.delete": ("Button", "Delete", "Удалить"),
    "shelf.open": ("Context menu", "Open", "Открыть"),
    "shelf.dragOut": ("Hint", "Drag a file out to use it anywhere.", "Перетащите файл наружу, чтобы использовать его."),
    "notes.placeholder": ("Placeholder", "Write something…", "Напишите что-нибудь…"),
    "weather.loading": ("Empty state", "Loading weather…", "Загружаю погоду…"),
    "weather.failed": ("Empty state", "Couldn't load weather", "Не удалось загрузить погоду"),
    "weather.off": ("Empty state", "Weather is off", "Погода выключена"),
    "weather.hint": ("Hint", "Set your city in Settings → Behavior. Data: Open-Meteo, only the city name is sent.", "Город задаётся в Настройки → Поведение. Данные: Open-Meteo, отправляется только название города."),
    "command.placeholder": ("Placeholder", "App, 12*34, timer 10, anything…", "Программа, 12*34, таймер 10, что угодно…"),
    "command.title": ("Empty state", "One line for everything", "Одна строка на всё"),
    "command.hint": ("Empty state", "Open apps, calculate, start a timer or search the web. ⌥Space opens it anywhere.", "Открывайте программы, считайте, ставьте таймер или ищите в сети. ⌥Пробел — из любого места."),
    "command.copyResult": ("Row detail", "Enter — copy", "Enter — скопировать"),
    "command.timer": ("Row; %d = minutes", "Start timer: %d min", "Запустить таймер: %d мин"),
    "command.open": ("Row detail", "Open", "Открыть"),
    "command.web": ("Row; %@ = query", "Search the web: “%@”", "Искать в сети: «%@»"),
    "command.browser": ("Row detail", "Browser", "Браузер"),
    "behavior.mascot": ("Toggle", "Cat", "Котик"),
    "behavior.time": ("Toggle", "Time", "Время"),
    "behavior.temperature": ("Toggle", "Temperature", "Градусы"),
    "behavior.wings": ("Section header", "Next to the notch", "Рядом с чёлкой"),
    "behavior.wingsHint": ("Hint", "Turn everything off and the island hides behind the notch until you hover over it. Music and the timer still show up while they run.", "Если всё выключить, островок прячется за чёлкой, пока вы на него не наведёте. Музыка и таймер всё равно появляются, пока работают."),
    "behavior.toasts": ("Toggle", "Pop-up activities (copied, new song, shelf)", "Всплывающие события (скопировано, новый трек, полка)"),
    "behavior.weather": ("Toggle", "Weather", "Погода"),
    "behavior.city": ("Label", "City", "Город"),
    "behavior.apply": ("Button", "Apply", "Применить"),
}


def unit(v):
    return {"stringUnit": {"state": "translated", "value": v}}


def loc(v):
    if isinstance(v, dict):
        return {"variations": {"plural": {k: unit(x) for k, x in v.items()}}}
    return unit(v)


out = {"sourceLanguage": "en", "version": "1.0", "strings": {}}
for key in sorted(S):
    comment, en, ru = S[key]
    out["strings"][key] = {"comment": comment, "extractionState": "manual",
                           "localizations": {"en": loc(en), "ru": loc(ru)}}

path = os.path.join(os.path.dirname(__file__), "..", "Sources", "Islet", "Resources", "Localizable.xcstrings")
with open(path, "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, indent=2)
    f.write("\n")
print("wrote", len(S), "keys")
