--!strict
-- Сервер «Пекарни монстриков»: игроки, ремоуты и общий цикл.
-- Клиент присылает только намерения; монеты, опыт и печи считаются здесь.
-- Правила — в Bakery, мир — в Plots и Board, данные — в Saves и Leaderboards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local GameData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameData"))
local Bakery = require(script.Parent.Bakery)
local BattleService = require(script.Parent.BattleService)
local Board = require(script.Parent.Board)
local Leaderboards = require(script.Parent.Leaderboards)
local Plots = require(script.Parent.Plots)
local Saves = require(script.Parent.Saves)

local TICK = 0.2
local AUTOSAVE_INTERVAL = 60
local REMOTE_COOLDOWN = 0.2

type State = {
	profile: Saves.Profile,
	plotIndex: number,
	plot: Model,
	lastRemote: number,
}

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function newRemote(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
	return remote
end
local stateRemote = newRemote("State")
local bakeRemote = newRemote("Bake")
local stopOvenRemote = newRemote("StopOven")
local reigniteRemote = newRemote("Reignite")
local buyRemote = newRemote("Buy")
local buyOvenRemote = newRemote("BuyOven")
local upgradeOvenRemote = newRemote("UpgradeOven")
local bakedRemote = newRemote("Baked")
local notifyRemote = newRemote("Notify")
local awayRemote = newRemote("Away")
local placedRemote = newRemote("Placed")
local leaderboardRemote = newRemote("Leaderboard")
local battleRemotes: BattleService.Remotes = {
	setTeam = newRemote("SetTeam"),
	start = newRemote("BattleStart"),
	action = newRemote("BattleAction"),
	pick = newRemote("BattlePick"),
	forfeit = newRemote("BattleForfeit"),
	event = newRemote("BattleEvent"),
}
remotes.Parent = ReplicatedStorage

local states: { [Player]: State } = {}
local plotOwners: { [number]: Player } = {}
-- Чьё-то мастерство или состав сервера изменились: таблицу надо разослать заново
local boardDirty = true

-- Состояние

local function pushState(player: Player, state: State)
	local profile = state.profile
	stateRemote:FireClient(player, {
		coins = math.floor(profile.coins),
		income = Bakery.income(profile),
		unlocked = profile.unlocked,
		creatures = profile.creatures,
		xp = profile.xp,
		golden = profile.golden,
		ovens = profile.ovens,
		cap = GameData.levelCap(profile.diploma),
		tower = profile.tower,
		team = profile.team,
	})
end

local function refreshSlotPad(player: Player, state: State)
	Plots.setSlotPads(state.plot, state.plotIndex, #state.profile.ovens, state.profile.coins, player.UserId)
end

local function showBake(player: Player, state: State, slot: number, result: Bakery.BakeResult)
	Plots.showCreature(
		state.plot,
		state.plotIndex,
		result.key,
		result.level,
		state.profile.golden[result.key] == true,
		Plots.ovenExit(state.plot, slot)
	)
	bakedRemote:FireClient(player, {
		oven = slot,
		key = result.key,
		isNew = result.isNew,
		golden = result.golden,
		level = result.level,
		leveledUp = result.leveledUp,
	})
end

-- Таблица «Сервер»: считается из памяти, поэтому обновляется сразу
local function serverRows(): { Leaderboards.Row }
	local rows: { Leaderboards.Row } = {}
	for player, state in states do
		table.insert(rows, { userId = player.UserId, name = player.Name, value = Bakery.mastery(state.profile) })
	end
	table.sort(rows, function(x, y)
		if x.value ~= y.value then
			return x.value > y.value
		end
		return x.userId < y.userId
	end)
	return rows
end

-- Мировой топ меняется раз в две минуты, поэтому его строки шлём, только когда он обновился
local function broadcastBoard(withWorld: boolean)
	local rows = serverRows()
	local top = Leaderboards.top()
	leaderboardRemote:FireAllClients({ server = rows, world = if withWorld then top else nil })
	Board.show(top, rows[1])
	for _, state in states do
		Plots.setMastery(state.plot, Bakery.mastery(state.profile))
	end
end

-- Возвращает false, если игрок шлёт запросы слишком часто
local function allowRemote(state: State): boolean
	local now = os.clock()
	if now - state.lastRemote < REMOTE_COOLDOWN then
		return false
	end
	state.lastRemote = now
	return true
end

-- Печь игрока по номеру из запроса. Номер приходит от клиента, поэтому может быть чем угодно.
local function ovenAt(state: State, slot: unknown): (Saves.Oven?, number)
	if typeof(slot) ~= "number" or slot % 1 ~= 0 then
		return nil, 0
	end
	return state.profile.ovens[slot], slot
end

local function reignite(state: State, slot: number, at: number): boolean
	local profile = state.profile
	local oven = profile.ovens[slot]
	if not oven or oven.startedAt or not oven.key or not Bakery.canBake(profile, oven.key) then
		return false
	end
	Bakery.startBake(profile, oven, oven.key, at, true)
	Plots.setOvenGlow(state.plot, slot, true)
	return true
end

-- Ремоуты

bakeRemote.OnServerEvent:Connect(function(player: Player, slot: unknown, a: unknown, b: unknown, withRepeat: unknown)
	local state = states[player]
	if not state or not allowRemote(state) then
		return
	end
	local oven, index = ovenAt(state, slot)
	if not oven or oven.startedAt then
		return
	end
	if typeof(a) ~= "string" or typeof(b) ~= "string" or a == b then
		return
	end
	local profile = state.profile
	if not profile.unlocked[a] or not profile.unlocked[b] then
		return
	end
	local key = GameData.recipeKey(a, b)
	if not GameData.Recipes[key] or not Bakery.canBake(profile, key) then
		return
	end
	Bakery.startBake(profile, oven, key, workspace:GetServerTimeNow(), withRepeat == true)
	Plots.setOvenGlow(state.plot, index, true)
	pushState(player, state)
end)

-- Текущая выпечка допекается, после неё печь остывает
stopOvenRemote.OnServerEvent:Connect(function(player: Player, slot: unknown)
	local state = states[player]
	if not state or not allowRemote(state) then
		return
	end
	local oven = ovenAt(state, slot)
	if not oven or not oven.startedAt then
		return
	end
	oven.repeatOn = false
	oven.heatUntil = nil
	pushState(player, state)
end)

-- slot = 0 разжигает все остывшие печи
reigniteRemote.OnServerEvent:Connect(function(player: Player, slot: unknown)
	local state = states[player]
	if not state or not allowRemote(state) or typeof(slot) ~= "number" then
		return
	end
	local at = workspace:GetServerTimeNow()
	local changed = false
	if slot == 0 then
		for index in state.profile.ovens do
			changed = reignite(state, index, at) or changed
		end
	else
		changed = reignite(state, slot, at)
	end
	if changed then
		pushState(player, state)
	end
end)

buyRemote.OnServerEvent:Connect(function(player: Player, id: unknown)
	local state = states[player]
	if not state or not allowRemote(state) or typeof(id) ~= "string" then
		return
	end
	local profile = state.profile
	local ingredient = GameData.IngredientById[id]
	if not ingredient or profile.unlocked[id] or profile.coins < ingredient.price then
		return
	end
	profile.coins -= ingredient.price
	profile.unlocked[id] = true
	notifyRemote:FireClient(player, ingredient.emoji .. " Новый ингредиент: " .. ingredient.name .. "!")
	refreshSlotPad(player, state)
	pushState(player, state)
end)

buyOvenRemote.OnServerEvent:Connect(function(player: Player)
	local state = states[player]
	if not state or not allowRemote(state) then
		return
	end
	local profile = state.profile
	local slot = #profile.ovens + 1
	local price = GameData.OvenSlotPrices[slot]
	if not price or profile.coins < price then
		return
	end
	profile.coins -= price
	table.insert(profile.ovens, { tier = 1 })
	-- площадку убираем до постройки: печь встаёт на её место
	refreshSlotPad(player, state)
	Plots.addOven(state.plot, state.plotIndex, slot, 1, player.UserId)
	notifyRemote:FireClient(player, "Новая печь! Теперь их " .. slot)
	pushState(player, state)
end)

-- Скорость новой ступени действует со следующей выпечки, жар — со следующего розжига
upgradeOvenRemote.OnServerEvent:Connect(function(player: Player, slot: unknown)
	local state = states[player]
	if not state or not allowRemote(state) then
		return
	end
	local oven, index = ovenAt(state, slot)
	if not oven then
		return
	end
	local profile = state.profile
	local nextTier = GameData.OvenTiers[oven.tier + 1]
	if not nextTier or profile.coins < nextTier.price then
		return
	end
	profile.coins -= nextTier.price
	oven.tier += 1
	Plots.setOvenTier(state.plot, index, oven.tier)
	notifyRemote:FireClient(player, "Печь " .. index .. " теперь " .. nextTier.name .. "!")
	refreshSlotPad(player, state)
	pushState(player, state)
end)

-- Игроки

local function placeCharacter(player: Player, character: Model, plotIndex: number)
	character:WaitForChild("HumanoidRootPart", 10)
	task.wait(0.1)
	if character.Parent then
		local at = Plots.spawnCFrame(plotIndex)
		character:PivotTo(at)
		-- камера клиента к этому моменту уже встала по старому положению персонажа и сама к печи не повернётся
		placedRemote:FireClient(player, at)
	end
end

local function onPlayerAdded(player: Player)
	local plotIndex: number? = nil
	for index = 1, Plots.PLOT_COUNT do
		if not plotOwners[index] then
			plotIndex = index
			break
		end
	end
	if not plotIndex then
		player:Kick("Все пекарни на этом сервере заняты, попробуй ещё раз.")
		return
	end
	plotOwners[plotIndex] = player

	local profile = Saves.load(player)
	if not player:IsDescendantOf(Players) then
		plotOwners[plotIndex] = nil
		return
	end

	-- Пока игрока не было: доход считается по зверькам на момент выхода, печи допекают то, что успели
	local offlineCoins, offlineBakes = 0, 0
	if profile.lastSeen then
		local away = math.clamp(os.time() - profile.lastSeen, 0, GameData.OFFLINE_CAP_SECONDS)
		offlineCoins = math.floor(away * Bakery.income(profile) * GameData.OFFLINE_RATE)
		profile.coins += offlineCoins
		local at = workspace:GetServerTimeNow()
		for _, oven in profile.ovens do
			offlineBakes += #Bakery.advanceOven(profile, oven, at)
		end
	end

	local plot = Plots.build(plotIndex, player)
	for slot, oven in profile.ovens do
		Plots.addOven(plot, plotIndex, slot, oven.tier, player.UserId)
		Plots.setOvenGlow(plot, slot, oven.startedAt ~= nil)
	end
	for key, level in profile.creatures do
		Plots.showCreature(plot, plotIndex, key, level, profile.golden[key] == true)
	end

	local state: State = { profile = profile, plotIndex = plotIndex, plot = plot, lastRemote = 0 }
	states[player] = state
	refreshSlotPad(player, state)

	player.CharacterAdded:Connect(function(character)
		placeCharacter(player, character, plotIndex)
	end)
	if player.Character then
		task.spawn(placeCharacter, player, player.Character, plotIndex)
	end

	pushState(player, state)
	-- новичку — обе вкладки сразу; остальным новая строка «Сервера» уйдёт со следующим тиком
	leaderboardRemote:FireClient(player, { server = serverRows(), world = Leaderboards.top() })
	boardDirty = true
	if offlineCoins > 0 or offlineBakes > 0 then
		awayRemote:FireClient(player, { coins = offlineCoins, bakes = offlineBakes })
	end
end

-- Обе записи начинаются сразу, до первой паузы: BindToClose увидит их в очереди и дождётся
local function saveOnExit(player: Player, state: State)
	if Saves.canSave(player) then
		task.spawn(Leaderboards.write, player, Bakery.mastery(state.profile))
	end
	Saves.save(player, state.profile)
end

local function onPlayerRemoving(player: Player)
	local state = states[player]
	if not state then
		return
	end
	states[player] = nil
	boardDirty = true
	BattleService.cancel(player)
	saveOnExit(player, state)
	state.plot:Destroy()
	plotOwners[state.plotIndex] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Общий цикл: печи проверяются каждый тик, доход начисляется раз в секунду
task.spawn(function()
	local sinceIncome = 0
	while true do
		sinceIncome += task.wait(TICK)
		local payIncome = sinceIncome >= 1
		if payIncome then
			sinceIncome -= 1
		end
		local at = workspace:GetServerTimeNow()
		for player, state in states do
			local profile = state.profile
			local changed = payIncome
			for slot, oven in profile.ovens do
				local results = Bakery.advanceOven(profile, oven, at)
				for _, result in results do
					showBake(player, state, slot, result)
					boardDirty = boardDirty or result.isNew or result.leveledUp
				end
				if #results > 0 then
					changed = true
					Plots.setOvenGlow(state.plot, slot, oven.startedAt ~= nil)
				end
			end
			if payIncome then
				profile.coins += Bakery.income(profile)
				refreshSlotPad(player, state)
			end
			if changed then
				pushState(player, state)
			end
		end
		if payIncome then
			local worldChanged = Leaderboards.consumeChanges()
			if boardDirty or worldChanged then
				boardDirty = false
				broadcastBoard(worldChanged)
			end
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for player, state in states do
			task.spawn(Saves.save, player, state.profile)
		end
	end
end)

-- Бои: сервис сам ведёт фазы и таймеры, а за профилем, участком и наградой приходит сюда
BattleService.start({
	profile = function(player: Player): Saves.Profile?
		local state = states[player]
		return if state then state.profile else nil
	end,
	plot = function(player: Player): (Model?, number)
		local state = states[player]
		if state then
			return state.plot, state.plotIndex
		end
		return nil, 0
	end,
	income = function(player: Player): number
		local state = states[player]
		return if state then Bakery.income(state.profile) else 0
	end,
	reward = function(player: Player, coins: number, xp: number, team: { string }, clearedFloor: number?)
		local levels: { [string]: BattleService.LevelChange } = {}
		local state = states[player]
		if not state then
			return levels
		end
		local profile = state.profile
		profile.coins += coins
		for _, key in team do
			if profile.creatures[key] then
				local leveledUp = xp > 0 and Bakery.addXp(profile, key, xp)
				levels[key] = { level = profile.creatures[key], leveledUp = leveledUp }
				if leveledUp then
					Plots.showCreature(
						state.plot,
						state.plotIndex,
						key,
						profile.creatures[key],
						profile.golden[key] == true
					)
					boardDirty = true
				end
			end
		end
		if clearedFloor then
			profile.tower = math.max(profile.tower, clearedFloor)
		end
		refreshSlotPad(player, state)
		pushState(player, state)
		return levels
	end,
	teamChanged = function(player: Player)
		local state = states[player]
		if state then
			pushState(player, state)
		end
	end,
}, battleRemotes)

-- В таблицу попадают только те, чья сессия сохраняется: иначе в топе оказался бы прогресс, которого нет в хранилище
Leaderboards.start(function(player: Player): number?
	local state = states[player]
	if state and Saves.canSave(player) then
		return Bakery.mastery(state.profile)
	end
	return nil
end)

game:BindToClose(function()
	for player, state in states do
		task.spawn(saveOnExit, player, state)
	end
	Saves.waitForPending()
	Leaderboards.waitForPending()
end)

-- Только для проверки в Studio, с сервера: ServerStorage.BakeryDebug:Fire(userId, "coins", 5000)
if RunService:IsStudio() then
	local debugEvent = Instance.new("BindableEvent")
	debugEvent.Name = "BakeryDebug"
	debugEvent.Parent = ServerStorage
	debugEvent.Event:Connect(function(userId: number, action: string, value: any)
		if action == "sync" then
			Leaderboards.sync()
			return
		end
		local player = Players:GetPlayerByUserId(userId)
		local state = player and states[player]
		if not player or not state then
			return
		end
		if action == "coins" then
			state.profile.coins += value
		elseif action == "xp" and state.profile.creatures[value.key] then
			Bakery.addXp(state.profile, value.key, value.amount)
			Plots.showCreature(
				state.plot,
				state.plotIndex,
				value.key,
				state.profile.creatures[value.key],
				state.profile.golden[value.key] == true
			)
		end
		boardDirty = true
		refreshSlotPad(player, state)
		pushState(player, state)
	end)
end
