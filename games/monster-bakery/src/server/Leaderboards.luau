--!strict
-- Таблицы лидеров в мире. Сейчас одна — «Мастерство» (сумма уровней зверьков).
-- Лежит в OrderedDataStore; запись и чтение — раз в две минуты, чтобы не упираться в лимиты запросов.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameData"))

local STORE_NAME = "LB_Mastery_v1"
local SYNC_INTERVAL = 120
local NAME_DELAY = 0.1
local NAME_PENDING = "…"
local NAME_UNKNOWN = "Игрок"

export type Row = { userId: number, name: string, value: number }

local Leaderboards = {}

local store: OrderedDataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[Bakery] таблица лидеров отключена: " .. tostring(result))
	end
end

-- Что этот сервер уже записал: то же значение второй раз не пишем
local written: { [number]: number } = {}
local names: { [number]: string } = {}
local nameQueue: { number } = {}
local top: { Row } = {}
local dirty = false
local pending = 0
local valueOf: ((Player) -> number?)? = nil

local function saveKey(userId: number): string
	return "u_" .. userId
end

-- Лучшие в мире на момент последнего чтения, по убыванию
function Leaderboards.top(): { Row }
	return top
end

-- true, если топ или имена в нём изменились с прошлого вызова
function Leaderboards.consumeChanges(): boolean
	local was = dirty
	dirty = false
	return was
end

function Leaderboards.write(player: Player, value: number)
	local userId = player.UserId
	if not store or value <= 0 or written[userId] == value then
		return
	end
	pending += 1
	local ok, err = pcall(function()
		(store :: OrderedDataStore):SetAsync(saveKey(userId), value)
	end)
	pending -= 1
	if ok then
		written[userId] = value
	else
		warn(
			"[Bakery] таблица лидеров: не удалось записать "
				.. player.Name
				.. ": "
				.. tostring(err)
		)
	end
end

local function refresh()
	if not store then
		return
	end
	local ok, result = pcall(function()
		return (store :: OrderedDataStore):GetSortedAsync(false, GameData.LEADERBOARD_TOP):GetCurrentPage()
	end)
	if not ok then
		warn("[Bakery] таблица лидеров: не удалось прочитать: " .. tostring(result))
		return
	end

	local rows: { Row } = {}
	for _, entry in result do
		local userId = tonumber(string.match(entry.key, "^u_(%d+)$"))
		if userId then
			local name = names[userId]
			if not name then
				local online = Players:GetPlayerByUserId(userId)
				if online then
					name = online.Name
					names[userId] = name
				else
					name = NAME_PENDING
					if not table.find(nameQueue, userId) then
						table.insert(nameQueue, userId)
					end
				end
			end
			table.insert(rows, { userId = userId, name = name, value = entry.value })
		end
	end
	top = rows
	dirty = true
end

-- Имена тех, кого нет на сервере, узнаём по одному: у запроса имени свой лимит
local function resolveNames()
	while true do
		local userId = table.remove(nameQueue, 1)
		if not userId then
			task.wait(0.5)
			continue
		end
		local ok, name = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		names[userId] = if ok then name else NAME_UNKNOWN
		for _, row in top do
			if row.userId == userId then
				row.name = names[userId]
			end
		end
		dirty = true
		task.wait(NAME_DELAY)
	end
end

-- Записывает изменившиеся значения игроков сервера и перечитывает топ
function Leaderboards.sync()
	if valueOf then
		for _, player in Players:GetPlayers() do
			local value = valueOf(player)
			if value then
				Leaderboards.write(player, value)
			end
		end
	end
	refresh()
end

-- getValue возвращает значение игрока или nil, если его в таблицу писать нельзя
function Leaderboards.start(getValue: (Player) -> number?)
	valueOf = getValue
	task.spawn(resolveNames)
	task.spawn(function()
		refresh()
		while true do
			task.wait(SYNC_INTERVAL)
			Leaderboards.sync()
		end
	end)
end

function Leaderboards.waitForPending()
	while pending > 0 do
		task.wait()
	end
end

return Leaderboards
