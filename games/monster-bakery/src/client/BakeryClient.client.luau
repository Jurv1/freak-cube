--!strict
-- Клиент «Пекарни монстриков»: печи, книга рецептов, счётчик монет.
-- Ничего не решает сам: шлёт намерения на сервер и рисует присланное состояние.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local GameData = require(Shared:WaitForChild("GameData"))
local BattleScreen = require(script.Parent.BattleScreen)
local Ui = require(script.Parent.Ui)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local make, round = Ui.make, Ui.round
local FONT = Ui.FONT
local WHITE, CREAM, BROWN, GREEN, GREY = Ui.WHITE, Ui.CREAM, Ui.BROWN, Ui.GREEN, Ui.GREY
local YELLOW, ORANGE, RED, GOLD, TRACK, FRIEND = Ui.YELLOW, Ui.ORANGE, Ui.RED, Ui.GOLD, Ui.TRACK, Ui.FRIEND

type Oven = {
	tier: number,
	key: string?,
	startedAt: number?,
	duration: number?,
	heatUntil: number?,
	repeatOn: boolean?,
}

local state = {
	coins = 0,
	income = 0,
	unlocked = {} :: { [string]: boolean },
	creatures = {} :: { [string]: number },
	xp = {} :: { [string]: number },
	golden = {} :: { [string]: boolean },
	ovens = { { tier = 1 } } :: { Oven },
	cap = GameData.LEVEL_CAP,
	tower = 0,
	team = {} :: { string },
}

-- Что игрок выбрал в панели каждой печи; на сервер уходит только по кнопке
local currentOven = 1
local selection: { [number]: { string } } = {}
local repeatOff: { [number]: boolean } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function picksFor(slot: number): { string }
	local picks = selection[slot]
	if not picks then
		picks = {}
		selection[slot] = picks
	end
	return picks
end

local function isBaking(oven: Oven): boolean
	return oven.startedAt ~= nil
end

-- Остывшая печь: стоит, но помнит рецепт и умеет печь сама
local function isCold(oven: Oven): boolean
	return oven.startedAt == nil and oven.key ~= nil and GameData.OvenTiers[oven.tier].heat > 0
end

local function isFinal(key: string): boolean
	local level = state.creatures[key]
	return level ~= nil and level >= state.cap and state.golden[key] == true
end

local gui = make("ScreenGui", { Name = "BakeryGui", ResetOnSpawn = false }, player:WaitForChild("PlayerGui"))
local uiScale = make("UIScale", {}, gui)
local function fitScale()
	local camera = workspace.CurrentCamera
	if camera then
		uiScale.Scale = math.clamp(camera.ViewportSize.Y / 720, 0.55, 1.3)
	end
end
fitScale()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitScale)

-- Кнопки и полоса печей живут в отдельном слое: на время боя он прячется целиком
local hud = make("Frame", {
	Name = "Hud",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
}, gui)

-- Верхняя панель

local coinsLabel = make("TextLabel", {
	Name = "Coins",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(340, 52),
	BackgroundColor3 = YELLOW,
	Font = FONT,
	TextSize = 26,
	TextColor3 = BROWN,
	Text = "💰 0",
}, gui)
round(coinsLabel, 16)

local hintLabel = make("TextLabel", {
	Name = "Hint",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 70),
	Size = UDim2.fromOffset(640, 34),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 22,
	TextColor3 = WHITE,
	TextStrokeTransparency = 0.2,
	Text = "Подойди к печи и смешай два ингредиента!",
}, hud)

local bookButton = make("TextButton", {
	Name = "BookButton",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 0),
	Size = UDim2.fromOffset(150, 56),
	BackgroundColor3 = CREAM,
	Font = FONT,
	TextSize = 22,
	TextColor3 = BROWN,
	Text = "📖 0/15",
}, hud)
round(bookButton, 16)

-- Появляется вместе со второй печью: раньше игроку не до соревнований
local leaderButton = make("TextButton", {
	Name = "LeaderButton",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 66),
	Size = UDim2.fromOffset(150, 56),
	BackgroundColor3 = CREAM,
	Font = FONT,
	TextSize = 22,
	TextColor3 = BROWN,
	Text = "🏆 Топ",
	Visible = false,
}, hud)
round(leaderButton, 16)

