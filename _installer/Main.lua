local component = require("component")
local computer = require("computer")
local term = require("term")
local unicode = require("unicode")
local fs = require("filesystem")

-- Проверка необходимых компонентов
local function checkComponent(name)
  if not component.isAvailable(name) then
    print("Ошибка: компонент " .. name .. " не найден!")
    return false
  end
  return true
end

if not checkComponent("gpu") or not checkComponent("internet") or not checkComponent("eeprom") then
  print("Установка невозможна. Нажмите любую клавишу для выхода.")
  os.sleep(0.5)
  while true do
    local _, _, _, code = computer.pullSignal("key_down")
    if code ~= 0 then
      computer.shutdown()
      return
    end
  end
end

local gpu = component.gpu
local internet = component.internet
local eeprom = component.eeprom

-- Настройки установщика
local repoURL = "https://raw.githubusercontent.com/KilDoomWise/InfluxOS/refs/heads/main/"
local installerURL = "_installer/"
local efiURL = "EFI/Minified.lua"
local installPath = "/"

-- Получение размеров экрана
local w, h = gpu.getResolution()

-- Цвета
local COLOR_BACKGROUND = 0x000000
local COLOR_TEXT = 0xFFFFFF
local COLOR_HEADER = 0xCCCCCC
local COLOR_SUCCESS = 0x00FF00
local COLOR_ERROR = 0xFF0000
local COLOR_PROGRESS = 0x3366CC

-- Очистка экрана
local function clearScreen()
  gpu.setBackground(COLOR_BACKGROUND)
  gpu.setForeground(COLOR_TEXT)
  gpu.fill(1, 1, w, h, " ")
  term.setCursor(1, 1)
end

-- Отрисовка заголовка
local function drawHeader(text)
  local textLength = unicode.len(text)
  local x = math.floor((w - textLength) / 2)
  
  gpu.setBackground(COLOR_BACKGROUND)
  gpu.setForeground(COLOR_HEADER)
  gpu.fill(1, 2, w, 1, "─")
  gpu.set(x, 1, text)
  gpu.fill(1, 3, w, 1, "─")
  
  term.setCursor(1, 4)
end

-- Отрисовка прогресс-бара
local function drawProgress(value, y)
  local width = math.floor(w * 0.8)
  local x = math.floor((w - width) / 2)
  local progWidth = math.floor(width * (value / 100))
  
  y = y or math.floor(h / 2)
  
  gpu.setBackground(COLOR_BACKGROUND)
  gpu.setForeground(COLOR_TEXT)
  gpu.set(x - 2, y, string.format("%3d%%", value))
  
  gpu.setBackground(COLOR_BACKGROUND)
  gpu.fill(x, y, width, 1, "─")
  
  gpu.setForeground(COLOR_PROGRESS)
  gpu.fill(x, y, progWidth, 1, "█")
  
  term.setCursor(1, y + 2)
end

-- Вывод центрированного текста
local function centerText(text, y, color)
  local textLength = unicode.len(text)
  local x = math.floor((w - textLength) / 2)
  
  gpu.setBackground(COLOR_BACKGROUND)
  gpu.setForeground(color or COLOR_TEXT)
  gpu.set(x, y, text)
  
  term.setCursor(1, y + 1)
end

-- Запрос данных из интернета
local function request(url)
  local fullURL = repoURL .. url
  local response = ""
  local success, connection = pcall(internet.request, fullURL)
  
  if not success then
    centerText("Ошибка подключения к " .. fullURL, h-4, COLOR_ERROR)
    centerText("Проверьте соединение и адрес репозитория", h-3, COLOR_ERROR)
    os.sleep(3)
    return nil
  end
  
  local deadline = computer.uptime() + 5
  while computer.uptime() < deadline do
    local connSuccess, status = pcall(connection.finishConnect)
    if connSuccess then break end
    os.sleep(0.1)
  end
  
  local data = ""
  local chunk = connection.read(math.huge)
  while chunk do
    data = data .. chunk
    chunk = connection.read(math.huge)
  end
  connection.close()
  
  return data
end

-- Загрузка файла из интернета
local function download(url, path)
  local data = request(url)
  if not data then
    return false
  end
  
  local dir = string.match(path, "(.+)/[^/]+$")
  if dir and not fs.exists(dir) then
    fs.makeDirectory(dir)
  end
  
  local file = io.open(path, "wb")
  if not file then
    centerText("Ошибка создания файла: " .. path, h-2, COLOR_ERROR)
    os.sleep(1)
    return false
  end
  
  file:write(data)
  file:close()
  
  return true
end

