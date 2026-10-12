--!strict
-- Бои игроков: кто сейчас дерётся, фазы и таймеры, награды.
-- Правила раунда — в BattleEngine, ринг в мире — в Ring. Сейчас есть только башня (бой с ботом).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BattleRules = require(Shared:WaitForChild("BattleRules"))
local GameData = require(Shared:WaitForChild("GameData"))
local Tower = require(Shared:WaitForChild("Tower"))
local BattleEngine = require(script.Parent.BattleEngine)
local Ring = require(script.Parent.Ring)
local Saves = require(script.Parent.Saves)

local RULES = GameData.Battle
local BOT_RANDOM = 0.25 -- как часто бот ходит наугад
local BOSS_RANDOM = 0.1
local REMOTE_COOLDOWN = 0.15
local NOTE_WHITE = Color3.new(1, 1, 1)
local NOTE_GREEN = Color3.fromRGB(120, 230, 130)
local NOTE_BLUE = Color3.fromRGB(150, 220, 255)
local NOTE_YELLOW = Color3.fromRGB(255, 220, 110)

export type LevelChange = { level: number, leveledUp: boolean }

-- То, что сервису нужно от основного скрипта
export type Host = {
	profile: (Player) -> Saves.Profile?,
	plot: (Player) -> (Model?, number),
	income: (Player) -> number,
	-- выдаёт монеты и опыт команде, отмечает пройденный этаж; возвращает уровни зверьков после награды
	reward: (Player, number, number, { string }, number?) -> { [string]: LevelChange },
	teamChanged: (Player) -> (),
}

export type Remotes = {
	setTeam: RemoteEvent,
	start: RemoteEvent,
	action: RemoteEvent,
	pick: RemoteEvent,
	forfeit: RemoteEvent,
	event: RemoteEvent,
}

type Session = {
	id: number,
	player: Player,
	battle: BattleEngine.Battle,
	floor: Tower.Floor,
	teamKeys: { string },
	ring: Model,
	phase: string, -- intro | choose | resolve | replace | ended
	deadline: number,
	choice: string?,
	pick: number?,
	forfeited: boolean,
	cancelled: boolean, -- игрок вышел: бой обрывается без наград
}

local BattleService = {}

local host: Host
local remotes: Remotes
local sessions: { [Player]: Session } = {}
local lastRemote: { [Player]: number } = {}
local nextId = 0

local function allowRemote(player: Player): boolean
	local now = os.clock()
	if now - (lastRemote[player] or 0) < REMOTE_COOLDOWN then
		return false
	end
	lastRemote[player] = now
	return true
end

-- Команда игрока на бой: сохранённая, а если её нет — трое сильнейших
local function teamOf(profile: Saves.Profile): { string }
	local keys = {}
	for _, key in profile.team do
		if profile.creatures[key] and not table.find(keys, key) and #keys < GameData.TEAM_SIZE then
			table.insert(keys, key)
		end
	end
	if #keys == 0 then
		return BattleRules.autoTeam(profile.creatures)
	end
	return keys
end

local function sideView(side: BattleEngine.Side)
	local team = {}
	for index, fighter in side.team do
		team[index] = {
			key = fighter.key,
			level = fighter.level,
			hp = fighter.hp,
			hpMax = fighter.hpMax,
			atk = fighter.atk,
			spd = fighter.spd,
			skills = fighter.skills,
			cooldown = fighter.cooldown,
			shield = fighter.shield > 0,
			slow = fighter.slow > 0,
			frozen = fighter.frozen,
			giant = fighter.giant,
		}
	end
	return { team = team, active = side.active }
end

-- Каждое сообщение несёт полный снимок боя: клиенту не нужно ничего досчитывать самому
local function send(session: Session, kind: string, extra: { [string]: any }?)
	local message: { [string]: any } = extra or {}
	message.kind = kind
	message.id = session.id
	message.round = session.battle.round
	message.deadline = session.deadline
	message.you = sideView(session.battle.sides[1])
	message.foe = sideView(session.battle.sides[2])
	remotes.event:FireClient(session.player, message)
end

-- Ждёт выбора игрока до срока; выходит раньше, если бой оборвался
local function waitFor(session: Session, ready: () -> boolean)
	while
		not ready()
		and not session.cancelled
		and not session.forfeited
		and workspace:GetServerTimeNow() < session.deadline
	do
		task.wait(0.05)
	end
end

