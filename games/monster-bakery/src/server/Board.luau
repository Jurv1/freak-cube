--!strict
-- Доска лидеров в центре карты: десять лучших в мире и лучший на этом сервере.

local SHOWN = 10
local SIZE = Vector3.new(20, 13, 1)
local PIXELS_PER_STUD = 40

local Board = {}

local labels: { TextLabel } = {}

local function build()
	local board = Instance.new("Part")
	board.Name = "LeaderBoard"
	board.Anchored = true
	-- доска висит над точкой появления: столкновения выключены, чтобы новый персонаж в ней не застрял
	board.CanCollide = false
	board.Size = SIZE
	-- повёрнута гранями к первому и четвёртому участкам
	board.CFrame = CFrame.new(0, 12, 0) * CFrame.Angles(0, math.rad(90), 0)
	board.Color = Color3.fromRGB(70, 45, 30)
	board.Material = Enum.Material.Wood
	board.TopSurface = Enum.SurfaceType.Smooth
	board.BottomSurface = Enum.SurfaceType.Smooth

	for _, side in { -1, 1 } do
		local leg = Instance.new("Part")
		leg.Name = "Leg"
		leg.Anchored = true
		leg.Size = Vector3.new(1, 5.5, 1)
		leg.CFrame = board.CFrame * CFrame.new(side * (SIZE.X / 2 - 0.5), -SIZE.Y / 2 - 2.75, 0)
		leg.Color = board.Color
		leg.Material = Enum.Material.Wood
		leg.Parent = board
	end

	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = PIXELS_PER_STUD
		gui.Parent = board
		local text = Instance.new("TextLabel")
		text.AnchorPoint = Vector2.new(0.5, 0.5)
		text.Position = UDim2.fromScale(0.5, 0.5)
		text.Size = UDim2.fromScale(0.92, 0.9)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBold
		-- пока строк мало, буквы крупнее: доску читают издалека
		text.TextScaled = true
		text.TextColor3 = Color3.fromRGB(255, 244, 225)
		text.Parent = gui
		table.insert(labels, text)
	end

	board.Parent = workspace
end

type Row = { userId: number, name: string, value: number }

function Board.show(top: { Row }, best: Row?)
	if #labels == 0 then
		build()
	end
	local lines = { "МАСТЕРСТВО · ЛУЧШИЕ В МИРЕ" }
	for index = 1, math.min(SHOWN, #top) do
		table.insert(lines, string.format("%d. %s — %d", index, top[index].name, top[index].value))
	end
	if #top == 0 then
		table.insert(lines, "Пока никого. Будь первым!")
	end
	table.insert(lines, "")
	table.insert(lines, if best then string.format("Лучший здесь: %s — %d", best.name, best.value) else "")
	local text = table.concat(lines, "\n")
	for _, label in labels do
		label.Text = text
	end
end

return Board