-- Проверка системных требований
local function checkSystemRequirements()
  clearScreen()
  drawHeader("Проверка системных требований")
  
  local requirements = {
    {"Видеокарта Tier 2+", gpu.getDepth() >= 4},
    {"ОЗУ 2MB+", computer.totalMemory() >= 2 * 1024 * 1024},
    {"Диск 2MB+", false}
  }
  
  -- Проверка доступного места
  for address in component.list("filesystem") do
    local proxy = component.proxy(address)
    if proxy.spaceTotal() >= 2 * 1024 * 1024 then
      requirements[3][2] = true
      break
    end
  end
  
  local allMet = true
  for i, req in ipairs(requirements) do
    local status = req[2] and "✓" or "✗"
    local color = req[2] and COLOR_SUCCESS or COLOR_ERROR
    centerText(status .. " " .. req[1], 4 + i, color)
    allMet = allMet and req[2]
  end
  
  if not allMet then
    centerText("Ваш компьютер не соответствует минимальным требованиям!", h-4, COLOR_ERROR)
    centerText("Нажмите любую клавишу для выхода", h-2)
    os.sleep(0.5)
    while true do
      local _, _, _, code = computer.pullSignal("key_down")
      if code ~= 0 then
        computer.shutdown()
        return false
      end
    end
  end
  
  centerText("Все требования соблюдены!", h-4, COLOR_SUCCESS)
  centerText("Нажмите любую клавишу для продолжения", h-2)
  os.sleep(0.5)
  while true do
    local _, _, _, code = computer.pullSignal("key_down")
    if code ~= 0 then
      break
    end
  end
  
  return true
}

