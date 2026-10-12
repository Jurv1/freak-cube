--!strict
-- Всё, что видно в мире: участки, печи, площадки под новые печи, зверьки.
-- Правил игры здесь нет: модуль рисует то, что ему передали.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local GameData = require(Shared:WaitForChild("GameData"))

local PLOT_RADIUS = 70
local PLOT_SIZE = 44
local PEN_RADIUS = 9
local FLOOR_TOP = 0.5
local CREATURE_SIZE = 3.2
local MAX_GROWTH_STEPS = 5
-- Место печи на участке по слотам; вторая печь — слева, если смотреть от входа
local OVEN_OFFSETS = { Vector3.new(0, 0, 15), Vector3.new(12, 0, 15), Vector3.new(-12, 0, 15) }
local SPAWN_OFFSET = CFrame.new(0, 5, -17) * CFrame.Angles(0, math.pi, 0)

local GOLD = Color3.fromRGB(255, 205, 50)
local PAD_IDLE = Color3.fromRGB(215, 210, 205)
local PAD_READY = Color3.fromRGB(90, 200, 110)

type TierLook = {
	body: Color3,
	material: Enum.Material,
	door: Color3,
	transparency: number?,
	light: Color3?,
	sparkles: boolean?,
}

-- Вид печи по уровню: кирпич, чугун с латунной дверцей, сталь, хрусталь, лунная, звёздная
local TIER_LOOKS: { TierLook } = {
	{ body = Color3.fromRGB(190, 95, 65), material = Enum.Material.Brick, door = Color3.fromRGB(45, 40, 45) },
	{ body = Color3.fromRGB(45, 45, 50), material = Enum.Material.Metal, door = Color3.fromRGB(200, 160, 60) },
	{ body = Color3.fromRGB(205, 210, 218), material = Enum.Material.Metal, door = Color3.fromRGB(70, 75, 85) },
	{
		body = Color3.fromRGB(150, 225, 255),
		material = Enum.Material.Glass,
		door = Color3.fromRGB(255, 255, 255),
		transparency = 0.25,
		light = Color3.fromRGB(150, 225, 255),
	},
	{
		body = Color3.fromRGB(35, 45, 105),
		material = Enum.Material.SmoothPlastic,
		door = Color3.fromRGB(255, 240, 170),
		light = Color3.fromRGB(255, 240, 170),
	},
	{
		body = Color3.fromRGB(30, 20, 70),
		material = Enum.Material.SmoothPlastic,
		door = Color3.fromRGB(255, 220, 120),
		light = Color3.fromRGB(190, 140, 255),
		sparkles = true,
	},
}

local Plots = {}

Plots.PLOT_COUNT = 6

local plotsFolder = Instance.new("Folder")
plotsFolder.Name = "Plots"
plotsFolder.Parent = workspace

local function plotCFrame(index: number): CFrame
	local angle = (index - 1) / Plots.PLOT_COUNT * 2 * math.pi
	local position = Vector3.new(math.cos(angle) * PLOT_RADIUS, 0, math.sin(angle) * PLOT_RADIUS)
	return CFrame.lookAt(position, Vector3.zero)
end

local function newPart(props: { [string]: any }, parent: Instance): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = parent
	return part
end

Plots.plotCFrame = plotCFrame
Plots.FLOOR_TOP = FLOOR_TOP
Plots.CREATURE_SIZE = CREATURE_SIZE

-- Табличка над деталью; возвращает её текст
local function newSign(name: string, parent: Instance, size: UDim2, offset: Vector3, maxDistance: number): TextLabel
	local board = Instance.new("BillboardGui")
	board.Name = name
	board.Size = size
	board.StudsOffset = offset
	board.MaxDistance = maxDistance
	board.Parent = parent
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.2
	text.Parent = board
	return text
end

local function signText(part: Instance, name: string): TextLabel
	return (part:FindFirstChild(name) :: BillboardGui):FindFirstChild("Text") :: TextLabel
end

-- Участок

function Plots.build(index: number, player: Player): Model
	local origin = plotCFrame(index)
	local plot = Instance.new("Model")
	plot.Name = "Plot" .. index
	plot:SetAttribute("OwnerId", player.UserId)
	plot:SetAttribute("PlotIndex", index)

	newPart({
		Name = "Floor",
		Size = Vector3.new(PLOT_SIZE, FLOOR_TOP, PLOT_SIZE),
		CFrame = origin * CFrame.new(0, FLOOR_TOP / 2, 0),
		Color = Color3.fromRGB(255, 236, 200),
		Material = Enum.Material.SmoothPlastic,
	}, plot)

	local anchor = newPart({
		Name = "SignAnchor",
		Size = Vector3.one,
		CFrame = origin * CFrame.new(OVEN_OFFSETS[1]) * CFrame.new(0, 16, 0),
		Transparency = 1,
		CanCollide = false,
	}, plot)
	plot:SetAttribute("OwnerName", player.DisplayName)
	newSign("Sign", anchor, UDim2.fromScale(16, 4), Vector3.zero, 150).Text = "Пекарня " .. player.DisplayName

	local creatures = Instance.new("Folder")
	creatures.Name = "Creatures"
	creatures.Parent = plot

	plot.Parent = plotsFolder
	return plot