local function closeButton(parent: Instance): TextButton
	local button = make("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = RED,
		Font = FONT,
		TextSize = 22,
		TextColor3 = WHITE,
		Text = "X",
	}, parent)
	round(button, 12)
	return button
end

-- Панель печи

local ovenPanel = make("Frame", {
	Name = "OvenPanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.47),
	Size = UDim2.fromOffset(460, 500),
	BackgroundColor3 = CREAM,
	Visible = false,
}, gui)
round(ovenPanel, 20)

closeButton(ovenPanel).Activated:Connect(function()
	ovenPanel.Visible = false
end)

local tabsRow = make("Frame", {
	Name = "Tabs",
	Position = UDim2.fromOffset(15, 10),
	Size = UDim2.fromOffset(300, 36),
	BackgroundTransparency = 1,
}, ovenPanel)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, tabsRow)

local ovenTitle = make("TextLabel", {
	Name = "Title",
	Position = UDim2.fromOffset(15, 50),
	Size = UDim2.fromOffset(430, 28),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 22,
	TextColor3 = BROWN,
	Text = "",
}, ovenPanel)

local function slot(x: number): TextLabel
	local label = make("TextLabel", {
		Position = UDim2.fromOffset(x, 84),
		Size = UDim2.fromOffset(72, 72),
		BackgroundColor3 = WHITE,
		Font = FONT,
		TextSize = 40,
		TextColor3 = GREY,
		Text = "?",
	}, ovenPanel)
	round(label, 16)
	return label
end
local slotLabels = { slot(130), slot(258) }
make("TextLabel", {
	Position = UDim2.fromOffset(202, 84),
	Size = UDim2.fromOffset(56, 72),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 36,
	TextColor3 = BROWN,
	Text = "+",
}, ovenPanel)

local resultLabel = make("TextLabel", {
	Name = "Result",
	Position = UDim2.fromOffset(15, 160),
	Size = UDim2.fromOffset(430, 26),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 19,
	TextColor3 = BROWN,
	Text = "",
}, ovenPanel)

local ingredientGrid = make("Frame", {
	Name = "Ingredients",
	Position = UDim2.fromOffset(15, 190),
	Size = UDim2.fromOffset(430, 130),
	BackgroundTransparency = 1,
}, ovenPanel)
make("UIGridLayout", {
	CellSize = UDim2.fromOffset(136, 60),
	CellPadding = UDim2.fromOffset(11, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, ingredientGrid)

local function wideButton(name: string, y: number, height: number, textSize: number): TextButton
	local button = make("TextButton", {
		Name = name,
		Position = UDim2.fromOffset(15, y),
		Size = UDim2.fromOffset(430, height),
		BackgroundColor3 = GREY,
		Font = FONT,
		TextSize = textSize,
		TextColor3 = WHITE,
		Text = "",
		AutoButtonColor = false,
	}, ovenPanel)
	round(button, 14)
	return button
end

local repeatButton = wideButton("Repeat", 328, 36, 17)
local bakeButton = wideButton("Bake", 370, 56, 26)
local upgradeButton = wideButton("Upgrade", 434, 54, 16)

-- Книга рецептов

local bookPanel = make("Frame", {
	Name = "BookPanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.47),
	Size = UDim2.fromOffset(580, 410),
	BackgroundColor3 = CREAM,
	Visible = false,
}, gui)
round(bookPanel, 20)
local bookTitle = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 44),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 26,
	TextColor3 = BROWN,
	Text = "Книга рецептов",
}, bookPanel)
closeButton(bookPanel).Activated:Connect(function()
	bookPanel.Visible = false
end)
local bookGrid = make("Frame", {
	Position = UDim2.fromOffset(16, 56),
	Size = UDim2.fromOffset(548, 340),
	BackgroundTransparency = 1,
}, bookPanel)
make("UIGridLayout", {
	CellSize = UDim2.fromOffset(103, 106),
	CellPadding = UDim2.fromOffset(8, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, bookGrid)

local bookCells: { [string]: TextLabel } = {}
for order, key in GameData.RecipeOrder do
	local cell = make("TextLabel", {
		Name = key,
		LayoutOrder = order,
		BackgroundColor3 = GREY,
		Font = FONT,
		TextSize = 14,
		TextWrapped = true,
		TextColor3 = WHITE,
		TextStrokeTransparency = 0.4,
		Text = "?",
	}, bookGrid)
	round(cell, 12)
	bookCells[key] = cell
end

-- Таблица лидеров: «Сервер» считается сразу, «Мир» обновляется раз в две минуты

type Row = { userId: number, name: string, value: number }
local board = { server = {} :: { Row }, world = {} :: { Row } }
local leaderTab = "server"
local friends: { [number]: boolean } = {}

local leaderPanel = make("Frame", {
	Name = "LeaderPanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.47),
	Size = UDim2.fromOffset(460, 480),
	BackgroundColor3 = CREAM,
	Visible = false,
}, gui)
round(leaderPanel, 20)
make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 44),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 26,
	TextColor3 = BROWN,
	Text = "Мастерство",
}, leaderPanel)
closeButton(leaderPanel).Activated:Connect(function()
	leaderPanel.Visible = false
end)

