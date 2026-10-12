# Пекарня монстриков — 15 моделей для Roblox

Каждый монстрик — **один меш + одна текстура-палитра 256×256**, то есть после импорта это один `MeshPart`.
Имя файла = ключ рецепта из `GameData` (`cheese+flour` и т.д.), поэтому скрипт может находить модель прямо по ключу.

| № | Монстрик | Файл | Треугольников |
|---|----------|------|---------------|
| 1 | Сырный Булкотик | `cheese+flour.glb` | 7 636 |
| 2 | Чизкейк-Хрюша | `cheese+strawberry.glb` | 8 388 |
| 3 | Клубничный Пончозавр | `flour+strawberry.glb` | 10 712 |
| 4 | Фондю-Пёс | `cheese+chocolate.glb` | 10 128 |
| 5 | Шоко-Кексозавр | `chocolate+flour.glb` | 8 196 |
| 6 | Трюфельный Зайка | `chocolate+strawberry.glb` | 7 524 |
| 7 | Пицца-Попугай | `cheese+rainbow.glb` | 7 756 |
| 8 | Радужный Бубликорог | `flour+rainbow.glb` | 10 404 |
| 9 | Мармеладный Дракоша | `rainbow+strawberry.glb` | 7 752 |
| 10 | Конфетти-Хамелеон | `chocolate+rainbow.glb` | 10 960 |
| 11 | Моцарелла-Йети | `cheese+ice.glb` | 9 612 |
| 12 | Снежный Вафлепингвин | `flour+ice.glb` | 9 008 |
| 13 | Пломбирный Тюлень | `ice+strawberry.glb` | 8 260 |
| 14 | Эскимо-Морж | `chocolate+ice.glb` | 7 616 |
| 15 | Лис Северного Сияния | `ice+rainbow.glb` | 7 628 |

## Что в архиве

- `models/` — основной формат, **GLB** (текстура внутри файла).
- `models_obj/` — запасной вариант: OBJ + MTL + PNG, если GLB почему-то не подхватит текстуру.
- `preview.png`, `preview/` — как монстрики должны выглядеть.
- `generator/` — Python-скрипты, которыми модели построены (`python build.py`), если захочется поменять цвета или пропорции.

## Импорт в Roblox Studio

1. **File → Import 3D** (или Home → Import 3D), выбери сразу все 15 файлов из `models/`.
2. В окне импорта проверь:
   - **Scale Unit = Stud** — монстрики должны получиться высотой 3–4 студа (в файле 1 единица = 1 студ);
   - **Anchored** — включить; **Insert in Workspace** — по желанию.
3. Нажми **Import**. Меши и текстуры загрузятся в твой аккаунт и пройдут модерацию.
4. Сложи импортированные модели в папку `ReplicatedStorage.Monsters`. Имена менять не нужно.

Модели уже развёрнуты «по-робло́ксовски»: мордочка смотрит в **−Z** (LookVector), низ стоит на y = 0,
пивот — центр габаритов. `CFrame.lookAt(...)` из серверного скрипта будет поворачивать их лицом по ходу движения.

## Подключение в BakeryServer

Сейчас `showCreature` создаёт шарик с глазами. Чтобы вместо него появлялась модель:

```lua
local monsterFolder = ReplicatedStorage:FindFirstChild("Monsters")
local FLOOR_Y = 0.5 -- верх пола участка

local function monsterTemplate(key: string): MeshPart?
	local found = monsterFolder and monsterFolder:FindFirstChild(key)
	if not found then
		return nil
	end
	return if found:IsA("MeshPart") then found else found:FindFirstChildWhichIsA("MeshPart", true)
end
```

В ветке `if not body then`:

```lua
local template = monsterTemplate(key)
if template then
	local mesh = template:Clone()
	mesh.Name = key
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CFrame = CFrame.new(position.X, FLOOR_Y + mesh.Size.Y / 2, position.Z)
	mesh.Parent = folder
	newBody = mesh
else
	-- старый шарик с глазами как запасной вариант
end
```

И три мелочи:

- в цикле прогулки `child:IsA("Part")` → `child:IsA("BasePart")`, а цель брать на высоте самого зверька:
  `target = Vector3.new(target.X, child.Position.Y, target.Z)`;
- `recipe.color` к мешу не применять (у него своя текстура);
- золотой вариант: `part.TextureID = ""` (и удалить `SurfaceAppearance`, если импортёр его создал), затем
  `Color = Color3.fromRGB(255, 205, 50)` и `Material = Foil` — модель станет цельно-золотой.