local function deadlineIn(session: Session, seconds: number)
	session.deadline = workspace:GetServerTimeNow() + seconds
end

-- Показывает раунд на ринге в том же темпе, в каком его проигрывает клиент
local function playOnRing(session: Session, events: { BattleEngine.Event })
	local battle = session.battle
	for _, event in events do
		if session.cancelled then
			return
		end
		local other = 3 - event.side
		if event.kind == "hit" then
			local actor, target = BattleEngine.active(battle, event.side), BattleEngine.active(battle, other)
			Ring.lunge(session.ring, event.side)
			local text = "-" .. tostring(event.damage)
			if event.crit then
				text ..= " Крит!"
			end
			if event.matchup == "strong" then
				text ..= " Сильно!"
			elseif event.matchup == "weak" then
				text ..= " Слабо…"
			end
			Ring.note(session.ring, other, text, if event.crit then NOTE_YELLOW else NOTE_WHITE)
			Ring.setHp(session.ring, other, event.targetHp or 0, target.hpMax)
			if event.heal and event.heal > 0 then
				Ring.note(session.ring, event.side, "+" .. event.heal, NOTE_GREEN)
				Ring.setHp(session.ring, event.side, event.actorHp or actor.hp, actor.hpMax)
			end
			task.wait(RULES.actionTime)
		elseif event.kind == "skip" then
			Ring.note(session.ring, event.side, "Заморожен", NOTE_BLUE)
			task.wait(RULES.actionTime)
		elseif event.kind == "ko" then
			Ring.remove(session.ring, event.side)
			task.wait(RULES.koTime)
		end
	end
end

local function finish(session: Session, winner: number?, technical: boolean)
	local player = session.player
	session.phase = "ended"
	sessions[player] = nil
	if session.cancelled then
		return
	end

	local number = session.floor.number
	local won = winner == 1
	local coins, xp = 0, 0
	local cleared: number? = nil
	if won then
		coins = Tower.winCoins(number, host.income(player))
		xp = Tower.winXp(number)
		cleared = number
	elseif not technical then
		-- сдача и пропуск ходов опыта не дают: иначе его можно набивать, не играя
		xp = Tower.loseXp(number)
	end
	local levels = host.reward(player, coins, xp, session.teamKeys, cleared)
	send(session, "end", {
		result = if won then "win" else "lose",
		floor = number,
		coins = coins,
		xp = xp,
		levels = levels,
		nextOpen = number < GameData.TOWER_FLOORS_OPEN,
	})
	-- ринг убираем чуть позже: исход должны успеть увидеть соседи
	task.delay(1.5, Ring.close, session.ring)
end

local function runTower(session: Session)
	local battle = session.battle
	local rng = Random.new()
	local randomChance = if session.floor.boss then BOSS_RANDOM else BOT_RANDOM

	send(session, "start", {
		floor = session.floor.number,
		boss = session.floor.boss,
		camera = Ring.camera(session.ring:GetAttribute("PlotIndex") :: number),
	})
	task.wait(RULES.introTime)

	local winner: number? = nil
	local technical = false
	while not session.cancelled do
		-- выбор: замороженный зверёк не выбирает, раунд идёт сразу
		session.choice = nil
		if not BattleEngine.active(battle, 1).frozen then
			session.phase = "choose"
			deadlineIn(session, RULES.chooseTime)
			send(session, "choose")
			waitFor(session, function()
				return session.choice ~= nil
			end)
			if session.cancelled then
				break
			end
			local side = battle.sides[1]
			side.missed = if session.choice then 0 else side.missed + 1
			if session.forfeited or side.missed >= RULES.missedLimit then
				winner, technical = 2, true
				break
			end
		end

		session.phase = "resolve"
		local foeChoice = BattleEngine.botChoice(battle, 2, randomChance, rng)
		local played = battle.round
		local events = BattleEngine.resolveRound(battle, { session.choice, foeChoice }, rng)
		send(session, "round", { played = played, events = events })
		playOnRing(session, events)
		task.wait(RULES.roundPad)

		winner = BattleEngine.winner(battle)
		if winner or session.cancelled then
			break
		end

		-- замены: бот выходит первым, чтобы игрок выбирал, уже видя соперника
		if BattleEngine.needsReplacement(battle, 2) then
			BattleEngine.replace(battle, 2, BattleEngine.botReplacement(battle, 2, session.floor.boss))
			Ring.place(session.ring, 2, BattleEngine.active(battle, 2))
		end
		if BattleEngine.needsReplacement(battle, 1) then
			local reserves = BattleEngine.reserves(battle, 1)
			session.pick = nil
			if #reserves > 1 then
				session.phase = "replace"
				deadlineIn(session, RULES.replaceTime)
				send(session, "replace", { options = reserves })
				waitFor(session, function()
					return session.pick ~= nil
				end)
				if session.cancelled then
					break
				end
				if session.forfeited then
					winner, technical = 2, true
					break
				end
			end
			BattleEngine.replace(battle, 1, session.pick)
			Ring.place(session.ring, 1, BattleEngine.active(battle, 1))
		end
	end

	finish(session, winner, technical)
