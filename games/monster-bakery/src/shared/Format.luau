--!strict
-- Числа и время для интерфейса: 1.5K, 20M, 1B; «5 мин», «4:32».

local Format = {}

local SUFFIXES = { "K", "M", "B", "T" }

function Format.number(value: number): string
	local scaled = math.floor(value)
	if scaled < 1000 then
		return tostring(scaled)
	end
	local index = 0
	while scaled >= 1000 and index < #SUFFIXES do
		scaled /= 1000
		index += 1
	end
	-- одна цифра после точки, пока число меньше 100; округление вниз, чтобы не показать больше, чем есть
	local text = if scaled < 100
		then string.format("%.1f", math.floor(scaled * 10) / 10)
		else string.format("%d", math.floor(scaled))
	local trimmed = string.gsub(text, "%.0$", "")
	return trimmed .. SUFFIXES[index]
end

-- Длительность словами: «45 с», «5 мин», «2 ч»
function Format.duration(seconds: number): string
	if seconds >= 3600 then
		return string.format("%g ч", seconds / 3600)
	elseif seconds >= 60 then
		return string.format("%g мин", seconds / 60)
	end
	return string.format("%d с", seconds)
end

-- Обратный отсчёт: «4:32» или «1:02:05»
function Format.clock(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	if whole >= 3600 then
		return string.format("%d:%02d:%02d", whole // 3600, whole % 3600 // 60, whole % 60)
	end
	return string.format("%d:%02d", whole // 60, whole % 60)
end

return Format
