--!strict
-- Бой на клиенте: кнопка и панель «Бой» (этаж башни и команда), экран боя, итог.
-- Ничего не считает сам: показывает присланное сервером и шлёт нажатую кнопку.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BattleRules = require(Shared:WaitForChild("BattleRules"))
local Format = require(Shared:WaitForChild("Format"))
local GameData = require(Shared:WaitForChild("GameData"))
local Tower = require(Shared:WaitForChild("Tower"))
local Ui = require(script.Parent.Ui)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local RULES = GameData.Battle
local make, round = Ui.make, Ui.round
local FONT = Ui.FONT
local BLUE = Color3.fromRGB(150, 220, 255)
local IMPACT_DELAY = 0.3 -- через сколько после названия скилла падает здоровье
local START_TIMEOUT = 4
local CAMERA_BINDING = "BakeryBattleCamera"
local MATCHUP_SIGN = 0.15 -- с какого расклада на карточке команды появляется стрелка
-- ⬆ и ⬇ рисуются толстой стрелкой и красятся цветом текста; ▲ выходит мелким, ➜ не рисуется вовсе
local ARROWS = { [2] = "⬆⬆", [1] = "⬆", [-1] = "⬇", [-2] = "⬇⬇" }
local WHEEL_RADIUS = 105

type FighterView = {
	key: string,
	level: number,
	hp: number,
	hpMax: number,
	atk: number,
	spd: number,
	skills: { string },
	cooldown: { [string]: number },
	shield: boolean,
	slow: boolean,
	frozen: boolean,
	giant: boolean,
}
type SideView = { team: { FighterView }, active: number }

export type Context = {
	gui: ScreenGui,
	hud: Frame, -- кнопки и полоса печей: прячутся на время боя
	getState: () -> any,
	closePanels: () -> (), -- закрыть остальные панели перед открытием панели боя
}

type CardView = { frame: Frame, name: TextLabel, status: TextLabel, fill: Frame, hp: TextLabel, dots: { Frame } }
type TeamCard = { button: TextButton, badge: TextLabel, sign: TextLabel }
type SkillButton = {
	button: TextButton,
	icon: TextLabel,
	name: TextLabel,
	hint: TextLabel,
	matchup: TextLabel,
	shade: TextLabel,
}

local BattleScreen = {}

-- Заполняются в init: до него экрана нет
BattleScreen.refresh = function() end
BattleScreen.closePanel = function() end

-- Значки типов для надписи с RichText: основной тип крупно, подтип мельче справа
local function typeIcons(key: string, mainSize: number, subSize: number): string
	local main, sub = BattleRules.types(key)
	local text = string.format('<font size="%d">%s</font>', mainSize, GameData.IngredientById[main].emoji)
	if sub then
		text ..= string.format('<font size="%d">%s</font>', subSize, GameData.IngredientById[sub].emoji)
	end
	return text
end

local function fighterName(fighter: FighterView): string
	return (if fighter.giant then "Гигант " else "") .. GameData.Recipes[fighter.key].name
end

