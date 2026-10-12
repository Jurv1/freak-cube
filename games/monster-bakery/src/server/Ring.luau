--!strict
-- Ринг на участке игрока: временные копии двух зверьков, полоски здоровья, цифры урона.
-- Это то, что видят соседи; у самого игрока поверх — экран боя.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameData"))
local BattleEngine = require(script.Parent.BattleEngine)
local Plots = require(script.Parent.Plots)

-- Свободный угол участка со стороны центра карты (в координатах участка)
local CENTER = CFrame.new(14, 0, -13)
local HALF_GAP = 4 -- зверьки стоят в 8 studs друг от друга
local GIANT_SCALE = 1.5
local MAT_SIZE = Vector3.new(16, 0.2, 9)
local GOLD = Color3.fromRGB(255, 205, 50)
local HP_GREEN = Color3.fromRGB(90, 200, 110)
local HP_RED = Color3.fromRGB(235, 100, 90)

local Ring = {}

local function origin(plotIndex: number): CFrame
	return Plots.plotCFrame(plotIndex) * CENTER
end

-- Где стоит зверёк стороны: свой — слева от камеры боя, чужой — справа, мордочками друг к другу
local function spot(plotIndex: number, sideIndex: number, scale: number): CFrame
	local x = if sideIndex == 1 then HALF_GAP else -HALF_GAP
	local height = Plots.FLOOR_TOP + MAT_SIZE.Y + Plots.CREATURE_SIZE * scale / 2
	local base = origin(plotIndex)
	return CFrame.lookAt((base * CFrame.new(x, height, 0)).Position, (base * CFrame.new(-x, height, 0)).Position)
end

-- Вид сбоку на обоих зверьков: сюда клиент ставит камеру на время боя
function Ring.camera(plotIndex: number): CFrame
	local base = origin(plotIndex)
	return CFrame.lookAt((base * CFrame.new(0, 4.5, -11)).Position, (base * CFrame.new(0, 2.6, 0)).Position)
end

function Ring.open(plot: Model, plotIndex: number): Model
	local ring = Instance.new("Model")
	ring.Name = "Ring"
	ring:SetAttribute("PlotIndex", plotIndex)

	local mat = Instance.new("Part")
	mat.Name = "Mat"
	mat.Anchored = true
	mat.Size = MAT_SIZE
	mat.CFrame = origin(plotIndex) * CFrame.new(0, Plots.FLOOR_TOP + MAT_SIZE.Y / 2, 0)
	mat.Color = Color3.fromRGB(235, 120, 110)
	mat.Material = Enum.Material.SmoothPlastic
	mat.TopSurface = Enum.SurfaceType.Smooth
	mat.Parent = ring

	ring.Parent = plot
	return ring
end

local function body(ring: Model, sideIndex: number): Part?
	return ring:FindFirstChild("Side" .. sideIndex) :: Part?
end

function Ring.setHp(ring: Model, sideIndex: number, hp: number, hpMax: number)
	local part = body(ring, sideIndex)
	local board = part and part:FindFirstChild("Hp")
	if not board then
		return
	end
	local share = math.clamp(hp / hpMax, 0, 1)
	local fill = (board:FindFirstChild("Track") :: Frame):FindFirstChild("Fill") :: Frame
	fill.Size = UDim2.fromScale(share, 1)
	fill.BackgroundColor3 = HP_RED:Lerp(HP_GREEN, share)
end

-- Ставит на ринг зверька стороны; прежний, если был, убирается
function Ring.place(ring: Model, sideIndex: number, fighter: BattleEngine.Fighter)
	local old = body(ring, sideIndex)
	if old then
		old:Destroy()
	end
	local plotIndex = ring:GetAttribute("PlotIndex") :: number
	local scale = if fighter.giant then GIANT_SCALE else 1
	local recipe = GameData.Recipes[fighter.key]
	local part = Plots.creatureBody(ring, "Side" .. sideIndex, spot(plotIndex, sideIndex, scale), scale)
	part.Color = if fighter.giant then GOLD else recipe.color
	part.Material = if fighter.giant then Enum.Material.Foil else Enum.Material.SmoothPlastic

	local board = Instance.new("BillboardGui")
	board.Name = "Hp"
	board.Size = UDim2.fromScale(8, 2.2)
	board.StudsOffset = Vector3.new(0, Plots.CREATURE_SIZE * scale / 2 + 1.7, 0)
	board.MaxDistance = 120
	board.Parent = part

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.Size = UDim2.fromScale(1, 0.55)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.2
	name.Text = (if fighter.giant then "Гигант " else "") .. recipe.name .. " · ур. " .. fighter.level
	name.Parent = board

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromScale(0.1, 0.64)
	track.Size = UDim2.fromScale(0.8, 0.28)
	track.BackgroundColor3 = Color3.fromRGB(45, 35, 30)
	track.BorderSizePixel = 0
	track.Parent = board
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.Parent = track

	Ring.setHp(ring, sideIndex, fighter.hp, fighter.hpMax)
end

-- Всплывающая надпись над зверьком стороны: урон, «Заморожен» и так далее
function Ring.note(ring: Model, sideIndex: number, text: string, color: Color3)
	local part = body(ring, sideIndex)
	if not part then
		return
	end
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromScale(7, 1.6)
	board.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 3.2, 0)
	board.MaxDistance = 120
	board.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.Text = text
	label.Parent = board
	TweenService:Create(board, TweenInfo.new(0.9), { StudsOffset = board.StudsOffset + Vector3.new(0, 2.5, 0) }):Play()
	Debris:AddItem(board, 0.95)
end

-- Выпад атакующего в сторону соперника и обратно
function Ring.lunge(ring: Model, sideIndex: number)
	local part = body(ring, sideIndex)
	if not part then
		return
	end
	local home = part.CFrame
	local tween = TweenService:Create(
		part,
		TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
		{ CFrame = home * CFrame.new(0, 0, -2.5) }
	)
	tween:Play()
end

function Ring.remove(ring: Model, sideIndex: number)
	local part = body(ring, sideIndex)
	if part then
		part.Name = "Fallen"
		TweenService:Create(part, TweenInfo.new(0.4), { Size = Vector3.one * 0.3, Transparency = 1 }):Play()
		Debris:AddItem(part, 0.45)
	end
end

function Ring.close(ring: Model)
	ring:Destroy()
end

return Ring
