--!strict
-- Правила боя без мира и сети: собирает бойцов, считает раунд, выбирает за бота.
-- Один и тот же код ведёт бой игрока и прогоняет тысячи боёв для проверки баланса (BattleSim).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BattleRules = require(Shared:WaitForChild("BattleRules"))
local GameData = require(Shared:WaitForChild("GameData"))
local Tower = require(Shared:WaitForChild("Tower"))

local RULES = GameData.Battle
-- Сроки статусов в раундах. Счётчики уменьшаются в конце раунда, поэтому к сроку прибавлен раунд наложения.
local SHIELD_ROUNDS = 2 -- до конца следующего раунда
local SLOW_ROUNDS = 3 -- два следующих раунда
local FREEZE_IMMUNE_ROUNDS = 3 -- два раунда после пропущенного хода

export type Fighter = {
	key: string,
	level: number,
	hpMax: number,
	hp: number,
	atk: number,
	spd: number,
	skills: { string },
	cooldown: { [string]: number },
	shield: number,
	slow: number,
	freezeImmune: number,
	frozen: boolean,
	giant: boolean,
}

export type Side = { team: { Fighter }, active: number, missed: number }

export type Battle = { round: number, sides: { Side } }

export type Event = {
	kind: string, -- "hit" | "skip" | "ko"
	side: number, -- кто действует; для "ko" — чья сторона потеряла зверька
	skill: string?,
	damage: number?,
	crit: boolean?,
	matchup: string?, -- "strong" | "weak"
	shielded: boolean?,
	heal: number?,
	applied: string?, -- "shield" | "slow" | "freeze"
	immune: boolean?, -- заморозка не прошла
	targetHp: number?,
	actorHp: number?,
}

local BattleEngine = {}

local function newFighter(key: string, level: number, hp: number, atk: number, spd: number, skills: { string }): Fighter
	return {
		key = key,
		level = level,
		hpMax = hp,
		hp = hp,
		atk = atk,
		spd = spd,
		skills = skills,
		cooldown = {},
		shield = 0,
		slow = 0,
		freezeImmune = 0,
		frozen = false,
		giant = false,
	}
end

-- Боец с настоящими статами: башня
function BattleEngine.towerFighter(key: string, level: number): Fighter
	local hp, atk, spd = BattleRules.stats(key, level)
	return newFighter(key, level, hp, atk, spd, BattleRules.skillsOf(key, level, false))
end

-- Боец с уравненными статами и обоими скиллами: арена
function BattleEngine.arenaFighter(key: string): Fighter
	local hp, atk, spd = BattleRules.arenaStats(key)
	return newFighter(key, 1, hp, atk, spd, BattleRules.skillsOf(key, 1, true))
end

function BattleEngine.towerEnemies(floor: Tower.Floor): { Fighter }
	local team = {}
	for index, key in floor.enemies do
		local fighter = BattleEngine.towerFighter(key, floor.level)
		fighter.hpMax = math.floor(fighter.hpMax * floor.scale + 0.5)
		fighter.atk = math.floor(fighter.atk * floor.scale + 0.5)
		if floor.boss and index == 1 then
			fighter.giant = true
			fighter.hpMax *= 2
		end
		fighter.hp = fighter.hpMax
		team[index] = fighter
	end
	return team
end

function BattleEngine.new(teamA: { Fighter }, teamB: { Fighter }): Battle
	return {
		round = 1,
		sides = { { team = teamA, active = 1, missed = 0 }, { team = teamB, active = 1, missed = 0 } },
	}
end

function BattleEngine.active(battle: Battle, sideIndex: number): Fighter
	local side = battle.sides[sideIndex]
	return side.team[side.active]
end

function BattleEngine.canUse(fighter: Fighter, skillId: string): boolean
	return table.find(fighter.skills, skillId) ~= nil and (fighter.cooldown[skillId] or 0) == 0
end

-- Кнопки, которые сейчас можно нажать. «Кусь» доступен всегда.
function BattleEngine.options(fighter: Fighter): { string }
	local options = {}
	for _, skillId in fighter.skills do
		if (fighter.cooldown[skillId] or 0) == 0 then
			table.insert(options, skillId)
		end
	end
	return options
