--!strict
-- Проверка баланса: бои бот против бота по docs/battles.md, раздел 13. В игре не используется.
-- Запуск из Studio в режиме Play, на сервере:
--   print(require(game.ServerScriptService.Server.BattleSim).run())
-- В режиме Edit require отдаёт модули из кеша Studio: после правки файлов посчитается старая версия.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BattleRules = require(Shared:WaitForChild("BattleRules"))
local GameData = require(Shared:WaitForChild("GameData"))
local Tower = require(Shared:WaitForChild("Tower"))
local BattleEngine = require(script.Parent.BattleEngine)

local YIELD_EVERY = 400 -- боёв между паузами, чтобы не подвесить Studio

local BattleSim = {}

local battlesRun = 0

-- Доигрывает бой ботами. Возвращает победителя (0 — ничья) и число сыгранных раундов.
local function play(
	battle: BattleEngine.Battle,
	chance1: number,
	chance2: number,
	smart2: boolean,
	rng: Random
): (number, number)
	while true do
		local choices = {
			BattleEngine.botChoice(battle, 1, chance1, rng),
			BattleEngine.botChoice(battle, 2, chance2, rng),
		}
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

-- Все пары 1 на 1 на арене: доля побед каждого зверька и средняя длина боя
local function duels(perPair: number, rng: Random, lines: { string })
	local order = GameData.RecipeOrder
	local score, fights = {}, {}
	local rounds, total = 0, 0
	for _, key in order do
		score[key], fights[key] = 0, 0
	end
	for _, a in order do
		for _, b in order do
			for _ = 1, perPair do
				local battle = BattleEngine.new({ BattleEngine.arenaFighter(a) }, { BattleEngine.arenaFighter(b) })
				local winner, played = play(battle, 0, 0, false, rng)
				score[a] += if winner == 1 then 1 elseif winner == 0 then 0.5 else 0
				score[b] += if winner == 2 then 1 elseif winner == 0 then 0.5 else 0
				fights[a] += 1
				fights[b] += 1
				rounds += played
				total += 1
			end
		end
	end

	table.insert(
		lines,
		string.format(
			"1 на 1, арена, %d боёв. Цель: у каждого 40–60%% побед, 3–4 раунда.",
			total
		)
	)
	table.insert(lines, string.format("  средняя длина: %.2f раунда", rounds / total))
	local outside = 0
	for _, key in order do
		local share = score[key] / fights[key]
		local mark = ""
		if share < 0.4 or share > 0.6 then
			mark = "  <-- вне коридора"
			outside += 1
		end
		table.insert(lines, string.format("  %-22s %s%s", GameData.Recipes[key].name, percent(share), mark))
	end
	table.insert(lines, string.format("  вне коридора: %d из %d", outside, #order))
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

-- Случайные бои 3 на 3 на арене: длина боя и влияние скорости лидера
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
	table.insert(
		lines,
		string.format(
			"3 на 3, арена, %d боёв. Цель: медиана 8–12 раундов, до предела не больше 5%%.",
			count
		)
	)
	table.insert(lines, string.format("  медиана: %d раундов", lengths[math.ceil(#lengths / 2)]))
	table.insert(lines, "  дошли до предела раундов: " .. percent(atLimit / count))
	table.insert(
		lines,
		"  побеждает сторона с более быстрым лидером: "
			.. percent(fasterWins / fasterFights)
			.. " (цель — не больше 60%)"
	)
end

-- Этажи башни: команда «Авто» уровня этажа против врагов этажа.
-- Игроку даются те же рецепты, из которых набраны враги: на раннем этаже у него ещё нет ледяных зверьков.
local function towerFloors(lastFloor: number, perFloor: number, rng: Random, lines: { string })
	table.insert(
		lines,
		string.format(
			"Башня, этажи 1–%d, по %d боёв. Цель: обычный этаж от 70%%, босс 40–60%%.",
			lastFloor,
			perFloor
		)
	)
	for number = 1, lastFloor do
		local floor = Tower.floor(number)
		local creatures = {}
		for index = 1, Tower.poolSize(number) do
			creatures[GameData.RecipeOrder[index]] = number
		end
		local keys = BattleRules.autoTeam(creatures)
		local wins = 0
		for _ = 1, perFloor do
			local team = {}
			for index, key in keys do
				team[index] = BattleEngine.towerFighter(key, number)
			end
			local battle = BattleEngine.new(team, BattleEngine.towerEnemies(floor))
			local winner = play(battle, 0, if floor.boss then 0.1 else 0.25, floor.boss, rng)
			if winner == 1 then
				wins += 1
			end
		end
		local share = wins / perFloor
		local ok = if floor.boss then share >= 0.4 and share <= 0.6 else share >= 0.7
		table.insert(
			lines,
			string.format(
				"  этаж %2d%s %s%s",
				number,
				if floor.boss then " босс" else "     ",
				percent(share),
				if ok then "" else "  <-- вне цели"
			)
		)
	end
end

function BattleSim.run(perPair: number?, teamBattles: number?, lastFloor: number?, perFloor: number?): string
	local rng = Random.new(20261012)
	local lines: { string } = {}
	duels(perPair or 200, rng, lines)
	teamFights(teamBattles or 1000, rng, lines)
	towerFloors(lastFloor or 30, perFloor or 200, rng, lines)
	return table.concat(lines, "\n")
end

return BattleSim
