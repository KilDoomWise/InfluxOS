local component = require("component")
local computer = require("computer")
local os = require("os")

local gpu = component.gpu

-- Проверка системных требований
do
  local requirements = {}

  -- Графика
  if gpu.getDepth() < 8 or gpu.maxResolution() < 160 then
    table.insert(requirements, "Видеокарта и экран уровня 3 (Tier 3)")
  end

  -- Оперативная память
  if computer.totalMemory() < 2 * 1024 * 1024 then
    table.insert(requirements, "Минимум 2 модуля памяти уровня 3.5")
  end

  -- Жесткий диск
  do
    local diskFound = false
    
    for address in component.list("filesystem") do
      if component.invoke(address, "spaceTotal") >= 2 * 1024 * 1024 then
        diskFound = true
        break
      end
    end
    
    if not diskFound then
      table.insert(requirements, "Жесткий диск минимум уровня 2")
    end
  end

  -- Интернет-карта
  if not component.isAvailable("internet") then
    table.insert(requirements, "Интернет-карта")
  end

  -- EEPROM
  if not component.isAvailable("eeprom") then
    table.insert(requirements, "EEPROM")
  end

  -- Вывод ошибок, если есть недостающие компоненты
  if #requirements > 0 then
    print("Ваш компьютер не соответствует минимальным требованиям:")
    
    for i = 1, #requirements do
      print("  ⨯ " .. requirements[i])
    end
    
    return
  end
end

-- URL к вашему установщику
local installerUrl = "https://raw.githubusercontent.com/KilDoomWise/InfluxOS/main/Installer/Main.lua"

-- Проверка доступности сервера
do
  local success, result = pcall(component.internet.request, installerUrl)
  
  if not success then
    if result then
      if result:match("PKIX") then
        print("SSL-сертификат сервера был отклонен Java. Обновите Java или установите сертификат вручную")
      else
        print("Сервер недоступен: " .. tostring(result))
      end
    else
      print("Сервер недоступен по неизвестной причине")
    end
    
    return
  end
  
  local deadline = computer.uptime() + 5
  local message
  
  while computer.uptime() < deadline do
    success, message = result.finishConnect()
    
    if success then
      break
    else
      if message then
        break
      else
        os.sleep(0.1)
      end
    end
  end
  
  result.close()
  
  if not success then
    print("Сервер недоступен. Проверьте, не заблокирован ли ваш репозиторий или настройки OpenComputers")
    return
  end
end

-- Запись EEPROM с загрузчиком для вашей системы
component.eeprom.set([[
  local internet = component.proxy(component.list("internet")())
  local connection = internet.request("]]..installerUrl..[[")
  local data = ""
  local chunk
  
  while true do
    chunk = connection.read(math.huge)
    
    if chunk then
      data = data .. chunk
    else
      break
    end
  end
  
  connection.close()
  
  load(data)()
]])

print("EEPROM успешно прошит. Перезагрузка компьютера...")
os.sleep(1)
computer.shutdown(true)
