--!strict
-- Общие данные игры: ингредиенты и рецепты. Читают и сервер, и клиент.

export type Ingredient = {
	id: string,
	name: string,
	emoji: string,
	price: number,
	power: number,
	hp: number,
	atk: number,
	spd: number,
}
export type Recipe = { name: string, color: Color3, income: number, bakeTime: number, a: string, b: string }
export type OvenTier = { name: string, speed: number, heat: number, golden: number, price: number }
export type Skill = {
	id: string,
	name: string,
	type: string?, -- id ингредиента; у «Кусь» типа нет
	power: number, -- урон в процентах от силы зверька
	cooldown: number, -- сколько следующих раундов скилл недоступен
	effect: string?, -- shield | heal | slow | first | freeze
	hint: string,
}

local GameData = {}

GameData.GOLDEN_MULTIPLIER = 5
GameData.OFFLINE_CAP_SECONDS = 8 * 3600
GameData.OFFLINE_RATE = 0.5
GameData.BAKE_XP = 10
GameData.LEVEL_CAP = 50
GameData.LEVELS_PER_DIPLOMA = 10
GameData.MAX_DIPLOMA = 5
GameData.LEADERBOARD_TOP = 50

-- Бой. Полные правила — docs/battles.md
GameData.TEAM_SIZE = 3
GameData.SECOND_SKILL_LEVEL = 5
GameData.BATTLE_UNLOCK_CREATURES = 4 -- кнопка «Бой» появляется при стольких зверьках
GameData.TOWER_FLOORS_OPEN = 10 -- сколько этажей башни уже можно пройти
GameData.ARENA_MULT = 4.4 -- общий множитель статов на арене: там уровень не действует
GameData.Battle = {
	roundLimit = 15,
	missedLimit = 3, -- столько пропущенных выборов подряд — техническое поражение
	critChance = 0.1,
	critMultiplier = 1.5,
	strongMultiplier = 1.5,
	weakMultiplier = 2 / 3,
	shieldMultiplier = 0.5,
	healShare = 0.5,
	-- длительности фаз, секунды: по ним идёт и сервер, и анимация клиента
	introTime = 2,
	chooseTime = 8,
	replaceTime = 5,
	actionTime = 1.2,
	koTime = 0.8,
	roundPad = 0.4,
}

-- Тип бьёт сильнее тот, на который указывает: радуга → лёд → шоколад → клубника → сыр → мука → радуга
GameData.TypeBeats = {
	rainbow = "ice",
	ice = "chocolate",
	chocolate = "strawberry",
	strawberry = "cheese",
	cheese = "flour",
	flour = "rainbow",
} :: { [string]: string }

-- У зверька три кнопки: «Кусь» и по скиллу от каждого ингредиента (id скилла = id ингредиента)
GameData.Skills = {
	bite = { id = "bite", name = "Кусь", power = 100, cooldown = 0, hint = "удар" },
	flour = {
		id = "flour",
		name = "Мучной щит",
		type = "flour",
		power = 100,
		cooldown = 2,
		effect = "shield",
		hint = "щит",
	},
	strawberry = {
		id = "strawberry",
		name = "Ягодный укус",
		type = "strawberry",
		power = 110,
		cooldown = 2,
		effect = "heal",
		hint = "лечит",
	},
	cheese = {
		id = "cheese",
		name = "Липкий сыр",
		type = "cheese",
		power = 120,
		cooldown = 2,
		effect = "slow",
		hint = "замедляет",
	},
	chocolate = {
		id = "chocolate",
		name = "Шоко-бомба",
		type = "chocolate",
		power = 180,
		cooldown = 3,
		hint = "сильный удар",
	},
	rainbow = {
		id = "rainbow",
		name = "Радужный луч",
		type = "rainbow",
		power = 130,
		cooldown = 2,
		effect = "first",
		hint = "бьёт первым",
	},
	ice = {
		id = "ice",
		name = "Ледяное дыхание",
		type = "ice",
		power = 90,
		cooldown = 3,
		effect = "freeze",
		hint = "морозит",
	},
} :: { [string]: Skill }

-- Цена слота печи по порядку покупки; первая печь есть сразу
GameData.OvenSlotPrices = { 0, 5000, 150000 }

-- speed делит время выпечки; heat — сколько секунд печь сама перепекает рецепт;
-- golden — шанс золотого зверька; price — цена улучшения до этого уровня
GameData.OvenTiers = {
	{ name = "Кирпичная", speed = 1, heat = 0, golden = 0.05, price = 0 },
	{ name = "Чугунная", speed = 1.25, heat = 300, golden = 0.05, price = 20000 },
	{ name = "Стальная", speed = 1.5, heat = 1200, golden = 0.06, price = 1000000 },
	{ name = "Хрустальная", speed = 2, heat = 3600, golden = 0.07, price = 10000000 },
	{ name = "Лунная", speed = 2.5, heat = 7200, golden = 0.08, price = 150000000 },
	{ name = "Звёздная", speed = 3, heat = 14400, golden = 0.1, price = 1000000000 },
} :: { OvenTier }