local function leaderTabButton(name: string, text: string, x: number): TextButton
	local button = make("TextButton", {
		Name = name,
		Position = UDim2.fromOffset(x, 52),
		Size = UDim2.fromOffset(210, 36),
		BackgroundColor3 = WHITE,
		Font = FONT,
		TextSize = 18,
		TextColor3 = BROWN,
		Text = text,
		AutoButtonColor = false,
	}, leaderPanel)
	round(button, 10)
	return button
end
local serverTabButton = leaderTabButton("ServerTab", "Сервер", 15)
local worldTabButton = leaderTabButton("WorldTab", "Мир", 235)

local leaderList = make("ScrollingFrame", {
	Name = "Rows",
	Position = UDim2.fromOffset(15, 98),
	Size = UDim2.fromOffset(430, 310),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, leaderPanel)
make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, leaderList)

local leaderEmpty = make("TextLabel", {
	Name = "Empty",
	Position = UDim2.fromOffset(15, 98),
	Size = UDim2.fromOffset(430, 60),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 18,
	TextColor3 = GREY,
	Text = "Пока никого. Будь первым!",
	Visible = false,
}, leaderPanel)

local leaderMine = make("TextLabel", {
	Name = "Mine",
	Position = UDim2.fromOffset(15, 416),
	Size = UDim2.fromOffset(430, 50),
	BackgroundColor3 = YELLOW,
	Font = FONT,
	TextSize = 17,
	TextWrapped = true,
	TextColor3 = BROWN,
	Text = "",
}, leaderPanel)
round(leaderMine, 12)

type RowView = { frame: Frame, name: TextLabel, value: TextLabel }
local rowViews: { RowView } = {}

local function rowView(index: number): RowView
	local view = rowViews[index]
	if view then
		return view
	end
	local frame = make("Frame", {
		LayoutOrder = index,
		Size = UDim2.new(1, -10, 0, 30),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, leaderList)
	round(frame, 8)
	local newView: RowView = {
		frame = frame,
		name = make("TextLabel", {
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -100, 1, 0),
			BackgroundTransparency = 1,
			Font = FONT,
			TextSize = 17,
			TextColor3 = BROWN,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, frame),
		value = make("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.new(0, 80, 1, 0),
			BackgroundTransparency = 1,
			Font = FONT,
			TextSize = 17,
			TextColor3 = BROWN,
			TextXAlignment = Enum.TextXAlignment.Right,
		}, frame),
	}
	rowViews[index] = newView
	return newView
end

local refreshLeaders: () -> ()

-- Друзья подсвечены во вкладке «Сервер». Проверка идёт в сеть, поэтому ответ запоминаем.
local function checkFriend(userId: number)
	if friends[userId] ~= nil or userId == player.UserId then
		return
	end
	friends[userId] = false
	task.spawn(function()
		local ok, isFriend = pcall(function()
			return player:IsFriendsWith(userId)
		end)
		if ok and isFriend then
			friends[userId] = true
			refreshLeaders()
		end
	end)
end

local function myMastery(): number
	local total = 0
	for _, level in state.creatures do
		total += level
	end
	return total
end