end

local function anyAlive(side: Side): boolean
	for _, fighter in side.team do
		if fighter.hp > 0 then
			return true
		end
	end
	return false
end

-- Доля оставшегося здоровья команды: по ней решается бой, не кончившийся за предел раундов
local function healthShare(side: Side): number
	local hp, hpMax = 0, 0
	for _, fighter in side.team do
		hp += fighter.hp
		hpMax += fighter.hpMax
	end
	return hp / hpMax
end

-- Кто ходит первым: «Радужный луч», затем скорость с учётом замедления, при равенстве — жребий
local function firstToAct(battle: Battle, choices: { string? }, rng: Random): number
	local priority, speed = {}, {}
	for sideIndex = 1, 2 do
		local fighter = BattleEngine.active(battle, sideIndex)
		local skillId = choices[sideIndex]
		local skill = if skillId then GameData.Skills[skillId] else nil
		priority[sideIndex] = if skill and skill.effect == "first" and not fighter.frozen then 1 else 0
		speed[sideIndex] = if fighter.slow > 0 then fighter.spd * 0.5 else fighter.spd
	end
	if priority[1] ~= priority[2] then
		return if priority[1] > priority[2] then 1 else 2
	elseif speed[1] ~= speed[2] then
		return if speed[1] > speed[2] then 1 else 2
	end
	return rng:NextInteger(1, 2)
end

local function act(battle: Battle, sideIndex: number, skillId: string, rng: Random, events: { Event })
	local actor = BattleEngine.active(battle, sideIndex)
	local target = BattleEngine.active(battle, 3 - sideIndex)

	if actor.frozen then
		actor.frozen = false
		actor.freezeImmune = FREEZE_IMMUNE_ROUNDS
		table.insert(events, { kind = "skip", side = sideIndex })
		return
	end

	local skill = GameData.Skills[skillId]
	local multiplier, matchup = BattleRules.typeMultiplier(skill.type, target.key)
	local crit = rng:NextNumber() < RULES.critChance
	local shielded = target.shield > 0
	local spread = rng:NextInteger(90, 110) / 100
	local damage = math.max(
		1,
		math.floor(
			actor.atk
				* skill.power
				/ 100
				* multiplier
				* (if crit then RULES.critMultiplier else 1)
				* (if shielded then RULES.shieldMultiplier else 1)
				* spread
		)
	)
	if shielded then
		target.shield = 0
	end
	target.hp = math.max(0, target.hp - damage)
	if skill.cooldown > 0 then
		-- плюс один: счётчик уменьшится уже в конце этого раунда
		actor.cooldown[skillId] = skill.cooldown + 1
	end

	local event: Event = {
		kind = "hit",
		side = sideIndex,
		skill = skillId,
		damage = damage,
		crit = crit,
		matchup = matchup,
		shielded = shielded,
	}
	if skill.effect == "shield" then
		actor.shield = SHIELD_ROUNDS
		event.applied = "shield"
	elseif skill.effect == "heal" then
		local heal = math.min(actor.hpMax - actor.hp, math.floor(damage * RULES.healShare))
		actor.hp += heal
		event.heal = heal
	elseif skill.effect == "slow" and target.hp > 0 then
		target.slow = SLOW_ROUNDS
		event.applied = "slow"
	elseif skill.effect == "freeze" and target.hp > 0 then
		if target.freezeImmune > 0 then
			event.immune = true
		else
			target.frozen = true
			event.applied = "freeze"
		end
	end
	event.targetHp = target.hp
	event.actorHp = actor.hp
	table.insert(events, event)

	if target.hp <= 0 then
		table.insert(events, { kind = "ko", side = 3 - sideIndex })
	end
end

local function tick(fighter: Fighter)
	for skillId, rounds in fighter.cooldown do
		fighter.cooldown[skillId] = math.max(0, rounds - 1)
	end
	fighter.shield = math.max(0, fighter.shield - 1)
	fighter.slow = math.max(0, fighter.slow - 1)
	fighter.freezeImmune = math.max(0, fighter.freezeImmune - 1)
end

