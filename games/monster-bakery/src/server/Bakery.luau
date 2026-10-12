--!strict
-- Правила пекарни без обращения к миру: доход, опыт, выпечка в печах.
-- Работает только с профилем, поэтому одинаково считает и живую игру, и время отсутствия.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameData"))
local Saves = require(script.Parent.Saves)

type Profile = Saves.Profile
type Oven = Saves.Oven

export type BakeResult = { key: string, isNew: boolean, golden: boolean, level: number, leveledUp: boolean }

local Bakery = {}

function Bakery.income(profile: Profile): number
	local total = 0
	for key, level in profile.creatures do
		local multiplier = if profile.golden[key] then GameData.GOLDEN_MULTIPLIER else 1
		total += GameData.Recipes[key].income * level * multiplier
	end
	return total
end

-- Мастерство — сумма уровней всех зверьков; по нему строится таблица лидеров
function Bakery.mastery(profile: Profile): number
	local total = 0
	for _, level in profile.creatures do
		total += level
	end
	return total
end

function Bakery.isMaxed(profile: Profile, key: string): boolean
	local level = profile.creatures[key]
	return level ~= nil and level >= GameData.levelCap(profile.diploma)
end

-- Золотого зверька на потолке уровня печь уже ничем не улучшит
function Bakery.canBake(profile: Profile, key: string): boolean
	return not (Bakery.isMaxed(profile, key) and profile.golden[key] == true)
end

-- Возвращает true, если уровень вырос. На потолке опыт сгорает.
function Bakery.addXp(profile: Profile, key: string, amount: number): boolean
	local cap = GameData.levelCap(profile.diploma)
	local startLevel = profile.creatures[key]
	local level = startLevel
	local xp = (profile.xp[key] or 0) + amount
	while level < cap and xp >= GameData.xpNeed(level) do
		xp -= GameData.xpNeed(level)
		level += 1
	end
	profile.creatures[key] = level
	profile.xp[key] = if level >= cap then 0 else xp
	return level > startLevel
end

-- Жар даётся только при запуске: улучшение печи посреди выпечки его не продлевает
function Bakery.startBake(profile: Profile, oven: Oven, key: string, at: number, withRepeat: boolean)
	local tier = GameData.OvenTiers[oven.tier]
	oven.key = key
	oven.startedAt = at
	oven.duration = GameData.bakeDuration(key, oven.tier)
	if withRepeat and tier.heat > 0 and not Bakery.isMaxed(profile, key) then
		oven.repeatOn = true
		oven.heatUntil = at + tier.heat
	else
		oven.repeatOn = false
		oven.heatUntil = nil
	end
end

local function finishBake(profile: Profile, oven: Oven, key: string): BakeResult
	local isNew = profile.creatures[key] == nil
	local leveledUp = false
	if isNew then
		profile.creatures[key] = 1
		profile.xp[key] = 0
	else
		leveledUp = Bakery.addXp(profile, key, GameData.BAKE_XP)
	end
	local becameGolden = false
	if not profile.golden[key] and math.random() < GameData.OvenTiers[oven.tier].golden then
		profile.golden[key] = true
		becameGolden = true
	end
	return { key = key, isNew = isNew, golden = becameGolden, level = profile.creatures[key], leveledUp = leveledUp }
end

-- Завершает все выпечки печи, закончившиеся к моменту t, и возвращает их по порядку.
-- Выпечка, начатая до конца жара, допекается; после неё печь остывает, но помнит рецепт.
function Bakery.advanceOven(profile: Profile, oven: Oven, t: number): { BakeResult }
	local results: { BakeResult } = {}
	while oven.key and oven.startedAt and oven.duration and oven.startedAt + oven.duration <= t do
		local finishedAt = oven.startedAt + oven.duration
		table.insert(results, finishBake(profile, oven, oven.key))
		local again = oven.repeatOn == true
			and oven.heatUntil ~= nil
			and finishedAt < oven.heatUntil
			and not Bakery.isMaxed(profile, oven.key)
		if again then
			oven.startedAt = finishedAt
			-- скорость печи могла вырасти с прошлой выпечки
			oven.duration = GameData.bakeDuration(oven.key, oven.tier)
		else
			oven.startedAt = nil
			oven.duration = nil
			oven.heatUntil = nil
			oven.repeatOn = false
		end
	end
	return results
end

return Bakery