end

local function startTower(player: Player)
	local profile = host.profile(player)
	local plot, plotIndex = host.plot(player)
	if sessions[player] or not profile or not plot then
		return
	end
	local number = profile.tower + 1
	if number > GameData.TOWER_FLOORS_OPEN then
		return
	end
	local keys = teamOf(profile)
	if #keys == 0 then
		return
	end

	local team = {}
	for index, key in keys do
		team[index] = BattleEngine.towerFighter(key, profile.creatures[key])
	end
	local floor = Tower.floor(number)
	local battle = BattleEngine.new(team, BattleEngine.towerEnemies(floor))
	local ring = Ring.open(plot, plotIndex)
	Ring.place(ring, 1, BattleEngine.active(battle, 1))
	Ring.place(ring, 2, BattleEngine.active(battle, 2))

	nextId += 1
	local session: Session = {
		id = nextId,
		player = player,
		battle = battle,
		floor = floor,
		teamKeys = keys,
		ring = ring,
		phase = "intro",
		deadline = 0,
		choice = nil,
		pick = nil,
		forfeited = false,
		cancelled = false,
	}
	sessions[player] = session
	task.spawn(runTower, session)
end

-- Сессия игрока, если запрос относится к идущему бою и пришёл в нужной фазе
local function sessionFor(player: Player, id: unknown, phase: string): Session?
	local session = sessions[player]
	if not session or session.id ~= id or session.phase ~= phase then
		return nil
	end
	return session
end

function BattleService.busy(player: Player): boolean
	return sessions[player] ~= nil
end

-- Игрок вышел: бой обрывается без наград. Ринг уходит вместе с участком.
function BattleService.cancel(player: Player)
	local session = sessions[player]
	if session then
		session.cancelled = true
		sessions[player] = nil
	end
	lastRemote[player] = nil
end

function BattleService.start(newHost: Host, newRemotes: Remotes)
	host = newHost
	remotes = newRemotes

	-- Пустой список возвращает команду по умолчанию
	remotes.setTeam.OnServerEvent:Connect(function(player: Player, keys: unknown)
		local profile = host.profile(player)
		if not profile or not allowRemote(player) or typeof(keys) ~= "table" then
			return
		end
		local team = {}
		for index = 1, GameData.TEAM_SIZE do
			local key = (keys :: { unknown })[index]
			if typeof(key) ~= "string" then
				break
			end
			if not profile.creatures[key] or table.find(team, key) then
				return
			end
			table.insert(team, key)
		end
		profile.team = team
		host.teamChanged(player)
	end)

	remotes.start.OnServerEvent:Connect(function(player: Player, kind: unknown)
		if allowRemote(player) and kind == "tower" then
			startTower(player)
		end
	end)

	-- Первый принятый выбор остаётся: второй запрос в том же раунде игнорируется
	remotes.action.OnServerEvent:Connect(function(player: Player, id: unknown, round: unknown, skillId: unknown)
		local session = sessionFor(player, id, "choose")
		if not session or session.choice or round ~= session.battle.round or typeof(skillId) ~= "string" then
			return
		end
		if BattleEngine.canUse(BattleEngine.active(session.battle, 1), skillId) then
			session.choice = skillId
		end
	end)

	remotes.pick.OnServerEvent:Connect(function(player: Player, id: unknown, index: unknown)
		local session = sessionFor(player, id, "replace")
		if not session or session.pick or typeof(index) ~= "number" then
			return
		end
		if table.find(BattleEngine.reserves(session.battle, 1), index) then
			session.pick = index
		end
	end)

	remotes.forfeit.OnServerEvent:Connect(function(player: Player, id: unknown)
		local session = sessions[player]
		if session and session.id == id and (session.phase == "choose" or session.phase == "replace") then
			session.forfeited = true
		end
	end)
end

return BattleService