function BattleScreen.init(context: Context)
	local gui = context.gui
	local inBattle = false

	-- Кнопка в левом столбце

	local hudButton = make("TextButton", {
		Name = "BattleButton",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 132),
		Size = UDim2.fromOffset(150, 56),
		BackgroundColor3 = Ui.RED,
		Font = FONT,
		TextSize = 22,
		TextColor3 = Ui.WHITE,
		Text = "Бой",
		Visible = false,
	}, context.hud)
	round(hudButton, 16)

	-- Панель «Бой»: кто на этаже и кого берём с собой

	local panel = make("Frame", {
		Name = "BattlePanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromOffset(600, 500),
		BackgroundColor3 = Ui.CREAM,
		Visible = false,
	}, gui)
	round(panel, 20)

	local panelTitle = make("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 26,
		TextColor3 = Ui.BROWN,
		Text = "",
	}, panel)

	local panelClose = make("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Ui.RED,
		Font = FONT,
		TextSize = 22,
		TextColor3 = Ui.WHITE,
		Text = "X",
	}, panel)
	round(panelClose, 12)
	panelClose.Activated:Connect(function()
		panel.Visible = false
	end)

	local foeRow = make("Frame", {
		Name = "Foes",
		Position = UDim2.fromOffset(15, 50),
		Size = UDim2.fromOffset(570, 64),
		BackgroundTransparency = 1,
	}, panel)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 9),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, foeRow)
	local foeCards: { TextLabel } = {}
	for index = 1, GameData.TEAM_SIZE do
		local card = make("TextLabel", {
			Name = "Foe" .. index,
			LayoutOrder = index,
			Size = UDim2.fromOffset(167, 64),
			BackgroundColor3 = Ui.DARK,
			Font = FONT,
			TextSize = 14,
			TextWrapped = true,
			RichText = true,
			TextColor3 = Ui.WHITE,
			Text = "",
		}, foeRow)
		round(card, 10)
		foeCards[index] = card
	end

	-- Не в углу экрана: там кнопки самого Roblox
	local wheelButton = make("TextButton", {
		Name = "Wheel",
		LayoutOrder = GameData.TEAM_SIZE + 1,
		Size = UDim2.fromOffset(42, 42),
		BackgroundColor3 = Ui.ORANGE,
		Font = FONT,
		TextSize = 26,
		TextColor3 = Ui.WHITE,
		Text = "?",
	}, foeRow)
	round(wheelButton, 21)

	make("TextLabel", {
		Position = UDim2.fromOffset(15, 120),
		Size = UDim2.fromOffset(570, 24),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 16,
		TextColor3 = Ui.BROWN,
		Text = "Твоя команда. Нажми на зверька, чтобы взять или убрать:",
	}, panel)

	local teamGrid = make("ScrollingFrame", {
		Name = "Team",
		Position = UDim2.fromOffset(15, 148),
		Size = UDim2.fromOffset(570, 276),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, panel)
	make("UIGridLayout", {
		CellSize = UDim2.fromOffset(106, 86),
		CellPadding = UDim2.fromOffset(7, 7),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, teamGrid)

	local autoButton = make("TextButton", {
		Name = "Auto",
		Position = UDim2.fromOffset(15, 434),
		Size = UDim2.fromOffset(150, 52),
		BackgroundColor3 = Ui.WHITE,
		Font = FONT,
		TextSize = 20,
		TextColor3 = Ui.BROWN,
		Text = "Авто",
		AutoButtonColor = false,
	}, panel)
	round(autoButton, 14)

	local fightButton = make("TextButton", {
		Name = "Fight",
		Position = UDim2.fromOffset(175, 434),
		Size = UDim2.fromOffset(410, 52),
		BackgroundColor3 = Ui.GREEN,
		Font = FONT,
		TextSize = 24,
		TextColor3 = Ui.WHITE,
		Text = "В бой!",
		AutoButtonColor = false,
	}, panel)
	round(fightButton, 14)

	-- Этаж, на который игрок пойдёт следующим; nil — открытые этажи кончились
	local function nextFloor(): Tower.Floor?
		local number = (context.getState().tower or 0) + 1
		return if number <= GameData.TOWER_FLOORS_OPEN then Tower.floor(number) else nil
	end

	-- Сохранённая команда, а если её нет — «Авто» под врагов этажа, как это сделает сервер
	local function currentTeam(): { string }
		local state = context.getState()
		local team = {}
		for _, key in state.team or {} do
			if state.creatures[key] then
				table.insert(team, key)
			end
		end
		if #team == 0 then
			local floor = nextFloor()
			if floor then
				return BattleRules.autoTeam(state.creatures, floor.enemies, floor.level)
			end
			return BattleRules.autoTeam(state.creatures)
		end
		return team
	end

	local function toggleTeam(key: string)
		local team = table.clone(currentTeam())
		local index = table.find(team, key)
		if index then
			if #team == 1 then
				return
			end
			table.remove(team, index)
		else
			-- четвёртый вытесняет первого: не нужно сначала кого-то убирать
			if #team >= GameData.TEAM_SIZE then
				table.remove(team, 1)
			end
			table.insert(team, key)
		end
		remotes.SetTeam:FireServer(team)
	end

	local teamCards: { [string]: TeamCard } = {}
	for order, key in GameData.RecipeOrder do
		local button = make("TextButton", {
			Name = key,
			LayoutOrder = order,
			BackgroundColor3 = Ui.WHITE,
			Font = FONT,
			TextSize = 13,
			TextWrapped = true,
			RichText = true,
			TextColor3 = Ui.BROWN,
			Text = "",
			Visible = false,
			AutoButtonColor = false,
		}, teamGrid)
		round(button, 10)
		local badge = make("TextLabel", {
			Name = "Badge",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 4),
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = Ui.GREEN,
			Font = FONT,
			TextSize = 15,
			TextColor3 = Ui.WHITE,
			Text = "",
			Visible = false,
		}, button)
		round(badge, 11)
		-- расклад против врагов этажа: зелёная стрелка — враги удобные, красная — неудобные
		local sign = make("TextLabel", {
			Name = "Sign",
			Position = UDim2.fromOffset(5, 3),
			Size = UDim2.fromOffset(24, 24),
			BackgroundTransparency = 1,
			Font = FONT,
			TextSize = 22,
			TextColor3 = Ui.GREEN,
			Text = "",
		}, button)
		teamCards[key] = { button = button, badge = badge, sign = sign }
		button.Activated:Connect(function()
			toggleTeam(key)
		end)
	end

	local function refreshPanel()
		local state = context.getState()
		local owned = 0
		for _ in state.creatures do
			owned += 1
		end
		hudButton.Visible = owned >= GameData.BATTLE_UNLOCK_CREATURES
		if not panel.Visible then
			return
		end

		local number = (state.tower or 0) + 1
		local floor = nextFloor()
		local open = floor ~= nil
		panelTitle.Text = if floor
			then "Торт-башня · этаж " .. number .. (if floor.boss then " · БОСС" else "")
			else "Торт-башня · все этажи пройдены"
		for index, card in foeCards do
			local key = if floor then floor.enemies[index] else nil
			card.Visible = key ~= nil or (floor == nil and index == 1)
			if floor and key then
				local giant = floor.boss and index == 1
				card.Text = string.format(
					"%s %s%s\nур. %d",
					typeIcons(key, 22, 13),
					if giant then "Гигант " else "",
					GameData.Recipes[key].name,
					floor.level
				)
			else
				card.Text = "Новые этажи скоро!"
			end
		end

		local team = currentTeam()
		for key, card in teamCards do
			local level = state.creatures[key]
			card.button.Visible = level ~= nil
			if level then
				local place = table.find(team, key)
				card.button.Text = string.format(
					"%s\n%s\nур. %d · сила %s",
					typeIcons(key, 20, 12),
					GameData.Recipes[key].name,
					level,
					Format.number(BattleRules.power(key, level))
				)
				card.button.BackgroundColor3 = if place then Ui.YELLOW else Ui.WHITE
				card.badge.Visible = place ~= nil
				card.badge.Text = tostring(place or "")
				local matchup = if floor then BattleRules.matchup(key, level, floor.enemies, floor.level) else 0
				card.sign.Text = if matchup >= MATCHUP_SIGN
					then ARROWS[1]
					elseif matchup <= -MATCHUP_SIGN then ARROWS[-1]
					else ""
				card.sign.TextColor3 = if matchup > 0 then Ui.GREEN else Ui.RED
			end
		end

		autoButton.BackgroundColor3 = if #(state.team or {}) == 0 then Ui.YELLOW else Ui.WHITE
		fightButton.Text = if open then "В бой!" else "Этажи пройдены"
		fightButton.BackgroundColor3 = if open then Ui.GREEN else Ui.GREY
	end

	autoButton.Activated:Connect(function()
		remotes.SetTeam:FireServer({})
	end)

	-- Колесо типов: кто кого бьёт сильнее. Одна картинка без текста, закрывается нажатием.

	local wheel = make("TextButton", {
		Name = "TypeWheel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromOffset(340, 400),
		BackgroundColor3 = Ui.CREAM,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 10,
	}, gui)
	round(wheel, 20)
	make("UIStroke", { Color = Ui.BROWN, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, wheel)
	local function wheelLabel(position: UDim2, size: number, text: string, color: Color3): TextLabel
		return make("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = UDim2.fromOffset(size * 2, size * 1.4),
			BackgroundTransparency = 1,
			Font = FONT,
			TextSize = size,
			TextColor3 = color,
			Text = text,
			ZIndex = 11,
		}, wheel)
	end
	local typeCount = #GameData.TypeOrder
	for index, id in GameData.TypeOrder do
		-- по часовой стрелке, первый тип сверху; стрелка между соседями смотрит на того, кого бьют
		local angle = math.rad(-90 + (index - 1) * 360 / typeCount)
		local between = angle + math.rad(180 / typeCount)
		wheelLabel(
			UDim2.new(0.5, math.cos(angle) * WHEEL_RADIUS, 0, 150 + math.sin(angle) * WHEEL_RADIUS),
			40,
			GameData.IngredientById[id].emoji,
			Ui.BROWN
		)
		local arrow = wheelLabel(
			UDim2.new(0.5, math.cos(between) * WHEEL_RADIUS, 0, 150 + math.sin(between) * WHEEL_RADIUS),
			30,
			ARROWS[1],
			Ui.GREEN
		)
		arrow.Rotation = math.deg(between) + 180
	end
	-- образцы: крупный значок — основной тип, по нему две стрелки; мелкий — подтип, одна
	local sample = GameData.IngredientById[GameData.TypeOrder[2]].emoji
	wheelLabel(UDim2.new(0.5, -40, 0, 310), 40, sample, Ui.BROWN)
	wheelLabel(UDim2.new(0.5, 40, 0, 310), 30, ARROWS[2], Ui.GREEN)
	wheelLabel(UDim2.new(0.5, -40, 0, 362), 22, sample, Ui.BROWN)
	wheelLabel(UDim2.new(0.5, 40, 0, 362), 30, ARROWS[1], Ui.GREEN)
	wheel.Activated:Connect(function()
		wheel.Visible = false
	end)
	wheelButton.Activated:Connect(function()
		wheel.Visible = not wheel.Visible
	end)
	panelClose.Activated:Connect(function()
		wheel.Visible = false
	end)

	hudButton.Activated:Connect(function()
		local opening = not panel.Visible
		context.closePanels()
		panel.Visible = opening
		wheel.Visible = false
		refreshPanel()
	end)

	-- Экран боя

	local screen = make("Frame", {
		Name = "BattleScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)

	local function fighterCard(name: string, anchor: Vector2, position: UDim2): CardView
		local frame = make("Frame", {
			Name = name,
			AnchorPoint = anchor,
			Position = position,
			Size = UDim2.fromOffset(560, 76),
			BackgroundColor3 = Ui.CREAM,
		}, screen)
		round(frame, 14)
		local nameLabel = make("TextLabel", {
			Name = "Name",
			Position = UDim2.fromOffset(12, 4),
			Size = UDim2.fromOffset(330, 30),
			BackgroundTransparency = 1,
			Font = FONT,
			TextSize = 19,
			RichText = true,
			TextColor3 = Ui.BROWN,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
		}, frame)
		local status = make("TextLabel", {
			Name = "Status",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -78, 0, 4),
			Size = UDim2.fromOffset(130, 30),
			BackgroundTransparency = 1,
			Font = FONT,
			TextSize = 14,
			TextColor3 = Ui.ORANGE,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = "",
		}, frame)
		local dots = {}
		for index = 1, GameData.TEAM_SIZE do
			local dot = make("Frame", {
				Name = "Dot" .. index,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12 - (GameData.TEAM_SIZE - index) * 20, 0, 11),
				Size = UDim2.fromOffset(16, 16),
				BackgroundColor3 = Ui.GREEN,
				BorderSizePixel = 0,
			}, frame)
			round(dot, 8)
			dots[index] = dot
		end
		local track = make("Frame", {
			Name = "Track",
			Position = UDim2.fromOffset(12, 40),
			Size = UDim2.fromOffset(536, 26),
			BackgroundColor3 = Ui.DARK,
			BorderSizePixel = 0,
		}, frame)
		round(track, 8)
		local fill = make("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Ui.GREEN,
			BorderSizePixel = 0,
		}, track)
		round(fill, 8)
		local hp = make("TextLabel", {
			Name = "Hp",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = FONT,
			TextSize = 16,
			TextColor3 = Ui.WHITE,
			TextStrokeTransparency = 0.4,
			Text = "",
			ZIndex = 2,
		}, track)
		return { frame = frame, name = nameLabel, status = status, fill = fill, hp = hp, dots = dots }
	end

	local foeCard = fighterCard("Foe", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 72))
	local youCard = fighterCard("You", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -180))

	local banner = make("TextLabel", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(760, 44),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 26,
		TextColor3 = Ui.WHITE,
		TextStrokeTransparency = 0,
		Text = "",
	}, screen)

	local timerTrack = make("Frame", {
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -164),
		Size = UDim2.fromOffset(620, 8),
		BackgroundColor3 = Ui.DARK,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
	}, screen)
	local timerFill = make("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Ui.YELLOW,
		BorderSizePixel = 0,
	}, timerTrack)

	local buttonRow = make("Frame", {
		Name = "Skills",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(620, 140),
		BackgroundTransparency = 1,
	}, screen)

	local function buttonText(parent: Instance, y: number, height: number, textSize: number): TextLabel
		return make("TextLabel", {
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, height),
			BackgroundTransparency = 1,
			Font = FONT,
			TextSize = textSize,
			RichText = true,
			TextColor3 = Ui.BROWN,
			Text = "",
		}, parent)
	end

	local skillButtons: { SkillButton } = {}
	for index = 1, 3 do
		local button = make("TextButton", {
			Name = "Skill" .. index,
			Position = UDim2.fromOffset((index - 1) * 210, 0),
			Size = UDim2.fromOffset(200, 140),
			BackgroundColor3 = Ui.WHITE,
			Text = "",
			AutoButtonColor = false,
		}, buttonRow)
		round(button, 16)
		local shade = make("TextLabel", {
			Name = "Shade",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Ui.DARK,
			BackgroundTransparency = 0.35,
			Font = FONT,
			TextSize = 44,
			TextColor3 = Ui.WHITE,
			Text = "",
			Visible = false,
			ZIndex = 3,
		}, button)
		round(shade, 16)
		skillButtons[index] = {
			button = button,
			icon = buttonText(button, 8, 46, 36),
			name = buttonText(button, 56, 26, 17),
			hint = buttonText(button, 82, 20, 14),
			matchup = buttonText(button, 102, 32, 16),
			shade = shade,
		}
	end

	local forfeitButton = make("TextButton", {
		Name = "Forfeit",
		-- слева по центру: в углах экрана кнопки самого Roblox, и нажатие уходит им
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(120, 40),
		BackgroundColor3 = Ui.GREY,
		Font = FONT,
		TextSize = 16,
		TextColor3 = Ui.WHITE,
		Text = "Сдаться",
	}, screen)
	round(forfeitButton, 12)

	local resultPanel = make("Frame", {
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(480, 400),
		BackgroundColor3 = Ui.CREAM,
		Visible = false,
		ZIndex = 5,
	}, screen)
	round(resultPanel, 20)
	local resultTitle = make("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 34,
		TextColor3 = Ui.BROWN,
		Text = "",
		ZIndex = 6,
	}, resultPanel)
	local resultText = make("TextLabel", {
		Name = "Text",
		Position = UDim2.fromOffset(20, 60),
		Size = UDim2.fromOffset(440, 200),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 18,
		TextWrapped = true,
		TextColor3 = Ui.BROWN,
		Text = "",
		ZIndex = 6,
	}, resultPanel)
	local function resultButton(name: string, y: number, color: Color3): TextButton
		local button = make("TextButton", {
			Name = name,
			Position = UDim2.fromOffset(40, y),
			Size = UDim2.fromOffset(400, 54),
			BackgroundColor3 = color,
			Font = FONT,
			TextSize = 22,
			TextColor3 = Ui.WHITE,
			Text = "",
			ZIndex = 6,
		}, resultPanel)
		round(button, 14)
		return button
	end
	local againButton = resultButton("Again", 270, Ui.GREEN)
	local homeButton = resultButton("Home", 332, Ui.ORANGE)
	homeButton.Text = "К печам"

	-- Состояние идущего боя: только то, что прислал сервер

	local battleId = 0
	local phase = "none"
	local currentRound = 0
	local deadline, timeSpan = 0, 1
	local you: SideView? = nil
	local foe: SideView? = nil
	local chosen: string? = nil
	local options: { number } = {}
	local startToken = 0

	local function setHp(card: CardView, hp: number, hpMax: number, animate: boolean)
		local share = math.clamp(hp / hpMax, 0, 1)
		local goal = { Size = UDim2.fromScale(share, 1), BackgroundColor3 = Ui.RED:Lerp(Ui.GREEN, share) }
		if animate then
			TweenService:Create(card.fill, TweenInfo.new(0.3), goal):Play()
		else
			card.fill.Size = goal.Size
			card.fill.BackgroundColor3 = goal.BackgroundColor3
		end
		card.hp.Text = Format.number(hp) .. " / " .. Format.number(hpMax)
	end

	local function showCard(card: CardView, side: SideView, other: SideView)
		local fighter = side.team[side.active]
		local rival = other.team[other.active]
		card.name.Text =
			string.format("%s %s · ур. %d", typeIcons(fighter.key, 22, 13), fighterName(fighter), fighter.level)
		setHp(card, fighter.hp, fighter.hpMax, false)

		local notes = {}
		if fighter.frozen then
			table.insert(notes, "заморожен")
		end
		if fighter.slow then
			table.insert(notes, "замедлен")
		end
		if fighter.shield then
			table.insert(notes, "щит")
		end
		-- у кого сейчас выше скорость, тот при прочих равных ходит первым
		local mySpeed = if fighter.slow then fighter.spd / 2 else fighter.spd
		local rivalSpeed = if rival.slow then rival.spd / 2 else rival.spd
		if #notes == 0 and fighter.hp > 0 and mySpeed > rivalSpeed then
			table.insert(notes, "быстрее")
		end
		card.status.Text = table.concat(notes, " · ")

		for index, dot in card.dots do
			local member = side.team[index]
			dot.Visible = member ~= nil
			if member then
				dot.BackgroundColor3 = if member.hp <= 0
					then Ui.GREY
					elseif index == side.active then Ui.YELLOW
					else Ui.GREEN
			end
		end
	end

	local function showButtons()
		local mine, theirs = you, foe
		if not mine or not theirs then
			return
		end
		if phase == "replace" then
			-- те же три кнопки показывают, кого можно выпустить
			for index, view in skillButtons do
				local fighter = if options[index] then mine.team[options[index]] else nil
				view.button.Visible = fighter ~= nil
				view.shade.Visible = false
				if fighter then
					view.button.BackgroundColor3 = Ui.WHITE
					view.icon.Text = typeIcons(fighter.key, 36, 20)
					view.name.Text = GameData.Recipes[fighter.key].name
					view.hint.Text = "ур. " .. fighter.level
					view.matchup.Text = Format.number(fighter.hp) .. " / " .. Format.number(fighter.hpMax)
					view.matchup.TextSize = 16
					view.matchup.TextColor3 = Ui.BROWN
				end
			end
			return
		end

		local fighter = mine.team[mine.active]
		local rival = theirs.team[theirs.active]
		for index, view in skillButtons do
			local skillId = fighter.skills[index]
			view.button.Visible = true
			if not skillId then
				view.button.BackgroundColor3 = Ui.GREY
				view.icon.Text = "🔒"
				view.name.Text = "Второй скилл"
				view.hint.Text = "с " .. GameData.SECOND_SKILL_LEVEL .. " уровня"
				view.matchup.Text = ""
				view.shade.Visible = false
				continue
			end
			local skill = GameData.Skills[skillId]
			local wait = fighter.cooldown[skillId] or 0
			-- стрелки — готовый итог по обоим типам соперника: «жми, где больше зелёных»
			local _, arrows = BattleRules.typeMultiplier(skill.type, rival.key)
			view.icon.Text = if skill.type then GameData.IngredientById[skill.type].emoji else "Кусь"
			view.name.Text = if skill.type then skill.name else ""
			view.hint.Text = skill.hint
			view.matchup.Text = ARROWS[arrows] or ""
			view.matchup.TextSize = 30
			view.matchup.TextColor3 = if arrows > 0 then Ui.GREEN else Ui.RED
			view.shade.Visible = wait > 0
			view.shade.Text = tostring(wait)
			view.button.BackgroundColor3 = if chosen == skillId
				then Ui.YELLOW
				elseif phase == "choose" and not chosen then Ui.WHITE
				else Ui.TRACK
		end
	end

	local function render(message: any)
		you = message.you
		foe = message.foe
		showCard(youCard, message.you, message.foe)
		showCard(foeCard, message.foe, message.you)
		showButtons()
	end

	-- Надпись у карточки, улетающая вверх: урон, «Крит!», «Заморожен»
	local function float(card: CardView, text: string, color: Color3, shift: number)
		local above = card == youCard
		local label = make("TextLabel", {
			AnchorPoint = Vector2.new(0.5, if above then 1 else 0),
			Position = card.frame.Position
				+ UDim2.fromOffset(shift, if above then -card.frame.Size.Y.Offset - 6 else card.frame.Size.Y.Offset + 6),
			Size = UDim2.fromOffset(360, 34),
			BackgroundTransparency = 1,
			Font = FONT,
			TextSize = 28,
			TextColor3 = color,
			TextStrokeTransparency = 0,
			Text = text,
			ZIndex = 4,
		}, screen)
		local tween = TweenService:Create(label, TweenInfo.new(1), {
			Position = label.Position + UDim2.fromOffset(0, if above then -40 else 40),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		tween.Completed:Connect(function()
			label:Destroy()
		end)
		tween:Play()
	end

	-- Проигрывает раунд в том же темпе, в каком его ведёт сервер
	local function playRound(message: any)
		local mine, theirs = you, foe
		if not mine or not theirs then
			return
		end
		phase = "resolve"
		showButtons()
		for _, event in message.events do
			local actorSide = if event.side == 1 then mine else theirs
			local targetSide = if event.side == 1 then theirs else mine
			local actorCard = if event.side == 1 then youCard else foeCard
			local targetCard = if event.side == 1 then foeCard else youCard
			local actor = actorSide.team[actorSide.active]
			local target = targetSide.team[targetSide.active]

			if event.kind == "hit" then
				banner.Text = fighterName(actor) .. ": " .. GameData.Skills[event.skill].name .. "!"
				task.wait(IMPACT_DELAY)
				target.hp = event.targetHp
				setHp(targetCard, target.hp, target.hpMax, true)
				local text = "-" .. Format.number(event.damage)
				if event.crit then
					text ..= "  Крит!"
				end
				local word = GameData.MatchupWords[event.matchup or 0]
				if word then
					text ..= "  " .. word
				end
				float(targetCard, text, if event.crit then Ui.YELLOW else Ui.WHITE, 0)
				if event.shielded then
					float(targetCard, "Щит выдержал", BLUE, 190)
				end
				if event.heal and event.heal > 0 then
					actor.hp = event.actorHp
					setHp(actorCard, actor.hp, actor.hpMax, true)
					float(actorCard, "+" .. Format.number(event.heal), Ui.GREEN, 0)
				end
				if event.applied == "freeze" then
					float(targetCard, "Заморожен", BLUE, -190)
				elseif event.applied == "slow" then
					float(targetCard, "Замедлен", Ui.ORANGE, -190)
				elseif event.applied == "shield" then
					float(actorCard, "Щит", BLUE, -190)
				elseif event.immune then
					float(targetCard, "Не замёрз", BLUE, -190)
				end
				task.wait(RULES.actionTime - IMPACT_DELAY)
			elseif event.kind == "skip" then
				banner.Text = fighterName(actor) .. " заморожен и пропускает ход"
				task.wait(RULES.actionTime)
			elseif event.kind == "ko" then
				-- у события «выбыл» side — сторона, потерявшая зверька
				banner.Text = fighterName(actor) .. " выбыл!"
				actor.hp = 0
				setHp(actorCard, 0, actor.hpMax, true)
				task.wait(RULES.koTime)
			end
		end
		chosen = nil
		render(message)
	end

	-- Таблички своего участка (имена зверьков, цены, полоски на ринге) рассчитаны на соседей,
	-- а у самого игрока ложатся поверх экрана боя: на время боя они гаснут
	local hiddenSigns: { BillboardGui } = {}
	local signWatch: RBXScriptConnection? = nil

	local function hideSign(instance: Instance)
		if instance:IsA("BillboardGui") and instance.Enabled then
			instance.Enabled = false
			table.insert(hiddenSigns, instance)
		end
	end

	local function setWorldSigns(visible: boolean)
		if visible then
			if signWatch then
				signWatch:Disconnect()
				signWatch = nil
			end
			for _, sign in hiddenSigns do
				sign.Enabled = true
			end
			table.clear(hiddenSigns)
		elseif not signWatch then
			local plots = workspace:FindFirstChild("Plots")
			for _, plot in if plots then plots:GetChildren() else {} do
				if plot:GetAttribute("OwnerId") == Players.LocalPlayer.UserId then
					for _, descendant in plot:GetDescendants() do
						hideSign(descendant)
					end
					signWatch = plot.DescendantAdded:Connect(hideSign)
				end
			end
		end
	end

	local function setHud(visible: boolean)
		context.hud.Visible = visible
		setWorldSigns(visible)
	end

	local function exitBattle()
		inBattle = false
		phase = "none"
		screen.Visible = false
		resultPanel.Visible = false
		setHud(true)
		RunService:UnbindFromRenderStep(CAMERA_BINDING)
		local camera = workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
		refreshPanel()
	end

	local function enterBattle(message: any)
		inBattle = true
		startToken += 1
		battleId = message.id
		chosen = nil
		panel.Visible = false
		wheel.Visible = false
		context.closePanels()
		setHud(false)
		resultPanel.Visible = false
		screen.Visible = true
		-- Камеру держим каждый кадр: стандартный скрипт камеры возвращает её к персонажу,
		-- например когда персонаж появляется заново
		local view: CFrame = message.camera
		RunService:UnbindFromRenderStep(CAMERA_BINDING)
		RunService:BindToRenderStep(CAMERA_BINDING, Enum.RenderPriority.Camera.Value + 1, function()
			local camera = workspace.CurrentCamera
			if camera then
				camera.CameraType = Enum.CameraType.Scriptable
				camera.CFrame = view
			end
		end)
		phase = "intro"
		banner.Text = (if message.boss then "БОСС! " else "") .. "Этаж " .. message.floor
		forfeitButton.Text = "Сдаться"
		render(message)
	end

	local function showResult(message: any)
		local mine = you
		local won = message.result == "win"
		resultTitle.Text = if won then "Победа!" else "Поражение"
		local lines = {
			string.format(
				if won then "Этаж %d пройден" else "Этаж %d пока не взят",
				message.floor
			),
		}
		if message.coins > 0 then
			table.insert(lines, "💰 +" .. Format.number(message.coins))
		end
		if mine then
			for _, fighter in mine.team do
				local change = message.levels[fighter.key]
				if change and message.xp > 0 then
					table.insert(
						lines,
						string.format(
							"%s: +%d опыта · ур. %d%s",
							GameData.Recipes[fighter.key].name,
							message.xp,
							change.level,
							if change.leveledUp then " — новый уровень!" else ""
						)
					)
				end
			end
		end
		if not won and message.xp == 0 then
			table.insert(lines, "Бой не доигран — опыта нет")
		end

		againButton.Visible = not won or message.nextOpen
		againButton.Text = if won then "Следующий этаж" else "Ещё раз"
		if won and not message.nextOpen then
			table.insert(lines, "Все этажи пройдены. Новые скоро!")
		end
		resultText.Text = table.concat(lines, "\n")
		banner.Text = ""
		resultPanel.Visible = true
	end

	-- Сообщения сервера обрабатываются строго по очереди: раунд проигрывается секунды, следующее ждёт
	local queue: { any } = {}
	local pumping = false

	local function handle(message: any)
		if message.kind == "start" then
			enterBattle(message)
		elseif message.id ~= battleId or not inBattle then
			return
		elseif message.kind == "choose" then
			render(message)
			chosen = nil
			currentRound = message.round
			deadline, timeSpan = message.deadline, RULES.chooseTime
			phase = "choose"
			banner.Text = "Твой ход!"
			showButtons()
		elseif message.kind == "round" then
			playRound(message)
		elseif message.kind == "replace" then
			render(message)
			options = message.options
			deadline, timeSpan = message.deadline, RULES.replaceTime
			phase = "replace"
			banner.Text = "Кого выпустить?"
			showButtons()
		elseif message.kind == "end" then
			render(message)
			phase = "ended"
			showButtons()
			showResult(message)
		end
	end

	remotes.BattleEvent.OnClientEvent:Connect(function(message)
		table.insert(queue, message)
		if pumping then
			return
		end
		pumping = true
		while #queue > 0 do
			handle(table.remove(queue, 1))
		end
		pumping = false
	end)

	local function startTower()
		startToken += 1
		local token = startToken
		remotes.BattleStart:FireServer("tower")
		-- сервер мог отказать (бой уже идёт, этажи кончились): не оставляем игрока на пустом экране
		task.delay(START_TIMEOUT, function()
			if startToken == token and inBattle and phase == "ended" then
				exitBattle()
			end
		end)
	end

	fightButton.Activated:Connect(function()
		local state = context.getState()
		if (state.tower or 0) < GameData.TOWER_FLOORS_OPEN then
			startTower()
		end
	end)

	againButton.Activated:Connect(function()
		resultPanel.Visible = false
		banner.Text = "Готовимся…"
		startTower()
	end)

	homeButton.Activated:Connect(exitBattle)

	for index, view in skillButtons do
		view.button.Activated:Connect(function()
			local mine = you
			if not mine then
				return
			end
			if phase == "replace" then
				if options[index] then
					remotes.BattlePick:FireServer(battleId, options[index])
					phase = "resolve"
				end
			elseif phase == "choose" and not chosen then
				local fighter = mine.team[mine.active]
				local skillId = fighter.skills[index]
				if skillId and (fighter.cooldown[skillId] or 0) == 0 then
					chosen = skillId
					remotes.BattleAction:FireServer(battleId, currentRound, skillId)
					showButtons()
				end
			end
		end)
	end

	-- Сдаться можно только вторым нажатием: кнопка маленькая, но промахнуться по ней легко
	local forfeitArmed = 0
	forfeitButton.Activated:Connect(function()
		if phase ~= "choose" and phase ~= "replace" then
			return
		end
		if os.clock() - forfeitArmed < 3 then
			remotes.BattleForfeit:FireServer(battleId)
			forfeitButton.Text = "Сдаться"
		else
			forfeitArmed = os.clock()
			forfeitButton.Text = "Точно?"
			task.delay(3, function()
				forfeitButton.Text = "Сдаться"
			end)
		end
	end)

	RunService.Heartbeat:Connect(function()
		if not inBattle then
			return
		end
		local left = 0
		if phase == "choose" or phase == "replace" then
			left = math.clamp((deadline - workspace:GetServerTimeNow()) / timeSpan, 0, 1)
		end
		timerFill.Size = UDim2.fromScale(left, 1)
	end)

	BattleScreen.refresh = refreshPanel
	BattleScreen.closePanel = function()
		panel.Visible = false
		wheel.Visible = false
	end
end

return BattleScreen
