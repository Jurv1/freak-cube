--!strict
-- Формулы боя, общие для сервера и клиента: статы, типы, скиллы зверька.
-- Числа лежат в GameData, полное описание — в docs/battles.md.

local GameData = require(script.Parent.GameData)

local RULES = GameData.Battle
local TYPE_COUNT = #GameData.TypeOrder
-- Насколько расклад по типам сдвигает оценку зверька для команды «Авто». Подобрано прогоном BattleSim:
-- при большем весе «Авто» берёт удобного по типам, но слабого зверька и проигрывает чаще
local MATCHUP_WEIGHT = 0.2

local BattleRules = {}

local typeIndex: { [string]: number } = {}
for index, id in GameData.TypeOrder do
	typeIndex[id] = index
end

-- Сколько шагов по стрелке круга типов от from до to
local function steps(from: string, to: string): number
	return (typeIndex[to] - typeIndex[from]) % TYPE_COUNT
end

function BattleRules.baseStats(key: string): (number, number, number)
	local recipe = GameData.Recipes[key]
	local a, b = GameData.IngredientById[recipe.a], GameData.IngredientById[recipe.b]
	return a.hp + b.hp, a.atk + b.atk, a.spd + b.spd
end

-- Сила рецепта растит статы медленно: дорогой зверёк сильнее стартового в полтора раза, а не в 14 раз, как по доходу.
-- income рецепта — это и есть сумма power двух ингредиентов.
function BattleRules.tier(key: string): number
	return 1 + GameData.TIER_GROWTH * math.log(GameData.Recipes[key].income / 2, 2)
end

function BattleRules.levelScale(level: number): number
	return 1 + GameData.LEVEL_GROWTH * (level - 1)
end

-- Здоровье, сила, скорость. Скорость с уровнем не растёт.
function BattleRules.stats(key: string, level: number): (number, number, number)
	local hp, atk, spd = BattleRules.baseStats(key)
	local scale = BattleRules.tier(key) * BattleRules.levelScale(level)
	return math.floor(hp * scale + 0.5), math.floor(atk * scale + 0.5), spd
end

-- На арене все уравнены: ни уровень, ни сила рецепта не действуют
function BattleRules.arenaStats(key: string): (number, number, number)
	local hp, atk, spd = BattleRules.baseStats(key)
	return math.floor(hp * GameData.ARENA_MULT + 0.5), math.floor(atk * GameData.ARENA_MULT + 0.5), spd
end

-- Одно число «насколько зверёк силён»: для карточки и для команды по умолчанию
function BattleRules.power(key: string, level: number): number
	local hp, atk = BattleRules.stats(key, level)
	return math.floor(hp / 4 + atk)
end

-- Основной тип и подтип зверька — два его ингредиента. Основной — тот, от которого до второго
-- ближе по стрелке круга; если они стоят напротив — тот, чей ингредиент дороже.
local typesCache: { [string]: { string } } = {}
function BattleRules.types(key: string): (string, string?)
	local cached = typesCache[key]
	if not cached then
		local recipe = GameData.Recipes[key]
		local a, b = recipe.a, recipe.b
		local distance = steps(a, b)
		-- ближе по стрелке от b до a; ровно напротив — решает цена ингредиента
		local swap = distance * 2 > TYPE_COUNT
			or (distance * 2 == TYPE_COUNT and GameData.IngredientById[b].power > GameData.IngredientById[a].power)
		if distance == 0 then
			cached = { a }
		elseif swap then
			cached = { b, a }
		else
			cached = { a, b }
		end
		typesCache[key] = cached
	end
	return cached[1], cached[2]
end

local function cell(skillType: string, targetType: string, strong: number, weak: number): number
	local distance = steps(skillType, targetType)
	if distance == 1 then
		return strong
	elseif distance == TYPE_COUNT - 1 then
		return weak
	end
	return 1
end