-- Считает один раунд и возвращает, что произошло, по порядку. choices[сторона] — id скилла;
-- nil или недоступный скилл считается «Кусем». Нокаутированный в этом раунде уже не ходит.
function BattleEngine.resolveRound(battle: Battle, choices: { string? }, rng: Random): { Event }
	local events: { Event } = {}
	local first = firstToAct(battle, choices, rng)
	for _, sideIndex in { first, 3 - first } do
		local actor = BattleEngine.active(battle, sideIndex)
		if actor.hp > 0 then
			local skillId = choices[sideIndex]
			if not skillId or not BattleEngine.canUse(actor, skillId) then
				skillId = "bite"
			end
			act(battle, sideIndex, skillId, rng, events)
		end
	end
	for sideIndex = 1, 2 do
		local fighter = BattleEngine.active(battle, sideIndex)
		if fighter.hp > 0 then
			tick(fighter)
		end
	end
	battle.round += 1
	return events
end

-- Победитель: 1 или 2, 0 — ничья, nil — бой продолжается
function BattleEngine.winner(battle: Battle): number?
	local alive1, alive2 = anyAlive(battle.sides[1]), anyAlive(battle.sides[2])
	if not alive2 then
		return 1
	elseif not alive1 then
		return 2
	elseif battle.round > RULES.roundLimit then
		local share1, share2 = healthShare(battle.sides[1]), healthShare(battle.sides[2])
		if math.abs(share1 - share2) < 0.001 then
			return 0
		end
		return if share1 > share2 then 1 else 2
	end
	return nil
end

-- Зверёк на поле выбыл, но у стороны есть кем заменить
function BattleEngine.needsReplacement(battle: Battle, sideIndex: number): boolean
	return BattleEngine.active(battle, sideIndex).hp <= 0 and anyAlive(battle.sides[sideIndex])
end

-- Номера живых зверьков по порядку команды
function BattleEngine.reserves(battle: Battle, sideIndex: number): { number }
	local indices = {}
	for index, fighter in battle.sides[sideIndex].team do
		if fighter.hp > 0 then
			table.insert(indices, index)
		end
	end
	return indices
end

-- Выпускает зверька. Неверный номер заменяется первым живым по порядку команды.
function BattleEngine.replace(battle: Battle, sideIndex: number, index: number?)
	local side = battle.sides[sideIndex]
	local fighter = if index then side.team[index] else nil
	if not fighter or fighter.hp <= 0 then
		index = BattleEngine.reserves(battle, sideIndex)[1]
	end
	side.active = index :: number
end

-- Насколько хорош скилл против соперника на поле: сила, умноженная на типовой множитель
local function skillValue(skillId: string, targetKey: string): number
	local skill = GameData.Skills[skillId]
	return skill.power * BattleRules.typeMultiplier(skill.type, targetKey)
end

-- Бот берёт лучший по силе и типу скилл; с вероятностью randomChance — случайный из доступных
function BattleEngine.botChoice(battle: Battle, sideIndex: number, randomChance: number, rng: Random): string?
	local actor = BattleEngine.active(battle, sideIndex)
	if actor.frozen then
		return nil
	end
	local options = BattleEngine.options(actor)
	if rng:NextNumber() < randomChance then
		return options[rng:NextInteger(1, #options)]
	end
	local targetKey = BattleEngine.active(battle, 3 - sideIndex).key
	local best, bestValue = options[1], -1
	for _, skillId in options do
		local value = skillValue(skillId, targetKey)
		if value > bestValue then
			best, bestValue = skillId, value
		end
	end
	return best
end

-- Кого бот выпускает после нокаута: следующего по порядку, а «умный» — того, чей скилл лучше ложится на соперника
function BattleEngine.botReplacement(battle: Battle, sideIndex: number, smart: boolean): number
	local reserves = BattleEngine.reserves(battle, sideIndex)
	if not smart then
		return reserves[1]
	end
	local targetKey = BattleEngine.active(battle, 3 - sideIndex).key
	local best, bestValue = reserves[1], -1
	for _, index in reserves do
		local fighter = battle.sides[sideIndex].team[index]
		for _, skillId in fighter.skills do
			local value = skillValue(skillId, targetKey)
			if value > bestValue then
				best, bestValue = index, value
			end
		end
	end
	return best
end

return BattleEngine
