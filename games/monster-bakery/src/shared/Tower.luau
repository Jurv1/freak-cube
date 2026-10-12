--!strict
-- Торт-башня: кто стоит на этаже и что дают за бой. Общий модуль: клиент показывает врагов до боя.

local GameData = require(script.Parent.GameData)

local LEVEL_CAP = 50
local BOSS_EVERY = 5
local BOSS_EXTRA_LEVELS = 2

export type Floor = {
	number: number,
	level: number, -- уровень врагов
	boss: boolean, -- первый враг — «Гигант» с двойным здоровьем
	enemies: { string },
	scale: number, -- рост здоровья и силы врагов выше 50-го этажа
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

-- Состав этажа одинаков у всех игроков: его задаёт номер этажа
function Tower.floor(number: number): Floor
	local enemies: { string }
	if number == 1 then
		enemies = { "cheese+flour" }
	elseif number == 2 then
		enemies = { "flour+strawberry", "cheese+strawberry" }
	else
		local pool = {}
		for index = 1, Tower.poolSize(number) do
			pool[index] = GameData.RecipeOrder[index]
		end
		Random.new(1000 + number):Shuffle(pool)
		enemies = { pool[1], pool[2], pool[3] }
	end

	local boss = number % BOSS_EVERY == 0
	local level = math.min(number, LEVEL_CAP)
	return {
		number = number,
		level = if boss then level + BOSS_EXTRA_LEVELS else level,
		boss = boss,
		enemies = enemies,
		scale = if number > LEVEL_CAP then 1.04 ^ (number - LEVEL_CAP) else 1,
	}
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