-- power задаёт и доход зверька, и время выпечки.
-- hp, atk, spd — боевой профиль: базовые статы зверька — сумма профилей двух его ингредиентов.
GameData.Ingredients = {
	{ id = "flour", name = "Мука", emoji = "🌾", price = 0, power = 1, hp = 130, atk = 23, spd = 12 },
	{ id = "strawberry", name = "Клубника", emoji = "🍓", price = 0, power = 1, hp = 90, atk = 25, spd = 27 },
	{ id = "cheese", name = "Сыр", emoji = "🧀", price = 0, power = 1, hp = 110, atk = 26, spd = 18 },
	{ id = "chocolate", name = "Шоколад", emoji = "🍫", price = 50, power = 3, hp = 95, atk = 31, spd = 15 },
	{ id = "rainbow", name = "Радуга", emoji = "🌈", price = 300, power = 8, hp = 95, atk = 24, spd = 31 },
	{ id = "ice", name = "Лёд", emoji = "🧊", price = 1500, power = 20, hp = 115, atk = 24, spd = 20 },
} :: { Ingredient }

GameData.IngredientById = {} :: { [string]: Ingredient }
for _, ingredient in GameData.Ingredients do
	GameData.IngredientById[ingredient.id] = ingredient
end

function GameData.recipeKey(a: string, b: string): string
	if a < b then
		return a .. "+" .. b
	end
	return b .. "+" .. a
end

-- Ключ — два id по алфавиту через «+»
local CREATURES: { [string]: { any } } = {
	["flour+strawberry"] = { "Клубничный Пончозавр", Color3.fromRGB(255, 130, 170) },
	["cheese+flour"] = { "Сырный Булкотик", Color3.fromRGB(255, 210, 90) },
	["cheese+strawberry"] = { "Чизкейк-Хрюша", Color3.fromRGB(255, 190, 170) },
	["chocolate+flour"] = { "Шоко-Кексозавр", Color3.fromRGB(120, 75, 50) },
	["chocolate+strawberry"] = { "Трюфельный Зайка", Color3.fromRGB(170, 70, 90) },
	["cheese+chocolate"] = { "Фондю-Пёс", Color3.fromRGB(200, 140, 60) },
	["flour+rainbow"] = { "Радужный Бубликорог", Color3.fromRGB(190, 140, 255) },
	["rainbow+strawberry"] = { "Мармеладный Дракоша", Color3.fromRGB(255, 90, 200) },
	["cheese+rainbow"] = { "Пицца-Попугай", Color3.fromRGB(255, 120, 60) },
	["chocolate+rainbow"] = { "Конфетти-Хамелеон", Color3.fromRGB(90, 210, 150) },
	["flour+ice"] = { "Снежный Вафлепингвин", Color3.fromRGB(210, 235, 255) },
	["ice+strawberry"] = { "Пломбирный Тюлень", Color3.fromRGB(255, 200, 225) },
	["cheese+ice"] = { "Моцарелла-Йети", Color3.fromRGB(240, 240, 215) },
	["chocolate+ice"] = { "Эскимо-Морж", Color3.fromRGB(95, 70, 110) },
	["ice+rainbow"] = { "Лис Северного Сияния", Color3.fromRGB(80, 230, 220) },
}

GameData.Recipes = {} :: { [string]: Recipe }
GameData.RecipeOrder = {} :: { string }
for key, info in CREATURES do
	local a, b = string.match(key, "^(%a+)%+(%a+)$")
	assert(a and b, "неверный ключ рецепта: " .. key)
	local power = GameData.IngredientById[a].power + GameData.IngredientById[b].power
	GameData.Recipes[key] = {
		name = info[1],
		color = info[2],
		income = power,
		bakeTime = 3 + power,
		a = a,
		b = b,
	}
	table.insert(GameData.RecipeOrder, key)
end
table.sort(GameData.RecipeOrder, function(x, y)
	local rx, ry = GameData.Recipes[x], GameData.Recipes[y]
	if rx.income ~= ry.income then
		return rx.income < ry.income
	end
	return x < y
end)

-- Опыт для перехода с уровня level на следующий
function GameData.xpNeed(level: number): number
	return math.max(10, math.floor(0.03 * level ^ 3 + 0.5))
end

function GameData.levelCap(diploma: number): number
	return GameData.LEVEL_CAP + GameData.LEVELS_PER_DIPLOMA * diploma
end

-- Время выпечки рецепта в печи уровня tier, с точностью до 0.1 с
function GameData.bakeDuration(key: string, tier: number): number
	return math.floor(GameData.Recipes[key].bakeTime / GameData.OvenTiers[tier].speed * 10 + 0.5) / 10
end

return GameData
