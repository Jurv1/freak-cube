--!strict
-- Общее для экранов клиента: цвета, шрифт, создание элементов.

local Ui = {}

Ui.FONT = Enum.Font.GothamBold
Ui.WHITE = Color3.new(1, 1, 1)
Ui.CREAM = Color3.fromRGB(255, 244, 225)
Ui.BROWN = Color3.fromRGB(90, 55, 35)
Ui.GREEN = Color3.fromRGB(90, 200, 110)
Ui.GREY = Color3.fromRGB(190, 185, 180)
Ui.YELLOW = Color3.fromRGB(255, 220, 110)
Ui.ORANGE = Color3.fromRGB(240, 150, 70)
Ui.RED = Color3.fromRGB(235, 100, 90)
Ui.GOLD = Color3.fromRGB(255, 205, 50)
Ui.TRACK = Color3.fromRGB(225, 215, 200)
Ui.FRIEND = Color3.fromRGB(205, 240, 210)
Ui.DARK = Color3.fromRGB(45, 35, 30)

function Ui.make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

function Ui.round(instance: Instance, radius: number)
	Ui.make("UICorner", { CornerRadius = UDim.new(0, radius) }, instance)
end

return Ui