function refreshLeaders()
	leaderButton.Visible = #state.ovens >= 2

	local onServer = leaderTab == "server"
	local rows = if onServer then board.server else board.world
	local mine = myMastery()
	local myPlace: number? = nil
	for index, row in rows do
		local view = rowView(index)
		local isMe = row.userId == player.UserId
		if isMe then
			myPlace = index
		elseif onServer then
			checkFriend(row.userId)
		end
		view.frame.Visible = true
		view.frame.BackgroundColor3 = if isMe then YELLOW elseif onServer and friends[row.userId] then FRIEND else WHITE
		view.name.Text = index .. ". " .. row.name
		-- своя строка в мире отстаёт до двух минут: показываем то, что уже есть на самом деле
		view.value.Text = Format.number(if isMe then math.max(mine, row.value) else row.value)
	end
	for index = #rows + 1, #rowViews do
		rowViews[index].frame.Visible = false
	end
	leaderEmpty.Visible = #rows == 0
	serverTabButton.BackgroundColor3 = if onServer then YELLOW else WHITE
	worldTabButton.BackgroundColor3 = if onServer then WHITE else YELLOW

	if onServer then
		leaderMine.Text = if myPlace
			then string.format("Ты: место %d из %d · мастерство %d", myPlace, #rows, mine)
			else string.format("Мастерство %d", mine)
	elseif myPlace then
		leaderMine.Text = string.format("Ты: место %d в мире · мастерство %d", myPlace, mine)
	elseif #rows >= GameData.LEADERBOARD_TOP then
		leaderMine.Text = string.format(
			"Мастерство %d · до топ-%d осталось %d",
			mine,
			GameData.LEADERBOARD_TOP,
			math.max(1, rows[#rows].value - mine + 1)
		)
	else
		leaderMine.Text =
			string.format("Мастерство %d · место появится через пару минут", mine)
	end
end

serverTabButton.Activated:Connect(function()
	leaderTab = "server"
	refreshLeaders()
end)
worldTabButton.Activated:Connect(function()
	leaderTab = "world"
	refreshLeaders()
end)

leaderButton.Activated:Connect(function()
	leaderPanel.Visible = not leaderPanel.Visible
	bookPanel.Visible = false
	ovenPanel.Visible = false
	BattleScreen.closePanel()
	refreshLeaders()
end)

bookButton.Activated:Connect(function()
	bookPanel.Visible = not bookPanel.Visible
	ovenPanel.Visible = false
	leaderPanel.Visible = false
	BattleScreen.closePanel()
end)

-- Бой: своя кнопка, панель и экран; печные панели при входе в бой закрываются
BattleScreen.init({
	gui = gui,
	hud = hud,
	getState = function()
		return state
	end,
	closePanels = function()
		bookPanel.Visible = false
		ovenPanel.Visible = false
		leaderPanel.Visible = false
	end,
})

-- Всплывающее сообщение

local popup = make("TextLabel", {
	Name = "Popup",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.22),
	Size = UDim2.fromOffset(560, 110),
	BackgroundColor3 = YELLOW,
	Font = FONT,
	TextSize = 28,
	TextWrapped = true,
	TextColor3 = BROWN,
	Visible = false,
	ZIndex = 10,
}, gui)
round(popup, 20)
local popupScale = make("UIScale", {}, popup)
local popupToken = 0

local function showPopup(text: string)
	popupToken += 1
	local token = popupToken
	popup.Text = text
	popup.Visible = true
	popupScale.Scale = 0.4
	TweenService:Create(popupScale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(3, function()
		if popupToken == token then
			popup.Visible = false
		end
	end)
end

-- Окно «Пока тебя не было»: висит, пока игрок не закроет, иначе итог перебьёт сообщение о новом уровне

local awayPanel = make("Frame", {
	Name = "AwayPanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	Size = UDim2.fromOffset(420, 220),
	BackgroundColor3 = CREAM,
	Visible = false,
	ZIndex = 20,
}, gui)
round(awayPanel, 20)
local awayText = make("TextLabel", {
	Name = "Text",
	Position = UDim2.fromOffset(20, 14),
	Size = UDim2.fromOffset(380, 130),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 24,
	TextWrapped = true,
	TextColor3 = BROWN,
	ZIndex = 21,
}, awayPanel)
local awayButton = make("TextButton", {
	Name = "Ok",
	Position = UDim2.fromOffset(110, 152),
	Size = UDim2.fromOffset(200, 52),
	BackgroundColor3 = GREEN,
	Font = FONT,
	TextSize = 24,
	TextColor3 = WHITE,
	Text = "Отлично!",
	ZIndex = 21,
}, awayPanel)
round(awayButton, 14)
awayButton.Activated:Connect(function()
	awayPanel.Visible = false
end)

-- Полоса печей: плитка на каждую печь, покупка следующей, «разжечь все»

local strip = make("Frame", {
	Name = "OvenStrip",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.fromOffset(0, 80),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
}, hud)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, strip)

type Tile = { button: TextButton, recipe: TextLabel, timer: TextLabel, progress: Frame, heat: Frame }
local tiles: { Tile } = {}
local tabs: { TextButton } = {}

local function stripButton(name: string, order: number, width: number): TextButton
	local button = make("TextButton", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(width, 80),
		BackgroundColor3 = CREAM,
		Font = FONT,
		TextSize = 16,
		TextColor3 = BROWN,
		Text = "",
		AutoButtonColor = false,
	}, strip)
	round(button, 14)
	return button
end

-- Тонкая полоска у края плитки; возвращает заполняемую часть
local function tileBar(parent: Instance, atTop: boolean, color: Color3): Frame
	local track = make("Frame", {
		AnchorPoint = Vector2.new(0.5, if atTop then 0 else 1),
		Position = UDim2.new(0.5, 0, if atTop then 0 else 1, if atTop then 6 else -6),
		Size = UDim2.new(1, -14, 0, 5),
		BackgroundColor3 = TRACK,
		BorderSizePixel = 0,
	}, parent)
	return make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color, BorderSizePixel = 0 }, track)