-- Множитель урона скилла по зверьку и число стрелок для интерфейса: от −2 («совсем слабо») до 2 («очень сильно»).
-- По основному типу цели скилл бьёт сильнее или слабее, чем по подтипу; результаты перемножаются.
local multiplierCache: { [string]: { [string]: { number } } } = {}
function BattleRules.typeMultiplier(skillType: string?, targetKey: string): (number, number)
	if not skillType then
		return 1, 0
	end
	local bySkill = multiplierCache[skillType]
	if not bySkill then
		bySkill = {}
		multiplierCache[skillType] = bySkill
	end
	local cached = bySkill[targetKey]
	if not cached then
		local main, sub = BattleRules.types(targetKey)
		local multiplier = cell(skillType, main, RULES.strongMultiplier, RULES.weakMultiplier)
		if sub then
			multiplier *= cell(skillType, sub, RULES.subStrongMultiplier, RULES.subWeakMultiplier)
		end
		local arrows = 0
		if multiplier >= 1.4 then
			arrows = 2
		elseif multiplier >= 1.1 then
			arrows = 1
		elseif multiplier <= 0.7 then
			arrows = -2
		elseif multiplier <= 0.9 then
			arrows = -1
		end
		cached = { multiplier, arrows }
		bySkill[targetKey] = cached
	end
	return cached[1], cached[2]
end

-- Кнопки зверька по порядку: «Кусь», скилл основного типа и, с 5-го уровня, скилл подтипа
function BattleRules.skillsOf(key: string, level: number, allOpen: boolean): { string }
	local main, sub = BattleRules.types(key)
	local skills = { "bite", main }
	if sub and (allOpen or level >= GameData.SECOND_SKILL_LEVEL) then
		table.insert(skills, sub)
	end
	return skills
end

-- Лучший типовой множитель скиллов по цели. «Кусь» есть у всех, поэтому меньше единицы не бывает.
function BattleRules.bestMultiplier(skills: { string }, targetKey: string): number
	local best = 0
	for _, skillId in skills do
		best = math.max(best, (BattleRules.typeMultiplier(GameData.Skills[skillId].type, targetKey)))
	end
	return best
end

-- Расклад зверька против врагов: насколько его скиллы ложатся на них лучше, чем их скиллы на него.
-- Больше нуля — враги удобные, меньше — неудобные.
function BattleRules.matchup(key: string, level: number, foes: { string }, foeLevel: number): number
	if #foes == 0 then
		return 0
	end
	local mine = BattleRules.skillsOf(key, level, false)
	local total = 0
	for _, foe in foes do
		local theirs = BattleRules.skillsOf(foe, foeLevel, false)
		total += BattleRules.bestMultiplier(mine, foe) - BattleRules.bestMultiplier(theirs, key)
	end
	return total / #foes
end

-- Берёт из списка до трёх зверьков по порядку: сначала тех, чей основной тип ещё не взят,
-- затем, если мест больше, чем типов, — пропущенных
function BattleRules.pickDistinct(keys: { string }): { string }
	local team: { string } = {}
	local taken: { [string]: boolean } = {}
	for _, distinctOnly in { true, false } do
		for _, key in keys do
			if #team >= GameData.TEAM_SIZE then
				break
			end
			local main = BattleRules.types(key)
			if not table.find(team, key) and not (distinctOnly and taken[main]) then
				table.insert(team, key)
				taken[main] = true
			end
		end
	end
	return team
end

-- Команда по умолчанию: зверьки с наибольшей оценкой и разными основными типами, первый — лидер.
-- Оценка — сила, поправленная на расклад против врагов этажа; без врагов (арена) остаётся одна сила.
-- При равной оценке — по порядку книги рецептов.
function BattleRules.autoTeam(creatures: { [string]: number }, foes: { string }?, foeLevel: number?): { string }
	local keys: { string } = {}
	local score: { [string]: number } = {}
	local place: { [string]: number } = {}
	for _, key in GameData.RecipeOrder do
		local level = creatures[key]
		if level then
			local matchup = if foes then BattleRules.matchup(key, level, foes, foeLevel or 1) else 0
			score[key] = BattleRules.power(key, level) * (1 + MATCHUP_WEIGHT * matchup)
			table.insert(keys, key)
			place[key] = #keys
		end
	end
	table.sort(keys, function(x, y)
		if score[x] ~= score[y] then
			return score[x] > score[y]
		end
		return place[x] < place[y]
	end)
	return BattleRules.pickDistinct(keys)
end

return BattleRules
