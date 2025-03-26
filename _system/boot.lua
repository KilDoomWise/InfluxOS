-- called from /init.lua
local raw_loadfile = ...

_G._OSVERSION = "InfluxOS 1.8.7"
_G.SCREEN = "SCREENADDR"

-- luacheck: globals component computer unicode _OSVERSION
local component = component
local computer = computer
local unicode = unicode

-- Runlevel information.
_G.runlevel = "S"
local shutdown = computer.shutdown
computer.runlevel = function() return _G.runlevel end
computer.shutdown = function(reboot)
  _G.runlevel = reboot and 6 or 0
  if os.sleep then
    computer.pushSignal("shutdown")
    os.sleep(0.1) -- Allow shutdown processing.
  end
  shutdown(reboot)
end

-- InfluxOS загрузочные переменные
local bootPercent = 0
local bootSteps = 0  -- Будет установлено позже после подсчета всех шагов
local currentStep = 0
local totalSteps = 0  -- Для подсчета общего числа операций

-- Сохраняем начальные GPU и screen
local originalGpu, originalScreen

-- Инициализация GPU и экрана
local w, h
local customScreen = _G.SCREEN
local screen = component.list("screen", true)()
local gpu = screen and component.list("gpu", true)()

if gpu then
  gpu = component.proxy(gpu)
  
  -- Сохраняем оригинальный экран и GPU для последующего восстановления
  originalScreen = gpu.getScreen()
  originalGpu = gpu
  
  -- Проверяем, существует ли указанный экран
  local screenExists = false
  for address in component.list("screen", true) do
    if address == customScreen then
      screenExists = true
      break
    end
  end
  
  -- Если указанный экран существует, привязываем к нему GPU
  if screenExists then
    gpu.bind(customScreen)
    screen = customScreen
  else
    -- Иначе привязываем к доступному экрану
    if not gpu.getScreen() then
      gpu.bind(screen)
    end
  end
  
  _G.boot_screen = gpu.getScreen()
  
  -- Получаем максимальное разрешение
  w, h = gpu.maxResolution()
  
  -- Устанавливаем квадратное (или близкое к квадратному) разрешение
  local size = 126
  gpu.setResolution(size, size/2)
  w, h = size, size
  
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  -- Скрываем начальный экран
  gpu.fill(1, 1, w, h, " ")
end

-- Настройки для загрузочного экрана
local backgroundColor = 0x111214 -- Темный фон
local textColor = 0xFFFFFF       -- Белый текст для надписи
local logoColor = 0x3366CC       -- Цвет логотипа (синий)
local progressColor = 0x3366CC   -- Синий цвет прогресса
local emptyColor = 0x17191d      -- Цвет пустых сегментов
local pkg_Name = "mtk"

-- Подсчет шагов загрузки - уменьшаем количество шагов для лучшего отображения прогресса
local function countBootSteps()
  -- Упрощаем подсчет до фиксированного числа для более предсказуемого прогресса
  return 15  -- Фиксированное количество шагов
end