end

local function tileText(parent: Instance, y: number, height: number, textSize: number): TextLabel
	return make("TextLabel", {
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = textSize,
		TextColor3 = BROWN,
		Text = "",
	}, parent)
end

local buyTile = stripButton("BuyTile", 10, 96)
local reigniteAll = stripButton("ReigniteAll", 11, 104)
reigniteAll.Text = "Разжечь\nвсе"
reigniteAll.BackgroundColor3 = ORANGE
reigniteAll.TextColor3 = WHITE

local refresh: () -> ()

local function openOven(index: number)
	local oven = state.ovens[index]
	if not oven then
		return
	end
	currentOven = index
	-- у остывшей печи сразу подставляем её рецепт: «Испечь!» запускает его снова
	local picks = picksFor(index)
	if #picks == 0 and not isBaking(oven) and oven.key then
		local recipe = GameData.Recipes[oven.key]
		table.insert(picks, recipe.a)
		table.insert(picks, recipe.b)
	end
	bookPanel.Visible = false
	leaderPanel.Visible = false
	BattleScreen.closePanel()
	ovenPanel.Visible = true
	refresh()
end

local function ensureOvenWidgets()
	for index = #tiles + 1, #state.ovens do
		local button = stripButton("Tile" .. index, index, 80)
		tiles[index] = {
			button = button,
			recipe = tileText(button, 14, 34, 22),
			timer = tileText(button, 48, 20, 14),
			heat = tileBar(button, true, ORANGE),
			progress = tileBar(button, false, GREEN),
		}
		button.Activated:Connect(function()
			if ovenPanel.Visible and currentOven == index then
				ovenPanel.Visible = false
			else
				openOven(index)
			end
		end)

		local tab = make("TextButton", {
			Name = "Tab" .. index,
			LayoutOrder = index,
			Size = UDim2.fromOffset(44, 36),
			BackgroundColor3 = WHITE,
			Font = FONT,
			TextSize = 20,
			TextColor3 = BROWN,
			Text = tostring(index),
			AutoButtonColor = false,
		}, tabsRow)
		round(tab, 10)
		tabs[index] = tab
		tab.Activated:Connect(function()
			openOven(index)
		end)
	end
end

-- Отрисовка состояния

local ingredientButtons: { [string]: TextButton } = {}