end

function Plots.spawnCFrame(index: number): CFrame
	return plotCFrame(index) * SPAWN_OFFSET
end

-- Вторая строка таблички пекарни: её видят соседи
function Plots.setMastery(plot: Model, mastery: number)
	local anchor = plot:FindFirstChild("SignAnchor") :: Part
	local text = "Пекарня " .. tostring(plot:GetAttribute("OwnerName"))
	if mastery > 0 then
		text ..= "\nМастерство " .. mastery
	end
	signText(anchor, "Sign").Text = text
end

-- Печи

local function ovenCFrame(plotIndex: number, slot: number): CFrame
	return plotCFrame(plotIndex) * CFrame.new(OVEN_OFFSETS[slot])
end

local function ovenPart(plot: Model, slot: number, name: string): Part
	return (plot:FindFirstChild("Oven" .. slot) :: Model):FindFirstChild(name) :: Part
end

function Plots.setOvenTier(plot: Model, slot: number, tier: number)
	local look = TIER_LOOKS[tier]
	local body = ovenPart(plot, slot, "Body")
	local chimney = ovenPart(plot, slot, "Chimney")
	local door = ovenPart(plot, slot, "Door")

	body.Color = look.body
	body.Material = look.material
	body.Transparency = look.transparency or 0
	chimney.Color = look.body:Lerp(Color3.new(0, 0, 0), 0.2)
	chimney.Material = look.material
	door.Color = look.door

	local aura = body:FindFirstChild("Aura") :: PointLight
	aura.Enabled = look.light ~= nil
	aura.Color = look.light or Color3.new(1, 1, 1)
	local sparkles = body:FindFirstChild("Sparkles") :: Sparkles
	sparkles.Enabled = look.sparkles == true

	signText(door, "TierTag").Text = if tier > 1 then GameData.OvenTiers[tier].name else ""
end

function Plots.addOven(plot: Model, plotIndex: number, slot: number, tier: number, ownerId: number)
	local base = ovenCFrame(plotIndex, slot)
	local oven = Instance.new("Model")
	oven.Name = "Oven" .. slot

	local body = newPart({ Name = "Body", Size = Vector3.new(9, 8, 7), CFrame = base * CFrame.new(0, 4.5, 0) }, oven)
	newPart({ Name = "Chimney", Size = Vector3.new(2.5, 5, 2.5), CFrame = base * CFrame.new(2.5, 11, 1) }, oven)
	local door = newPart({
		Name = "Door",
		Size = Vector3.new(5.5, 4, 0.4),
		CFrame = base * CFrame.new(0, 3.5, -3.6),
		Material = Enum.Material.Metal,
	}, oven)

	local aura = Instance.new("PointLight")
	aura.Name = "Aura"
	aura.Range = 16
	aura.Brightness = 1.5
	aura.Parent = body
	local sparkles = Instance.new("Sparkles")
	sparkles.Name = "Sparkles"
	sparkles.SparkleColor = Color3.fromRGB(255, 240, 170)
	sparkles.Parent = body

	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Color = Color3.fromRGB(255, 150, 60)
	glow.Range = 14
	glow.Brightness = 3
	glow.Enabled = false
	glow.Parent = door

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OvenPrompt"
	prompt.ObjectText = "Печь " .. slot
	prompt.ActionText = "Открыть"
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OwnerId", ownerId)
	prompt:SetAttribute("OvenIndex", slot)
	prompt.Parent = door

	newSign("TierTag", door, UDim2.fromScale(8, 1.4), Vector3.new(0, 3, 0), 90)

	oven.Parent = plot
	Plots.setOvenTier(plot, slot, tier)
end

function Plots.setOvenGlow(plot: Model, slot: number, on: boolean)
	local glow = ovenPart(plot, slot, "Door"):FindFirstChild("Glow") :: PointLight
	glow.Enabled = on
end

-- Точка перед дверцей, откуда выходит готовый зверёк
function Plots.ovenExit(plot: Model, slot: number): Vector3
	return (ovenPart(plot, slot, "Door").CFrame * CFrame.new(0, 0, -3)).Position
end