-- Выбор диска для установки
local function selectDisk()
  clearScreen()
  drawHeader("Выберите диск для установки")
  
  local drives = {}
  local y = 5
  
  for address in component.list("filesystem") do
    local proxy = component.proxy(address)
    if proxy.spaceTotal() >= 2 * 1024 * 1024 and not proxy.isReadOnly() then
      table.insert(drives, {
        address = address,
        proxy = proxy,
        label = proxy.getLabel() or "Диск " .. #drives + 1,
        size = proxy.spaceTotal(),
        used = proxy.spaceUsed()
      })
      
      centerText(#drives .. ". " .. drives[#drives].label, y)
      y = y + 1
      centerText("   " .. math.floor(drives[#drives].used / 1024) .. "KB/" .. 
                math.floor(drives[#drives].size / 1024) .. "KB", y)
      y = y + 2
    end
  end
  
  if #drives == 0 then
    centerText("Не найдено подходящих дисков!", h-4, COLOR_ERROR)
    centerText("Нажмите любую клавишу для выхода", h-2)
    os.sleep(0.5)
    while true do
      local _, _, _, code = computer.pullSignal("key_down")
      if code ~= 0 then
        computer.shutdown()
        return nil
      end
    end
  end
  
  centerText("Введите номер диска (1-" .. #drives .. "):", h-4)
  
  local selectedDrive
  while true do
    term.setCursor(math.floor(w/2), h-2)
    gpu.fill(math.floor(w/2), h-2, 10, 1, " ")
    local input = term.read()
    local num = tonumber(input)
    
    if num and num >= 1 and num <= #drives then
      selectedDrive = drives[num]
      break
    else
      centerText("Неверный ввод! Повторите попытку", h-3, COLOR_ERROR)
    end
  end
  
  return selectedDrive
}

-- Запрос данных пользователя
local function getUserData()
  clearScreen()
  drawHeader("Создание пользователя")
  
  centerText("Введите имя пользователя:", 5)
  term.setCursor(math.floor(w/2) - 10, 6)
  local username = term.read():gsub("\n", "")
  
  if username == "" then
    username = "user"
  end
  
  centerText("Установить пароль? (д/н):", 8)
  term.setCursor(math.floor(w/2) - 10, 9)
  local setPassword = term.read():gsub("\n", ""):lower()
  
  local password = nil
  if setPassword == "д" or setPassword == "y" then
    centerText("Введите пароль:", 11)
    term.setCursor(math.floor(w/2) - 10, 12)
    password = term.read({echo="*"}):gsub("\n", "")
    
    centerText("Повторите пароль:", 14)
    term.setCursor(math.floor(w/2) - 10, 15)
    local confirmPassword = term.read({echo="*"}):gsub("\n", "")
    
    if password ~= confirmPassword then
      centerText("Пароли не совпадают!", 17, COLOR_ERROR)
      centerText("Пароль не будет установлен", 18, COLOR_ERROR)
      password = nil
      os.sleep(2)
    else
      centerText("Пароль установлен", 17, COLOR_SUCCESS)
      os.sleep(1)
    end
  end
  
  return {
    username = username,
    password = password
  }
}

-- Установка системы
local function installSystem(drive, userData)
  clearScreen()
  drawHeader("Установка InfluxOS")
  
  -- Проверка файловых списков
  centerText("Получение списка файлов...", 5)
  local filesData = request(installerURL .. "Files.cfg")
  if not filesData then
    centerText("Ошибка получения списка файлов", h-4, COLOR_ERROR)
    centerText("Нажмите любую клавишу для выхода", h-2)
    os.sleep(0.5)
    while true do
      local _, _, _, code = computer.pullSignal("key_down")
      if code ~= 0 then
        computer.shutdown()
        return false
      end
    end
  end
  
  -- Преобразование строки в таблицу
  local files = load("return " .. filesData)()
  if not files then
    centerText("Ошибка обработки списка файлов", h-4, COLOR_ERROR)
    os.sleep(2)
    return false
  end
  
  -- Скачивание файлов
  local totalFiles = #files.required + #files.optional
  local currentFile = 0
  
  -- Создание системных директорий
  centerText("Создание системных директорий...", 7)
  fs.makeDirectory(installPath .. "System")
  fs.makeDirectory(installPath .. "Users/" .. userData.username)
  
  -- Скачивание необходимых файлов
  for i, file in ipairs(files.required) do
    currentFile = currentFile + 1
    local progress = math.floor(currentFile / totalFiles * 100)
    
    if type(file) == "table" then
      file = file.path
    end
    
    centerText("Загрузка: " .. file, 9)
    drawProgress(progress, 11)
    
    if not download(file, installPath .. file) then
      centerText("Ошибка загрузки файла: " .. file, h-4, COLOR_ERROR)
      centerText("Нажмите любую клавишу для продолжения", h-2)
      os.sleep(0.5)
      while true do
        local _, _, _, code = computer.pullSignal("key_down")
        if code ~= 0 then
          break
        end
      end
    end
  end
  
  -- Скачивание дополнительных файлов
  for i, file in ipairs(files.optional) do
    currentFile = currentFile + 1
    local progress = math.floor(currentFile / totalFiles * 100)
    
    if type(file) == "table" then
      file = file.path
    end
    
    centerText("Загрузка: " .. file, 9)
    drawProgress(progress, 11)
    
    if not download(file, installPath .. file) then
      centerText("Ошибка загрузки файла: " .. file, h-4, COLOR_ERROR)
      centerText("Установка продолжится...", h-3)
      os.sleep(1)
    end
  end
  
  -- Создание файла пользователя
  centerText("Создание профиля пользователя...", 13)
  local userFile = io.open(installPath .. "Users/" .. userData.username .. "/user.cfg", "w")
  if userFile then
    userFile:write("{\n")
    userFile:write("  username = \"" .. userData.username .. "\",\n")
    if userData.password then
      userFile:write("  password = \"" .. userData.password .. "\",\n")
    end
    userFile:write("  permissions = {\n")
    userFile:write("    admin = true\n")
    userFile:write("  }\n")
    userFile:write("}\n")
    userFile:close()
    centerText("Профиль пользователя создан!", 14, COLOR_SUCCESS)
  else
    centerText("Ошибка создания профиля пользователя", 14, COLOR_ERROR)
  end
  
  -- Прошивка EEPROM
  centerText("Прошивка EEPROM...", 16)
  local efiCode = request(efiURL)
  if efiCode then
    eeprom.set(efiCode)
    eeprom.setLabel("InfluxOS EFI")
    eeprom.setData(drive.address)
    centerText("EEPROM успешно прошит!", 17, COLOR_SUCCESS)
  else
    centerText("Ошибка прошивки EEPROM", 17, COLOR_ERROR)
    centerText("Система может не загрузиться автоматически", 18, COLOR_ERROR)
  end
  
  centerText("Установка завершена!", h-4, COLOR_SUCCESS)
  centerText("Нажмите любую клавишу для перезагрузки", h-2)
  os.sleep(0.5)
  while true do
    local _, _, _, code = computer.pullSignal("key_down")
    if code ~= 0 then
      computer.shutdown(true)
      return true
    end
  end
}

-- Главная функция установки
local function main()
  clearScreen()
  drawHeader("Установщик InfluxOS")
  
  centerText("Добро пожаловать в установщик InfluxOS!", 5)
  centerText("Этот мастер поможет вам установить систему", 7)
  centerText("Нажмите любую клавишу для начала", h-2)
  
  os.sleep(0.5)
  while true do
    local _, _, _, code = computer.pullSignal("key_down")
    if code ~= 0 then
      break
    end
  end
  
  if not checkSystemRequirements() then
    return
  end
  
  local selectedDrive = selectDisk()
  if not selectedDrive then
    return
  end
  
  local userData = getUserData()
  
  installSystem(selectedDrive, userData)
end

-- Запуск установщика
main()