local function refreshBook()
	local discovered = 0
	for _, key in GameData.RecipeOrder do
		local recipe = GameData.Recipes[key]
		local level = state.creatures[key]
		local cell = bookCells[key]
		if level then
			discovered += 1
			local progress = if level >= state.cap
				then "МАКС"
				else string.format("%d/%d", state.xp[key] or 0, GameData.xpNeed(level))
			cell.BackgroundColor3 = if state.golden[key] then GOLD else recipe.color
			cell.TextSize = 14
			cell.Text = (if state.golden[key] then "⭐ " else "")
				.. recipe.name
				.. "\nур. "
				.. level
				.. "\n"
				.. progress
		else
			cell.BackgroundColor3 = GREY
			cell.TextSize = 40
			cell.Text = "?"
		end
	end
	bookButton.Text = string.format("📖 %d/%d", discovered, #GameData.RecipeOrder)
	bookTitle.Text = string.format("Книга рецептов  %d/%d", discovered, #GameData.RecipeOrder)
	hintLabel.Visible = discovered == 0 and not ovenPanel.Visible
end

local function refreshStrip()
	local nextSlot = #state.ovens + 1
	local price = GameData.OvenSlotPrices[nextSlot]
	buyTile.Visible = price ~= nil
	if price then
		local affordable = state.coins >= price
		buyTile.Text = string.format("+ Печь %d\n💰 %s", nextSlot, Format.number(price))
		buyTile.BackgroundColor3 = if affordable then GREEN else CREAM
		buyTile.TextColor3 = if affordable then WHITE else BROWN
	end

	local anyCold = false
	for _, oven in state.ovens do
		anyCold = anyCold or isCold(oven)
	end
	reigniteAll.Visible = anyCold
end

local function refreshPanel()
	local oven = state.ovens[currentOven]
	if not oven then
		currentOven = 1
		oven = state.ovens[1]
	end
	local tier = GameData.OvenTiers[oven.tier]
	local baking = isBaking(oven)
	ovenTitle.Text = string.format("Печь %d · %s", currentOven, tier.name)

	for index, tab in tabs do
		tab.BackgroundColor3 = if index == currentOven then YELLOW else WHITE
	end

	-- пока печь занята, показываем то, что в ней печётся, а не выбор игрока
	local picks = picksFor(currentOven)
	if baking and oven.key then
		local recipe = GameData.Recipes[oven.key]
		picks = { recipe.a, recipe.b }
	end
	for index, label in slotLabels do
		local id = picks[index]
		label.Text = if id then GameData.IngredientById[id].emoji else "?"
	end

	if #picks == 2 then
		local key = GameData.recipeKey(picks[1], picks[2])
		local level = state.creatures[key]
		if not level then
			resultLabel.Text = "Что получится? Попробуй!"
		elseif level >= state.cap then
			resultLabel.Text = GameData.Recipes[key].name .. " · ур. " .. level .. " МАКС"
		else
			resultLabel.Text = string.format(
				"%s · ур. %d · %d/%d",
				GameData.Recipes[key].name,
				level,
				state.xp[key] or 0,
				GameData.xpNeed(level)
			)
		end
	else
		resultLabel.Text = ""
	end

	for _, ingredient in GameData.Ingredients do
		local button = ingredientButtons[ingredient.id]
		if state.unlocked[ingredient.id] then
			button.Text = ingredient.emoji .. " " .. ingredient.name
			button.BackgroundColor3 = if table.find(picks, ingredient.id) then YELLOW else WHITE
			button.TextColor3 = if baking then GREY else BROWN
		else
			button.Text = string.format("🔒 %s\n💰 %s", ingredient.name, Format.number(ingredient.price))
			button.BackgroundColor3 = if state.coins >= ingredient.price then GREEN else GREY
			button.TextColor3 = WHITE
		end
	end

	local nextTier = GameData.OvenTiers[oven.tier + 1]
	if nextTier then
		upgradeButton.Text = string.format(
			"Улучшить: %s — 💰 %s\nскорость ×%s · сама печёт %s",
			nextTier.name,
			Format.number(nextTier.price),
			tostring(nextTier.speed),
			Format.duration(nextTier.heat)
		)
		upgradeButton.BackgroundColor3 = if state.coins >= nextTier.price then GREEN else GREY
	else
		upgradeButton.Text = "Лучшая печь!"
		upgradeButton.BackgroundColor3 = GOLD
	end
end

-- То, что меняется каждую секунду и чаще: таймеры, полоски, пульс остывшей печи
local function refreshTimers()
	local t = now()
	for index, tile in tiles do
		local oven = state.ovens[index]
		if not oven then
			continue
		end
		local recipe = if oven.key then GameData.Recipes[oven.key] else nil
		tile.recipe.Text = if recipe
			then GameData.IngredientById[recipe.a].emoji .. GameData.IngredientById[recipe.b].emoji
			else tostring(index)

		local selected = ovenPanel.Visible and currentOven == index
		if oven.startedAt and oven.duration then
			local left = math.max(0, oven.startedAt + oven.duration - t)
			tile.timer.Text = math.ceil(left) .. " с"
			tile.progress.Size = UDim2.fromScale(math.clamp(1 - left / oven.duration, 0, 1), 1)
			tile.button.BackgroundColor3 = if selected then YELLOW else CREAM
		elseif isCold(oven) then
			tile.timer.Text = "остыла"
			tile.progress.Size = UDim2.fromScale(0, 1)
			tile.button.BackgroundColor3 = CREAM:Lerp(ORANGE, 0.5 + 0.5 * math.sin(t * 5))
		else
			tile.timer.Text = "свободна"
			tile.progress.Size = UDim2.fromScale(0, 1)
			tile.button.BackgroundColor3 = if selected then YELLOW else CREAM
		end

		local heat = GameData.OvenTiers[oven.tier].heat
		local heatLeft = if oven.heatUntil and heat > 0 then math.clamp((oven.heatUntil - t) / heat, 0, 1) else 0
		tile.heat.Size = UDim2.fromScale(heatLeft, 1)
	end

	local oven = state.ovens[currentOven]
	if not oven or not ovenPanel.Visible then
		return
	end
	local picks = picksFor(currentOven)
	if oven.startedAt and oven.duration then
		bakeButton.Text = "Печётся… " .. math.ceil(math.max(0, oven.startedAt + oven.duration - t)) .. " с"
		bakeButton.BackgroundColor3 = ORANGE
	elseif #picks == 2 and isFinal(GameData.recipeKey(picks[1], picks[2])) then
		bakeButton.Text = "Максимум"
		bakeButton.BackgroundColor3 = GREY
	elseif #picks == 2 then
		bakeButton.Text = "Испечь!"
		bakeButton.BackgroundColor3 = GREEN
	else
		bakeButton.Text = "Выбери два ингредиента"
		bakeButton.BackgroundColor3 = GREY
	end

	local heat = GameData.OvenTiers[oven.tier].heat
	if heat == 0 then
		repeatButton.Text = "Повтор — с Чугунной печи"
		repeatButton.BackgroundColor3 = GREY
	elseif isBaking(oven) and oven.repeatOn and oven.heatUntil then
		repeatButton.Text = "Остановить повтор · жар " .. Format.clock(oven.heatUntil - t)
		repeatButton.BackgroundColor3 = RED
	elseif isBaking(oven) then
		repeatButton.Text = "Повтор выключен"
		repeatButton.BackgroundColor3 = GREY
	elseif repeatOff[currentOven] then
		repeatButton.Text = "Повтор: ВЫКЛ"
		repeatButton.BackgroundColor3 = GREY
	else
		repeatButton.Text = "Повтор: ВКЛ · сама печёт " .. Format.duration(heat)
		repeatButton.BackgroundColor3 = GREEN
	end
end

function refresh()
	ensureOvenWidgets()
	coinsLabel.Text = string.format("💰 %s   (+%s/с)", Format.number(state.coins), Format.number(state.income))
	refreshBook()
	refreshStrip()
	refreshPanel()
	refreshLeaders()
	BattleScreen.refresh()
	refreshTimers()
end

-- Маленькая цифра над плиткой печи вместо всплывающего окна на каждую выпечку
local function floatText(index: number, text: string)
	local tile = tiles[index]
	if not tile then
		return
	end
	local label = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -4),
		Size = UDim2.fromOffset(80, 24),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 20,
		TextColor3 = WHITE,
		TextStrokeTransparency = 0.2,
		Text = text,
	}, tile.button)
	local tween = TweenService:Create(label, TweenInfo.new(0.9), {
		Position = UDim2.new(0.5, 0, 0, -40),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tween.Completed:Connect(function()
		label:Destroy()
	end)
	tween:Play()
end

-- Действия

for order, ingredient in GameData.Ingredients do
	local button = make("TextButton", {
		Name = ingredient.id,
		LayoutOrder = order,
		BackgroundColor3 = WHITE,
		Font = FONT,
		TextSize = 18,
		TextColor3 = BROWN,
		Text = ingredient.name,
	}, ingredientGrid)
	round(button, 12)
	ingredientButtons[ingredient.id] = button

	button.Activated:Connect(function()
		if not state.unlocked[ingredient.id] then
			if state.coins >= ingredient.price then
				remotes.Buy:FireServer(ingredient.id)
			end
			return
		end
		local oven = state.ovens[currentOven]
		if not oven or isBaking(oven) then
			return
		end
		local picks = picksFor(currentOven)
		local index = table.find(picks, ingredient.id)
		if index then
			table.remove(picks, index)
		else
			-- третий ингредиент вытесняет самый старый: ребёнку не нужно сначала снимать выбор
			if #picks == 2 then
				table.remove(picks, 1)
			end
			table.insert(picks, ingredient.id)
		end
		refresh()
	end)
end

bakeButton.Activated:Connect(function()
	local oven = state.ovens[currentOven]
	local picks = picksFor(currentOven)
	if not oven or isBaking(oven) or #picks ~= 2 or isFinal(GameData.recipeKey(picks[1], picks[2])) then
		return
	end
	remotes.Bake:FireServer(currentOven, picks[1], picks[2], not repeatOff[currentOven])
end)

repeatButton.Activated:Connect(function()
	local oven = state.ovens[currentOven]
	if not oven or GameData.OvenTiers[oven.tier].heat == 0 then
		return
	end
	if isBaking(oven) then
		if oven.repeatOn then
			remotes.StopOven:FireServer(currentOven)
		end
	else
		repeatOff[currentOven] = not repeatOff[currentOven]
		refresh()
	end
end)

upgradeButton.Activated:Connect(function()
	local oven = state.ovens[currentOven]
	local nextTier = oven and GameData.OvenTiers[oven.tier + 1]
	if nextTier and state.coins >= nextTier.price then
		remotes.UpgradeOven:FireServer(currentOven)
	end
end)

buyTile.Activated:Connect(function()
	local price = GameData.OvenSlotPrices[#state.ovens + 1]
	if price and state.coins >= price then
		remotes.BuyOven:FireServer()
	end
end)

reigniteAll.Activated:Connect(function()
	remotes.Reignite:FireServer(0)
end)

remotes.State.OnClientEvent:Connect(function(newState)
	state = newState
	refresh()
end)

remotes.Baked.OnClientEvent:Connect(function(result)
	local name = GameData.Recipes[result.key].name
	if result.golden then
		showPopup("⭐ ЗОЛОТОЙ! ⭐\n" .. name)
	elseif result.isNew then
		showPopup("✨ Новый рецепт!\n" .. name)
	elseif result.leveledUp then
		showPopup(name .. "\nтеперь уровень " .. result.level)
	else
		floatText(result.oven, "+" .. GameData.BAKE_XP)
	end
end)

remotes.Notify.OnClientEvent:Connect(showPopup)

-- Сервер шлёт только изменившуюся часть: строки «Мира» приходят раз в две минуты
remotes.Leaderboard.OnClientEvent:Connect(function(update)
	board.server = update.server or board.server
	board.world = update.world or board.world
	refreshLeaders()
end)

-- Сервер поставил персонажа перед печью: разворачиваем камеру туда же, чтобы печь была в кадре
remotes.Placed.OnClientEvent:Connect(function(at: CFrame)
	local camera = workspace.CurrentCamera
	if camera then
		local eye = at.Position - at.LookVector * 14 + Vector3.new(0, 7, 0)
		camera.CFrame = CFrame.lookAt(eye, at.Position + at.LookVector * 12)
	end
end)

remotes.Away.OnClientEvent:Connect(function(summary)
	local text = "Пока тебя не было\n💰 +" .. Format.number(summary.coins)
	if summary.bakes > 0 then
		text ..= "\nПечи испекли " .. Format.number(summary.bakes) .. " раз"
	end
	awayText.Text = text
	awayPanel.Visible = true
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local mine = prompt:GetAttribute("OwnerId") == player.UserId
	if prompt.Name == "OvenPrompt" then
		if mine then
			openOven(prompt:GetAttribute("OvenIndex") or 1)
		else
			showPopup("Это чужая печь. Твоя — рядом с твоей табличкой!")
		end
	elseif prompt.Name == "BuyOvenPrompt" and mine then
		remotes.BuyOven:FireServer()
	end
end)

RunService.Heartbeat:Connect(refreshTimers)
refresh()
