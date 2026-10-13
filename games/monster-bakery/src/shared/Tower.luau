--!strict
-- Торт-башня: кто стоит на этаже и что дают за бой. Общий модуль: клиент показывает врагов до боя.

local BattleRules = require(script.Parent.BattleRules)
local GameData = require(script.Parent.GameData)

local LEVEL_CAP = 50
local BOSS_EVERY = 5
local TIER_SAMPLE = 3 -- по скольким самым дорогим рецептам пула считается сила этажа
local ENDLESS_GROWTH = 1.04 -- рост врагов за этаж выше 50-го

export type Floor = {
	number: number,
	level: number, -- уровень врагов, он же на карточке
	boss: boolean, -- первый враг — «Гигант» с увеличенным здоровьем
	enemies: { string },
	scale: number, -- множитель здоровья и силы врагов поверх уровня: зависит от номера этажа, а не от рецепта
}

local Tower = {}

-- Из скольких первых рецептов книги набираются враги
function Tower.poolSize(number: number): number
	if number <= 5 then
		return 3
	elseif number <= 10 then
		return 6
	elseif number <= 20 then
		return 10
	end
	return #GameData.RecipeOrder
end

-- Книга рецептов отсортирована по доходу, поэтому самые дорогие рецепты пула — последние в нём
local function poolTier(poolSize: number): number
	local total = 0
	for index = poolSize - TIER_SAMPLE + 1, poolSize do
		total += BattleRules.tier(GameData.RecipeOrder[index])
	end
	return total / TIER_SAMPLE
end

-- Состав этажа одинаков у всех игроков: его задаёт номер этажа
function Tower.floor(number: number): Floor
	local poolSize = Tower.poolSize(number)
	local enemies: { string }
	if number == 1 then
		enemies = { "cheese+flour" }
	elseif number == 2 then
		enemies = { "flour+strawberry", "cheese+strawberry" }
	else
		local pool = {}
		for index = 1, poolSize do
			pool[index] = GameData.RecipeOrder[index]
		end
		Random.new(1000 + number):Shuffle(pool)
		-- три разных основных типа: у любой команды на этаже есть и удобный враг, и неудобный
		enemies = BattleRules.pickDistinct(pool)
	end

	local boss = number % BOSS_EVERY == 0
	local level = math.min(number, LEVEL_CAP)
	local scale = poolTier(poolSize)
		* (1 + GameData.TOWER_HARDENING * level)
		* (if boss then GameData.TOWER_BOSS_SCALE else GameData.TOWER_FLOOR_SCALE)
	if number > LEVEL_CAP then
		scale *= ENDLESS_GROWTH ^ (number - LEVEL_CAP)
	end
	return { number = number, level = level, boss = boss, enemies = enemies, scale = scale }
end

-- Здоровье, сила и скорость врага под номером index на этаже
function Tower.enemyStats(floor: Floor, index: number): (number, number, number)
	local hp, atk, spd = BattleRules.baseStats(floor.enemies[index])
	local scale = floor.scale * BattleRules.levelScale(floor.level)
	if floor.boss and index == 1 then
		hp *= GameData.TOWER_GIANT_HP
	end
	return math.floor(hp * scale + 0.5), math.floor(atk * scale + 0.5), spd
end

-- income — текущий доход игрока в секунду: награда не обесценивается с ростом
function Tower.winCoins(number: number, income: number): number
	if number % BOSS_EVERY == 0 then
		return math.floor(math.max(500 * number, 300 * income))
	end
	return math.floor(math.max(100 * number, 60 * income))
end

-- Опыт каждому зверьку команды за первое прохождение этажа
function Tower.winXp(number: number): number
	return 3 * (4 + math.min(number, LEVEL_CAP))
end

function Tower.loseXp(number: number): number
	return math.ceil(0.25 * (4 + math.min(number, LEVEL_CAP)))
end

return Tower