-- Площадки под ещё не купленные печи: следующая цель видна с первой секунды.
-- На ближайшей — накопленное и покупка, на остальных — только цена: печи покупаются по порядку.
function Plots.setSlotPads(plot: Model, plotIndex: number, owned: number, coins: number, ownerId: number)
	for slot, price in GameData.OvenSlotPrices do
		local name = "SlotPad" .. slot
		local pad = plot:FindFirstChild(name) :: Part?
		if slot <= owned then
			if pad then
				pad:Destroy()
			end
			continue
		end

		if not pad then
			local newPad = newPart({
				Name = name,
				Size = Vector3.new(9, 0.4, 7),
				CFrame = ovenCFrame(plotIndex, slot) * CFrame.new(0, FLOOR_TOP + 0.2, 0),
				Material = Enum.Material.SmoothPlastic,
			}, plot)
			newSign("Price", newPad, UDim2.fromScale(10, 3), Vector3.new(0, 4, 0), 120)

			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "BuyOvenPrompt"
			prompt.ObjectText = "Печь " .. slot
			prompt.ActionText = "Купить"
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt:SetAttribute("OwnerId", ownerId)
			prompt.Parent = newPad
			pad = newPad
		end

		local part = pad :: Part
		local isNext = slot == owned + 1
		local prompt = part:FindFirstChild("BuyOvenPrompt") :: ProximityPrompt
		prompt.Enabled = isNext
		part.Color = if isNext and coins >= price then PAD_READY else PAD_IDLE
		signText(part, "Price").Text = if isNext
			then string.format(
				"Печь %d\n💰 %s / %s",
				slot,
				Format.number(math.min(coins, price)),
				Format.number(price)
			)
			else string.format("Печь %d\n💰 %s", slot, Format.number(price))
	end
end

-- Зверьки

-- Каждые 10 уровней зверёк на 10% крупнее, но не больше чем в полтора раза
local function creatureScale(level: number): number
	return 1 + 0.1 * math.min(MAX_GROWTH_STEPS, level // 10)
end

local function penPoint(plotIndex: number, scale: number): Vector3
	local angle = math.random() * 2 * math.pi
	local distance = math.sqrt(math.random()) * PEN_RADIUS
	local offset =
		CFrame.new(math.cos(angle) * distance, FLOOR_TOP + CREATURE_SIZE * scale / 2, math.sin(angle) * distance)
	return (plotCFrame(plotIndex) * offset).Position
end

-- Тело зверька без таблички: шар с глазами, мордочка смотрит в −Z. Этим же собираются копии для ринга.
function Plots.creatureBody(parent: Instance, name: string, at: CFrame, scale: number): Part
	local size = CREATURE_SIZE * scale
	local body = newPart({
		Name = name,
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size, size),
		CFrame = at,
		CanCollide = false,
	}, parent)
	body:SetAttribute("Scale", scale)

	for _, side in { -1, 1 } do
		local eye = newPart({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.6 * scale,
			CFrame = body.CFrame * CFrame.new(side * 0.6 * scale, 0.45 * scale, -1.4 * scale),
			Color = Color3.fromRGB(25, 25, 30),
			Anchored = false,
			CanCollide = false,
			Massless = true,
		}, body)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = eye
		weld.Parent = eye
	end
	return body
end

local function newCreature(folder: Folder, key: string, position: Vector3, scale: number): Part
	local body = Plots.creatureBody(folder, key, CFrame.new(position), scale)
	newSign("Tag", body, UDim2.fromScale(9, 2.2), Vector3.new(0, 3 * scale, 0), 80)
	return body
end

-- Создаёт зверька или обновляет вид существующего. spawnAt нужен только новому.
function Plots.showCreature(
	plot: Model,
	plotIndex: number,
	key: string,
	level: number,
	golden: boolean,
	spawnAt: Vector3?
)
	local folder = plot:FindFirstChild("Creatures") :: Folder
	local scale = creatureScale(level)
	local body = folder:FindFirstChild(key) :: Part?
	local position = spawnAt

	-- подрос: шар с глазами проще собрать заново, чем масштабировать
	if body and body:GetAttribute("Scale") ~= scale then
		position = Vector3.new(body.Position.X, FLOOR_TOP + CREATURE_SIZE * scale / 2, body.Position.Z)
		body:Destroy()
		body = nil
	end
	if not body then
		body = newCreature(folder, key, position or penPoint(plotIndex, scale), scale)
	end

	local part = body :: Part
	part.Color = if golden then GOLD else GameData.Recipes[key].color
	part.Material = if golden then Enum.Material.Foil else Enum.Material.SmoothPlastic

	local stars = string.rep("★", level // 10)
	signText(part, "Tag").Text = (if golden then "⭐ " else "")
		.. GameData.Recipes[key].name
		.. "\nур. "
		.. level
		.. (if stars ~= "" then " " .. stars else "")
end

task.spawn(function()
	while true do
		task.wait(2.5)
		for _, plot in plotsFolder:GetChildren() do
			local plotIndex = plot:GetAttribute("PlotIndex")
			local folder = plot:FindFirstChild("Creatures")
			if not folder or typeof(plotIndex) ~= "number" then
				continue
			end
			for _, child in folder:GetChildren() do
				if child:IsA("Part") and math.random() < 0.6 then
					local target = penPoint(plotIndex, child:GetAttribute("Scale") or 1)
					local goal = CFrame.lookAt(target, target + (target - child.Position) * Vector3.new(1, 0, 1))
					TweenService:Create(child, TweenInfo.new(1.6, Enum.EasingStyle.Sine), { CFrame = goal }):Play()
				end
			end
		end
	end
end)

return Plots