-- Инициализация загрузочного экрана
if gpu then
  -- Сохраняем предыдущие настройки
  local oldBackground = gpu.getBackground()
  local oldForeground = gpu.getForeground()
  
  -- Получаем размеры экрана
  local w, h = gpu.getResolution()
  local screenCenterX = math.floor(w / 2)
  local screenCenterY = math.floor(h / 2)
  
  -- Очистка экрана
  gpu.setBackground(backgroundColor)
  gpu.fill(1, 1, w, h, " ")
  
  -- Создаем простой логотип, который ГАРАНТИРОВАННО будет по центру
  local function printCenteredText(text, y, color)
      gpu.setForeground(color or textColor)
      local x = math.floor((w - string.len(text)) / 2) + 1
      gpu.set(x, y, text)
  end
  
  -- Функция для рисования посимвольного градиента без использования bit32
  local function drawGradientLine(text, y, startColor, endColor)
      local textLength = string.len(text)
      local startX = math.floor((w - textLength) / 2) + 1
      
      -- Получаем RGB-компоненты начального цвета
      local r1 = math.floor(startColor / 65536)
      local g1 = math.floor((startColor % 65536) / 256)
      local b1 = startColor % 256
      
      -- Получаем RGB-компоненты конечного цвета
      local r2 = math.floor(endColor / 65536)
      local g2 = math.floor((endColor % 65536) / 256)
      local b2 = endColor % 256
      
      -- Проходим по каждому символу и рисуем его своим цветом
      for i = 1, textLength do
          -- Вычисляем промежуточный цвет для градиента
          local ratio = (i - 1) / (textLength - 1)
          local r = math.floor(r1 * (1 - ratio) + r2 * ratio)
          local g = math.floor(g1 * (1 - ratio) + g2 * ratio)
          local b = math.floor(b1 * (1 - ratio) + b2 * ratio)
          
          -- Собираем цвет из компонентов
          local color = r * 65536 + g * 256 + b
          
          -- Устанавливаем цвет и рисуем символ
          gpu.setForeground(color)
          gpu.set(startX + i - 1, y, string.sub(text, i, i))
      end
  end
  
  -- Цвета для градиента - начало и конец каждой строки
  local startColors = {
      0x0000AA, -- темно-синий
      0x0022BB, -- синий
      0x0044CC, -- голубой
      0x0066DD, -- светло-голубой
      0x0088EE, -- очень светлый голубой
      0x00AAFF, -- бледно-голубой
      0x66CCFF  -- почти белый голубой
  }
  
  local endColors = {
      0x6600AA, -- фиолетовый
      0x8800BB, -- пурпурный
      0xAA00CC, -- маджента
      0xCC00DD, -- розовый
      0xEE00EE, -- светло-розовый
      0xFF00FF, -- яркий розовый
      0xFFAAFF  -- бледно-розовый
  }
  
  -- ASCII арт для InfluxOS - логотип
  local logoStartY = screenCenterY - 6
  local logoLines = {
      "88                d8\"    88                             d8\"'    `\"8b   d8\"     \"8b  ",
      "88                88     88                            d8'        `8b  Y8,          ",
      "88  8b,dPPYba,  MM88MMM  88  88       88  8b,     ,d8  88          88  `Y8aaaaa,    ",
      "88  88P'   `\"8a   88     88  88       88   `Y8, ,8P'   88          88    `\"\"\"\"\"8b,  ",
      "88  88       88   88     88  88       88     )888(     Y8,        ,8P          `8b  ",
      "88  88       88   88     88  \"8a,   ,a88   ,d8\" \"8b,    Y8a.    .a8P   Y8a     a8P  ",
      "88  88       88   88     88   `\"YbbdP'Y8  8P'     `Y8    `\"Y8888Y\"'     \"Y88888P\"   "
  }
  
  -- Выводим градиентный ASCII-арт
  for i = 1, #logoLines do
      drawGradientLine(logoLines[i], logoStartY + i - 1, startColors[i], endColors[i])
  end
  
  -- Добавляем текст "REACTOR OFFENSIVE" внизу справа
  gpu.setForeground(textColor)
  local offensiveText = "REACTOR OFFENSIVE"
  local offensiveX = screenCenterX + 10  -- Позиция справа от логотипа (уменьшено для квадратного экрана)
  local offensiveY = logoStartY + 8   -- Позиция ниже логотипа
  gpu.set(offensiveX, offensiveY, offensiveText)
  
  -- Базовая точка для индикатора ровно под текстом
  local indicatorCenterX = screenCenterX
  local indicatorBaseY = logoStartY + 12
  
  -- Функция для отрисовки прогресс-индикатора (делаем её глобальной)
  _G.drawProgressIndicator = function(percent)
      -- Определяем, сколько сегментов нужно заполнить (из 12 возможных)
      local segmentsTotal = 12
      local segmentsToFill = math.ceil((percent / 100) * segmentsTotal)
     
      -- Создаем сегменты
      local pixels = {
          -- Верхняя горизонтальная линия (3 пикселя)
          {x = indicatorCenterX - 2, y = indicatorBaseY, w = 2},     -- левая часть
          {x = indicatorCenterX, y = indicatorBaseY, w = 2},         -- центральная часть
          {x = indicatorCenterX + 2, y = indicatorBaseY, w = 2},     -- правая часть
         
          -- Правая вертикальная линия (3 пикселя)
          {x = indicatorCenterX + 4, y = indicatorBaseY + 1, w = 2}, -- верхняя часть
          {x = indicatorCenterX + 4, y = indicatorBaseY + 2, w = 2}, -- средняя часть
          {x = indicatorCenterX + 4, y = indicatorBaseY + 3, w = 2}, -- нижняя часть
         
          -- Нижняя горизонтальная линия (3 пикселя)
          {x = indicatorCenterX + 2, y = indicatorBaseY + 4, w = 2}, -- правая часть
          {x = indicatorCenterX, y = indicatorBaseY + 4, w = 2},     -- центральная часть
          {x = indicatorCenterX - 2, y = indicatorBaseY + 4, w = 2}, -- левая часть
         
          -- Левая вертикальная линия (3 пикселя)
          {x = indicatorCenterX - 4, y = indicatorBaseY + 3, w = 2}, -- нижняя часть
          {x = indicatorCenterX - 4, y = indicatorBaseY + 2, w = 2}, -- средняя часть
          {x = indicatorCenterX - 4, y = indicatorBaseY + 1, w = 2}  -- верхняя часть
      }
     
      -- Отрисовка всех пикселей
      for i, pixel in ipairs(pixels) do
          if i <= segmentsToFill then
              gpu.setBackground(progressColor)  -- Заполненные пиксели
          else
              gpu.setBackground(emptyColor)     -- Незаполненные пиксели
          end
         
          -- Отрисовка пикселя с точно заданной шириной
          gpu.fill(pixel.x, pixel.y, pixel.w, 1, " ")
      end
  end
  
  -- Подсчет общего количества шагов загрузки
  bootSteps = countBootSteps()
  
  -- Обновление индикатора загрузки
  _G.updateBootProgress = function(step, message)
    currentStep = step
    -- Используем полный диапазон для отображения прогресса, но всегда минимум 5%
    bootPercent = math.max(5, math.min(100, math.floor((currentStep / bootSteps) * 100)))
    _G.drawProgressIndicator(bootPercent)
    
    if message then
      -- Очищаем предыдущее сообщение
      gpu.setBackground(backgroundColor)
      gpu.fill(1, indicatorBaseY + 6, w, 1, " ")
      
      -- Выводим новое сообщение
      gpu.setForeground(textColor)
      printCenteredText(message, indicatorBaseY + 6, textColor)
    end
  end
  
  -- Инициализируем индикатор загрузки с 5%
  _G.drawProgressIndicator(5)
  
  -- Добавляем текстовое поле для отображения статуса загрузки
  gpu.setForeground(textColor)
  printCenteredText("Initializing system...", indicatorBaseY + 6, textColor)
