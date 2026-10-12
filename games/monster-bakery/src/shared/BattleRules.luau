--!strict
-- Формулы боя, общие для сервера и клиента: статы, типы, скиллы зверька.
-- Числа лежат в GameData, полное описание — в docs/battles.md.

local GameData = require(script.Parent.GameData)

local BattleRules = {}

local function baseStats(key: string): (number, number, number)
	local recipe = GameData.Recipes[key]
	local a, b = GameData.IngredientById[recipe.a], GameData.IngredientById[recipe.b]
	return a.hp + b.hp, a.atk + b.atk, a.spd + b.spd
end

-- Сила рецепта растит статы медленно: дорогой зверёк сильнее стартового вдвое, а не в 14 раз, как по доходу.
-- income рецепта — это и есть сумма power двух ингредиентов.
function BattleRules.tier(key: string): number
	return 1 + 0.25 * math.log(GameData.Recipes[key].income / 2, 2)
end

-- Здоровье, сила, скорость. Скорость с уровнем не растёт.
function BattleRules.stats(key: string, level: number): (number, number, number)
	local hp, atk, spd = baseStats(key)
	local scale = BattleRules.tier(key) * (1 + 0.08 * (level - 1))
	return math.floor(hp * scale + 0.5), math.floor(atk * scale + 0.5), spd
end

-- На арене все уравнены: ни уровень, ни сила рецепта не действуют
function BattleRules.arenaStats(key: string): (number, number, number)
	local hp, atk, spd = baseStats(key)
	return math.floor(hp * GameData.ARENA_MULT + 0.5), math.floor(atk * GameData.ARENA_MULT + 0.5), spd
end

-- Одно число «насколько зверёк силён»: для карточки и для команды по умолчанию
function BattleRules.power(key: string, level: number): number
	local hp, atk = BattleRules.stats(key, level)
	return math.floor(hp / 4 + atk)
end

-- Множитель урона скилла по зверьку и подпись для интерфейса: "strong", "weak" или nil.
-- У зверька два типа; если один из них слаб к скиллу, а другой стоек, они гасят друг друга.
function BattleRules.typeMultiplier(skillType: string?, targetKey: string): (number, string?)
	if not skillType then
		return 1, nil
	end
	local recipe = GameData.Recipes[targetKey]
	local beats = GameData.TypeBeats
	local strong = beats[skillType] == recipe.a or beats[skillType] == recipe.b
	local weak = beats[recipe.a] == skillType or beats[recipe.b] == skillType
	if strong and not weak then
		return GameData.Battle.strongMultiplier, "strong"
	elseif weak and not strong then
		return GameData.Battle.weakMultiplier, "weak"
	end
	return 1, nil
end

-- Кнопки зверька по порядку. Первый скилл — от ингредиента с большей силой, при равенстве — от первого в ключе рецепта.
function BattleRules.skillsOf(key: string, level: number, allOpen: boolean): { string }
	local recipe = GameData.Recipes[key]
	local first, second = GameData.IngredientById[recipe.a], GameData.IngredientById[recipe.b]
	if second.power > first.power then
		first, second = second, first
	end
	local skills = { "bite", first.id }
	if allOpen or level >= GameData.SECOND_SKILL_LEVEL then
		table.insert(skills, second.id)
	end
	return skills
end

-- Команда по умолчанию: трое с наибольшей силой, при равенстве — по порядку книги рецептов
function BattleRules.autoTeam(creatures: { [string]: number }): { string }
	local keys = {}
	for _, key in GameData.RecipeOrder do
		if creatures[key] then
			table.insert(keys, key)
		end
	end
	local place = {}
	for index, key in keys do
		place[key] = index
	end
	table.sort(keys, function(x, y)
		local px, py = BattleRules.power(x, creatures[x]), BattleRules.power(y, creatures[y])
		if px ~= py then
			return px > py
		end
		return place[x] < place[y]
	end)
	local team = {}
	for index = 1, math.min(GameData.TEAM_SIZE, #keys) do
		team[index] = keys[index]
	end
	return team
end

return BattleRules
