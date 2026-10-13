--!strict
-- Проверка баланса: бои бот против бота по docs/battles.md, раздел 13. В игре не используется.
-- Запуск из Studio в режиме Play, на сервере:
--   print(require(game.ServerScriptService.Server.BattleSim).run())
-- Части считаются и по отдельности: BattleSim.duels(), BattleSim.teams(), BattleSim.tower(), BattleSim.levels().
-- В режиме Edit require отдаёт модули из кеша Studio: после правки файлов посчитается старая версия.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BattleRules = require(Shared:WaitForChild("BattleRules"))
local GameData = require(Shared:WaitForChild("GameData"))
local Tower = require(Shared:WaitForChild("Tower"))
local BattleEngine = require(script.Parent.BattleEngine)

local SEED = 20261012
local YIELD_EVERY = 400 -- боёв между паузами, чтобы не подвесить Studio
local BOT_RANDOM = 0.25 -- как в игре: BattleService
local BOSS_RANDOM = 0.1
local LEVEL_CAP = 50
local STARTERS = 3 -- сколько первых рецептов книги — стартовые
local SHIFT_FLOORS = { 10, 20, 30, 40 } -- боссы, у которых проверяется «решает уровень»
local SHIFT_LEVELS = 3
local NEED_RANGE = 8 -- в каких пределах ищется запас уровня

type Watch = (fighter: BattleEngine.Fighter, choice: string?) -> ()

local BattleSim = {}

local battlesRun = 0

-- Доигрывает бой ботами. Возвращает победителя (0 — ничья) и число сыгранных раундов.
-- Сторона 1 после нокаута выпускает первого живого по порядку, сторона 2 — как бот этажа.
local function play(
	battle: BattleEngine.Battle,
	chance1: number,
	chance2: number,
	smart2: boolean,
	rng: Random,
	watch: Watch?
): (number, number)
	while true do
		local choices = {
			BattleEngine.botChoice(battle, 1, chance1, rng),
			BattleEngine.botChoice(battle, 2, chance2, rng),
		}
		if watch then
			watch(BattleEngine.active(battle, 1), choices[1])
			watch(BattleEngine.active(battle, 2), choices[2])
		end
		BattleEngine.resolveRound(battle, choices, rng)
		local winner = BattleEngine.winner(battle)
		if winner then
			battlesRun += 1
			if battlesRun % YIELD_EVERY == 0 then
				task.wait()
			end
			return winner, battle.round - 1
		end
		if BattleEngine.needsReplacement(battle, 1) then
			BattleEngine.replace(battle, 1, BattleEngine.botReplacement(battle, 1, false))
		end
		if BattleEngine.needsReplacement(battle, 2) then
			BattleEngine.replace(battle, 2, BattleEngine.botReplacement(battle, 2, smart2))
		end
	end
end

local function percent(value: number): string
	return string.format("%.1f%%", value * 100)
end

local function mark(ok: boolean): string
	return if ok then "" else "  <-- вне цели"
end

-- Сколько типов скиллов бьют по зверьку сильнее обычного
local function weaknesses(key: string): number
	local count = 0
	for _, skillType in GameData.TypeOrder do
		if BattleRules.typeMultiplier(skillType, key) > 1 then
			count += 1
		end
	end
	return count
end

-- Средняя доля побед по группе зверьков
local function groupShare(share: { [string]: number }, belongs: (key: string) -> boolean): number
	local total, count = 0, 0
	for _, key in GameData.RecipeOrder do
		if belongs(key) then
			total += share[key]
			count += 1
		end
	end
	return if count > 0 then total / count else 0
end