end

-- Report boot progress if possible.
local uptime = computer.uptime
local pull = computer.pullSignal
local last_sleep = uptime()

-- Обновленная функция status для обновления загрузочного экрана без вывода OpenOS логов
local function status(msg)
  -- Обновляем прогресс загрузки
  if _G.updateBootProgress then
    currentStep = currentStep + 1
    _G.updateBootProgress(currentStep, msg)
  end
  
  -- boot can be slow in some environments, protect from timeouts
  if uptime() - last_sleep > 1 then
    local signal = table.pack(pull(0))
    -- there might not be any signal
    if signal.n > 0 then
      -- push the signal back in queue for the system to use it
      computer.pushSignal(table.unpack(signal, 1, signal.n))
    end
    last_sleep = uptime()
  end
end

status("Booting " .. _OSVERSION .. "...")

-- Custom low-level dofile implementation reading from our ROM.
local function dofile(file)
  status("> " .. file)
  local program, reason = raw_loadfile(file)
  if program then
    local result = table.pack(pcall(program))
    if result[1] then
      return table.unpack(result, 2, result.n)
    else
      error(result[2])
    end
  else
    error(reason)
  end
end

status("Initializing package management...")

-- Load file system related libraries we need to load other stuff moree
-- comfortably. This is basically wrapper stuff for the file streams
-- provided by the filesystem components.
local package = dofile("/lib/package.lua")

do
  -- Unclutter global namespace now that we have the package module and a filesystem
  _G.component = nil
  _G.computer = nil
  _G.process = nil
  _G.unicode = nil
  -- Inject the package modules into the global namespace, as in Lua.
  _G.package = package

  -- Initialize the package module with some of our own APIs.
  package.loaded.component = component
  package.loaded.computer = computer
  package.loaded.unicode = unicode
  package.loaded.buffer = dofile("/lib/buffer.lua")
  package.loaded.filesystem = dofile("/lib/filesystem.lua")

  -- Inject the io modules
  _G.io = dofile("/lib/io.lua")
end

status("Initializing file system...")

-- Mount the ROM and temporary file systems to allow working on the file
-- system module from this point on.
require("filesystem").mount(computer.getBootAddress(), "/")

status("Running boot scripts...")

-- Run library startup scripts. These mostly initialize event handlers.
local function rom_invoke(method, ...)
  return component.invoke(computer.getBootAddress(), method, ...)
end

local scripts = {}
for _, file in ipairs(rom_invoke("list", "boot")) do
  local path = "boot/" .. file
  if not rom_invoke("isDirectory", path) then
    table.insert(scripts, path)
  end
end
table.sort(scripts)
for i = 1, #scripts do
  dofile(scripts[i])
end

status("Initializing components...")

for c, t in component.list() do
  computer.pushSignal("component_added", c, t)
end

status("Initializing system...")

computer.pushSignal("init") -- so libs know components are initialized.
require("event").pull(1, "init") -- Allow init processing.
_G.runlevel = 1

-- После полной загрузки системы дорисовываем индикатор до 100%
if gpu and _G.updateBootProgress then
  _G.updateBootProgress(bootSteps, "System loaded!")
  _G.drawProgressIndicator(100)
  
  -- Небольшая пауза чтобы пользователь увидел 100% загрузку
  computer.pullSignal(0.5)
  
  -- Очищаем экран для приветствия
  gpu.setBackground(backgroundColor)
  gpu.fill(1, 1, w, h, " ")
  
  -- Добавляем перед запуском эффектное приветствие
  local welcomeText = "WELCOME TO INFLUXOS"
  local welcomeY = math.floor(h / 2) - 10
  
  -- Анимация появления текста с мгновенным исчезновением
  gpu.setForeground(0x00FFFF) -- Яркий бирюзовый
  local x = math.floor((w - string.len(welcomeText)) / 2) + 1
  gpu.set(x, welcomeY, welcomeText)
  
  -- Короткая пауза
  computer.pullSignal(0.7)
  
  -- Очистка экрана
  gpu.setBackground(0x000000)
  gpu.fill(1, 1, w, h, " ")
end

-- Устанавливаем переменную окружения SCREEN для всех последующих привязок GPU
os.setenv("SCREEN", _G.SCREEN)
