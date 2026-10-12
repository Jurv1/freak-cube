--!strict
-- Данные игрока: загрузка, сохранение и приведение старых форматов к текущему.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameData"))

local STORE_NAME = "BakeryV1"
local SAVE_VERSION = 2
local ATTEMPTS = 3

export type Oven = {
	tier: number,
	key: string?, -- рецепт, который печётся; у остывшей печи — последний
	startedAt: number?, -- время сервера (Unix), когда началась текущая выпечка; nil — печь стоит
	duration: number?,
	heatUntil: number?, -- до какого времени печь сама перепекает рецепт
	repeatOn: boolean?,
}

export type Profile = {
	coins: number,
	unlocked: { [string]: boolean },
	creatures: { [string]: number }, -- ключ рецепта -> уровень
	xp: { [string]: number }, -- опыт внутри текущего уровня
	golden: { [string]: boolean },
	ovens: { Oven },
	diploma: number,
	tower: number, -- наивысший пройденный этаж башни
	team: { string }, -- ключи рецептов по порядку выхода; пусто — команда собирается сама
	lastSeen: number?, -- nil у нового игрока
}

local Saves = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[Bakery] сохранение отключено: " .. tostring(result))
	end
end

-- Игроки, чьи данные не удалось загрузить: их сессию не сохраняем, чтобы не затереть то, что лежит в хранилище
local unsafe: { [number]: boolean } = {}
-- Сколько записей сейчас в пути; сервер не должен закрыться, пока они не дошли
local pending = 0

local function saveKey(userId: number): string
	return "u_" .. userId
end

local function withRetries(action: () -> any): (boolean, any)
	local lastError: any = nil
	for attempt = 1, ATTEMPTS do
		local ok, result = pcall(action)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < ATTEMPTS then
			task.wait(attempt)
		end
	end
	return false, lastError
end

local function newProfile(): Profile
	local profile: Profile = {
		coins = 0,
		unlocked = {},
		creatures = {},
		xp = {},
		golden = {},
		ovens = { { tier = 1 } },
		diploma = 0,
		tower = 0,
		team = {},
		lastSeen = nil,
	}
	for _, ingredient in GameData.Ingredients do
		if ingredient.price == 0 then
			profile.unlocked[ingredient.id] = true
		end
	end
	return profile
end

-- Конечное число или nil: в сохранении может лежать что угодно
local function num(value: any): number?
	if typeof(value) == "number" and value == value and math.abs(value) ~= math.huge then
		return value
	end
	return nil
end

-- Собирает профиль из сохранения любой версии.
-- Отдельной ветки для v1 нет: в v1 не было полей xp, ovens и diploma, и они получают значения по умолчанию,
-- а уровень выше потолка обрезается (в v1 потолка не было).
local function decode(raw: any): Profile
	local profile = newProfile()
	if typeof(raw) ~= "table" then
		return profile
	end

	profile.coins = math.max(0, num(raw.coins) or 0)
	profile.diploma = math.clamp(math.floor(num(raw.diploma) or 0), 0, GameData.MAX_DIPLOMA)
	profile.tower = math.max(0, math.floor(num(raw.tower) or 0))
	profile.lastSeen = num(raw.lastSeen)

	if typeof(raw.unlocked) == "table" then
		for _, id in raw.unlocked do
			if GameData.IngredientById[id] then
				profile.unlocked[id] = true
			end
		end
	end

	local cap = GameData.levelCap(profile.diploma)
	local savedXp = if typeof(raw.xp) == "table" then raw.xp else {}
	local savedGolden = if typeof(raw.golden) == "table" then raw.golden else {}
	if typeof(raw.creatures) == "table" then
		for key, savedLevel in raw.creatures do
			local rawLevel = num(savedLevel)
			if GameData.Recipes[key] and rawLevel then
				local level = math.clamp(math.floor(rawLevel), 1, cap)
				local xp = math.max(0, math.floor(num(savedXp[key]) or 0))
				profile.creatures[key] = level
				profile.xp[key] = if level >= cap then 0 else math.min(xp, GameData.xpNeed(level) - 1)
				if savedGolden[key] == true then
					profile.golden[key] = true
				end
			end
		end
	end

	if typeof(raw.team) == "table" then
		for _, key in raw.team do
			local fits = #profile.team < GameData.TEAM_SIZE
			if fits and profile.creatures[key] and not table.find(profile.team, key) then
				table.insert(profile.team, key)
			end
		end
	end

	if typeof(raw.ovens) == "table" then
		local ovens: { Oven } = {}
		for slot = 1, #GameData.OvenSlotPrices do
			local saved = raw.ovens[slot]
			if typeof(saved) ~= "table" then
				break
			end
			local oven: Oven = { tier = math.clamp(math.floor(num(saved.tier) or 1), 1, #GameData.OvenTiers) }
			local startedAt, duration = num(saved.startedAt), num(saved.duration)
			if typeof(saved.key) == "string" and GameData.Recipes[saved.key] then
				oven.key = saved.key
				if startedAt and duration and duration > 0 then
					oven.startedAt = startedAt
					oven.duration = duration
					oven.heatUntil = num(saved.heatUntil)
					oven.repeatOn = saved.repeatOn == true
				end
			end
			table.insert(ovens, oven)
		end
		if #ovens > 0 then
			profile.ovens = ovens
		end
	end

	return profile
end

local function encode(profile: Profile)
	local unlocked = {}
	for id in profile.unlocked do
		table.insert(unlocked, id)
	end
	return {
		v = SAVE_VERSION,
		coins = math.floor(profile.coins),
		unlocked = unlocked,
		creatures = profile.creatures,
		xp = profile.xp,
		golden = profile.golden,
		ovens = profile.ovens,
		diploma = profile.diploma,
		tower = profile.tower,
		team = profile.team,
		lastSeen = os.time(),
	}
end

-- Всегда возвращает профиль: при сбое загрузки — новый, и такая сессия не сохраняется
function Saves.load(player: Player): Profile
	local userId = player.UserId
	if not store then
		unsafe[userId] = true
		return newProfile()
	end
	local ok, result = withRetries(function()
		return (store :: DataStore):GetAsync(saveKey(userId))
	end)
	if not ok then
		unsafe[userId] = true
		warn(
			"[Bakery] не удалось загрузить "
				.. player.Name
				.. ", прогресс этой сессии не сохранится: "
				.. tostring(result)
		)
		return newProfile()
	end
	unsafe[userId] = nil
	return decode(result)
end

function Saves.canSave(player: Player): boolean
	return store ~= nil and not unsafe[player.UserId]
end

function Saves.save(player: Player, profile: Profile): boolean
	if not Saves.canSave(player) then
		return false
	end
	local userId = player.UserId
	local data = encode(profile)
	pending += 1
	local ok, err = withRetries(function()
		(store :: DataStore):SetAsync(saveKey(userId), data)
	end)
	pending -= 1
	if not ok then
		warn("[Bakery] не удалось сохранить " .. player.Name .. ": " .. tostring(err))
	end
	return ok
end

-- Ждёт, пока дойдут все начатые записи. Вызывается из BindToClose: запись, начатая в PlayerRemoving,
-- иначе обрывается закрытием сервера.
function Saves.waitForPending()
	while pending > 0 do
		task.wait()
	end
end

return Saves