-- А1–А4. Все пары 1 на 1 на арене: доля побед каждого зверька, длина боя, перекосы по группам
local function duels(perPair: number, rng: Random, lines: { string })
	local order = GameData.RecipeOrder
	local score, fights = {}, {}
	local rounds, total = 0, 0
	local iceTurns, iceUsed = 0, 0
	for _, key in order do
		score[key], fights[key] = 0, 0
	end
	local function watch(fighter: BattleEngine.Fighter, choice: string?)
		if choice and table.find(fighter.skills, "ice") then
			iceTurns += 1
			if choice == "ice" then
				iceUsed += 1
			end
		end
	end
	for _, a in order do
		for _, b in order do
			for _ = 1, perPair do
				local battle = BattleEngine.new({ BattleEngine.arenaFighter(a) }, { BattleEngine.arenaFighter(b) })
				local winner, played = play(battle, 0, 0, false, rng, watch)
				score[a] += if winner == 1 then 1 elseif winner == 0 then 0.5 else 0
				score[b] += if winner == 2 then 1 elseif winner == 0 then 0.5 else 0
				fights[a] += 1
				fights[b] += 1
				rounds += played
				total += 1
			end
		end
	end

	local share: { [string]: number } = {}
	local outside = 0
	table.insert(
		lines,
		string.format(
			"А1. 1 на 1, арена, %d боёв. Цель: у каждого 40–60%% побед.",
			total
		)
	)
	for _, key in order do
		share[key] = score[key] / fights[key]
		local ok = share[key] >= 0.4 and share[key] <= 0.6
		if not ok then
			outside += 1
		end
		table.insert(lines, string.format("  %-22s %s%s", GameData.Recipes[key].name, percent(share[key]), mark(ok)))
	end
	table.insert(lines, string.format("  вне коридора: %d из %d", outside, #order))

	local length = rounds / total
	table.insert(
		lines,
		string.format(
			"А2. Средняя длина: %.2f раунда. Цель: 3.0–3.6.%s",
			length,
			mark(length >= 3 and length <= 3.6)
		)
	)

	table.insert(lines, "А3. Средние по группам. Цель: каждая группа 45–55%.")
	for _, id in GameData.TypeOrder do
		local value = groupShare(share, function(key)
			return BattleRules.types(key) == id
		end)
		table.insert(
			lines,
			string.format(
				"  основной тип %-11s %s%s",
				GameData.IngredientById[id].name,
				percent(value),
				mark(value >= 0.45 and value <= 0.55)
			)
		)
	end
	for _, id in GameData.TypeOrder do
		local value = groupShare(share, function(key)
			local recipe = GameData.Recipes[key]
			return recipe.a == id or recipe.b == id
		end)
		table.insert(
			lines,
			string.format(
				"  ингредиент %-13s %s%s",
				GameData.IngredientById[id].name,
				percent(value),
				mark(value >= 0.45 and value <= 0.55)
			)
		)
	end
	local single = groupShare(share, function(key)
		return weaknesses(key) == 1
	end)
	local double = groupShare(share, function(key)
		return weaknesses(key) ~= 1
	end)
	table.insert(
		lines,
		string.format(
			"  одна слабость %s, две слабости %s, разница %.1f п.п. Цель: не больше 4.%s",
			percent(single),
			percent(double),
			math.abs(single - double) * 100,
			mark(math.abs(single - double) <= 0.04)
		)
	)

	local iceShare = iceUsed / math.max(1, iceTurns)
	table.insert(
		lines,
		string.format(
			"А4. «Ледяное дыхание»: %s ходов ледяных зверьков. Цель: от 15%%.%s",
			percent(iceShare),
			mark(iceShare >= 0.15)
		)
	)
end

local function randomTeam(rng: Random): { BattleEngine.Fighter }
	local pool = table.clone(GameData.RecipeOrder)
	rng:Shuffle(pool)
	local team = {}
	for index = 1, GameData.TEAM_SIZE do
		team[index] = BattleEngine.arenaFighter(pool[index])
	end
	return team
end

-- Б1–Б2. Случайные бои 3 на 3 на арене: длина боя и влияние скорости лидера
local function teamFights(count: number, rng: Random, lines: { string })
	local lengths = {}
	local atLimit, fasterWins, fasterFights = 0, 0, 0
	for _ = 1, count do
		local battle = BattleEngine.new(randomTeam(rng), randomTeam(rng))
		local speed1, speed2 = battle.sides[1].team[1].spd, battle.sides[2].team[1].spd
		local winner, played = play(battle, 0, 0, false, rng)
		table.insert(lengths, played)
		if played >= GameData.Battle.roundLimit then
			atLimit += 1
		end
		if speed1 ~= speed2 and winner ~= 0 then
			fasterFights += 1
			if (speed1 > speed2) == (winner == 1) then
				fasterWins += 1
			end
		end
	end
	table.sort(lengths)
	local median = lengths[math.ceil(#lengths / 2)]
	local limitShare = atLimit / count
	local fasterShare = fasterWins / math.max(1, fasterFights)
	table.insert(lines, string.format("Б1. 3 на 3, арена, %d боёв.", count))
	table.insert(
		lines,
		string.format(
			"  медиана: %d раундов. Цель: 9–11.%s",
			median,
			mark(median >= 9 and median <= 11)
		)
	)
	table.insert(
		lines,
		string.format(
			"  дошли до предела раундов: %s. Цель: не больше 3%%.%s",
			percent(limitShare),
			mark(limitShare <= 0.03)
		)
	)
	table.insert(
		lines,
		string.format(
			"Б2. Побеждает сторона с более быстрым лидером: %s. Цель: 45–60%%.%s",
			percent(fasterShare),
			mark(fasterShare >= 0.45 and fasterShare <= 0.6)
		)
	)
end

-- Зверьки, из которых эталонный игрок собирает команду на этаже: пул этажа, все одного уровня
local function poolCreatures(number: number, level: number): { [string]: number }
	local creatures = {}
	for index = 1, Tower.poolSize(number) do
		creatures[GameData.RecipeOrder[index]] = level
	end
	return creatures
end

-- Бои игрока на этаже. aware — команда «Авто» собрана под врагов этажа, иначе только по силе.
-- Возвращает долю побед и долю боёв, дошедших до предела раундов.
local function floorRun(
	number: number,
	creatures: { [string]: number },
	aware: boolean,
	fights: number,
	rng: Random
): (number, number)
	local floor = Tower.floor(number)
	local keys = if aware
		then BattleRules.autoTeam(creatures, floor.enemies, floor.level)
		else BattleRules.autoTeam(creatures)
	local wins, atLimit = 0, 0
	for _ = 1, fights do
		local team = {}
		for index, key in keys do
			team[index] = BattleEngine.towerFighter(key, creatures[key])
		end
		local battle = BattleEngine.new(team, BattleEngine.towerEnemies(floor))
		local winner, played = play(battle, 0, if floor.boss then BOSS_RANDOM else BOT_RANDOM, floor.boss, rng)
		if winner == 1 then
			wins += 1
		end
		if played >= GameData.Battle.roundLimit then
			atLimit += 1
		end
	end
	return wins / fights, atLimit / fights
end

-- В1–В5 и В7. Башня: эталонный игрок уровня этажа, команда «Авто» из пула этажа.
-- Прокачки и закалки врагов здесь ещё нет: проверки со ступенями (В6, В8) добавятся вместе с Миксером.
local function towerFloors(lastFloor: number, perFloor: number, rng: Random, lines: { string })
	table.insert(
		lines,
		string.format(
			"В1–В3. Башня, этажи 1–%d, по %d боёв. Цель: обычный этаж 70–95%% (этажи 1–4 — от 70%%), босс 40–60%%.",
			lastFloor,
			perFloor
		)
	)
	local share: { [number]: number } = {}
	local blind: { [number]: number } = {}
	local bossLimit, bossCount = 0, 0
	for number = 1, lastFloor do
		local floor = Tower.floor(number)
		local creatures = poolCreatures(number, math.min(number, LEVEL_CAP))
		local wins, atLimit = floorRun(number, creatures, true, perFloor, rng)
		share[number] = wins
		blind[number] = floorRun(number, creatures, false, perFloor, rng)
		local ok
		if floor.boss then
			ok = wins >= 0.4 and wins <= 0.6
			bossLimit += atLimit
			bossCount += 1
		else
			ok = wins >= 0.7 and (number < 5 or wins <= 0.95)
		end
		table.insert(
			lines,
			string.format(
				"  этаж %2d%s %6s   без учёта врагов %6s%s",
				number,
				if floor.boss then " босс" else "     ",
				percent(wins),
				percent(blind[number]),
				mark(ok)
			)
		)
	end

	-- В3: соседние обычные этажи (через босса — тоже соседние)
	local worstGap, worstAt, previous = 0, 0, nil :: number?
	-- В5: «Авто» без учёта врагов на обычных этажах
	local blindLow, blindLowAt, blindGap, blindGapAt = 1, 0, 0, 0
	for number = 1, lastFloor do
		if number % 5 == 0 then
			continue
		end
		if previous and math.abs(share[number] - share[previous]) > worstGap then
			worstGap, worstAt = math.abs(share[number] - share[previous]), number
		end
		previous = number
		if blind[number] < blindLow then
			blindLow, blindLowAt = blind[number], number
		end
		if share[number] - blind[number] > blindGap then
			blindGap, blindGapAt = share[number] - blind[number], number
		end
	end
	table.insert(
		lines,
		string.format(
			"В3. Наибольший разрыв между соседними обычными этажами: %.1f п.п. (на этаже %d). Цель: не больше 20.%s",
			worstGap * 100,
			worstAt,
			mark(worstGap <= 0.2)
		)
	)
	local limitShare = bossLimit / math.max(1, bossCount)
	table.insert(
		lines,
		string.format(
			"В3. Бои с боссом, дошедшие до предела раундов: %s. Цель: не больше 10%%.%s",
			percent(limitShare),
			mark(limitShare <= 0.1)
		)
	)
	table.insert(
		lines,
		string.format(
			"В5. «Авто» без учёта врагов, обычные этажи: худший %s (этаж %d). Цель: от 55%%.%s",
			percent(blindLow),
			blindLowAt,
			mark(blindLow >= 0.55)
		)
	)
	table.insert(
		lines,
		string.format(
			"В5. Наибольший выигрыш от учёта врагов: %.1f п.п. (этаж %d). Больше 20 — типы решают слишком много.%s",
			blindGap * 100,
			blindGapAt,
			mark(blindGap <= 0.2)
		)
	)

	table.insert(
		lines,
		string.format(
			"В4. Решает ли уровень. Цель: на %d уровня ниже обычный этаж под 50%%, на %d выше — босс от 80%%.",
			SHIFT_LEVELS,
			SHIFT_LEVELS
		)
	)
	for _, boss in SHIFT_FLOORS do
		if boss > lastFloor then
			continue
		end
		-- этажи из списка — боссы, поэтому «обычный этаж» берётся соседний снизу
		local plain = boss - 1
		local below = floorRun(plain, poolCreatures(plain, math.max(1, plain - SHIFT_LEVELS)), true, perFloor, rng)
		local above = floorRun(boss, poolCreatures(boss, boss + SHIFT_LEVELS), true, perFloor, rng)
		table.insert(
			lines,
			string.format(
				"  этаж %2d, уровень %2d: %6s%s   босс %2d, уровень %2d: %6s%s",
				plain,
				math.max(1, plain - SHIFT_LEVELS),
				percent(below),
				mark(below < 0.5),
				boss,
				boss + SHIFT_LEVELS,
				percent(above),
				mark(above >= 0.8)
			)
		)
	end

	-- В7: первый босс глазами ребёнка
	local firstBoss = 5
	local starters, chocolate = {}, {}
	for index = 1, STARTERS do
		starters[GameData.RecipeOrder[index]] = firstBoss
		chocolate[GameData.RecipeOrder[STARTERS + index]] = firstBoss
	end
	local starterShare = floorRun(firstBoss, starters, true, perFloor, rng)
	local chocolateShare = floorRun(firstBoss, chocolate, true, perFloor, rng)
	table.insert(lines, "В7. Первый босс, зверьки 5-го уровня.")
	table.insert(
		lines,
		string.format(
			"  три стартовых: %s. Цель: 25–45%%.%s",
			percent(starterShare),
			mark(starterShare >= 0.25 and starterShare <= 0.45)
		)
	)
	table.insert(
		lines,
		string.format(
			"  три шоколадных: %s. Цель: 60–85%%.%s",
			percent(chocolateShare),
			mark(chocolateShare >= 0.6 and chocolateShare <= 0.85)
		)
	)
end

-- Сколько уровней сверх этажа нужно эталонному игроку, чтобы побеждать хотя бы в половине боёв.
-- Доля побед на уровне этажа скачет между 0% и 100%: исход почти предрешён составом. Запас в уровнях
-- показывает то же ровнее — насколько этаж труднее или легче своего номера.
local function levelsNeeded(lastFloor: number, perStep: number, rng: Random, lines: { string })
	table.insert(
		lines,
		string.format(
			"Запас уровня: на сколько уровней выше этажа нужно быть для 50%% побед (от %d до +%d, по %d боёв на шаг).",
			-NEED_RANGE,
			NEED_RANGE,
			perStep
		)
	)
	local plain, boss = {}, {}
	for number = 1, lastFloor do
		local need = NEED_RANGE + 1
		for shift = -NEED_RANGE, NEED_RANGE do
			local level = math.min(number, LEVEL_CAP) + shift
			if level >= 1 and floorRun(number, poolCreatures(number, level), true, perStep, rng) >= 0.5 then
				need = shift
				break
			end
		end
		table.insert(if number % 5 == 0 then boss else plain, string.format("%d", need))
	end
	table.insert(lines, "  обычные этажи по порядку: " .. table.concat(plain, " "))
	table.insert(lines, "  боссы по порядку: " .. table.concat(boss, " "))
end

function BattleSim.duels(perPair: number?): string
	local lines: { string } = {}
	duels(perPair or 200, Random.new(SEED), lines)
	return table.concat(lines, "\n")
end

function BattleSim.teams(count: number?): string
	local lines: { string } = {}
	teamFights(count or 3000, Random.new(SEED + 1), lines)
	return table.concat(lines, "\n")
end

function BattleSim.tower(lastFloor: number?, perFloor: number?): string
	local lines: { string } = {}
	towerFloors(lastFloor or 50, perFloor or 300, Random.new(SEED + 2), lines)
	return table.concat(lines, "\n")
end

function BattleSim.levels(lastFloor: number?, perStep: number?): string
	local lines: { string } = {}
	levelsNeeded(lastFloor or 50, perStep or 100, Random.new(SEED + 3), lines)
	return table.concat(lines, "\n")
end

function BattleSim.run(): string
	return table.concat({ BattleSim.duels(), BattleSim.teams(), BattleSim.tower(), BattleSim.levels() }, "\n")
end

return BattleSim
