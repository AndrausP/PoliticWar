--!nocheck
-- Ícones sólidos (opacos) das construções, feitos só com Frames: nítidos em qualquer tamanho
-- e sem depender de emoji. Tudo em escala, então o ícone acompanha o tamanho do pai.
local Icons = {}

local GRAY = Color3.fromRGB(176, 182, 194)
Icons.COLORS = { city = GRAY, factory = GRAY, defense = GRAY, missile = GRAY }
local LIGHT = Color3.fromRGB(232, 235, 240) -- janelas, fumaça e chama em cinza claro

local function box(parent, x, y, w, h, color, radius, z)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 0
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.ZIndex = z
	if radius then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(radius, 0)
		c.Parent = f
	end
	f.Parent = parent
	return f
end

-- cria o desenho de "kind" dentro de um Frame quadrado transparente que ocupa todo o pai
function Icons.make(kind, parent, zindex)
	local z = zindex or 1
	local root = Instance.new("Frame")
	root.Name = "Icon"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = z
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = root
	root.Parent = parent

	local col = Icons.COLORS[kind] or Color3.new(1, 1, 1)
	local dark = Color3.fromRGB(92, 98, 112)
	local win = LIGHT

	if kind == "city" then
		-- três prédios de alturas diferentes com janelas
		box(root, 0.08, 0.40, 0.26, 0.52, col, nil, z)
		box(root, 0.37, 0.12, 0.28, 0.80, col, nil, z)
		box(root, 0.68, 0.30, 0.24, 0.62, col, nil, z)
		box(root, 0.47, 0.03, 0.08, 0.10, col, nil, z) -- antena
		for i = 0, 2 do
			box(root, 0.43, 0.22 + i * 0.2, 0.06, 0.08, win, nil, z + 1)
			box(root, 0.53, 0.22 + i * 0.2, 0.06, 0.08, win, nil, z + 1)
		end
		box(root, 0.15, 0.52, 0.12, 0.08, win, nil, z + 1)
		box(root, 0.74, 0.42, 0.12, 0.08, win, nil, z + 1)
		box(root, 0.74, 0.62, 0.12, 0.08, win, nil, z + 1)
		box(root, 0.04, 0.90, 0.92, 0.06, dark, nil, z)
	elseif kind == "factory" then
		-- galpão com telhado em serra, chaminé e fumaça
		box(root, 0.08, 0.48, 0.84, 0.44, col, nil, z)
		for i = 0, 2 do
			local tooth = box(root, 0.10 + i * 0.22, 0.36, 0.18, 0.18, col, nil, z)
			tooth.Rotation = 45
		end
		box(root, 0.70, 0.14, 0.14, 0.40, col, nil, z) -- chaminé
		box(root, 0.66, 0.02, 0.14, 0.14, LIGHT, 1, z) -- fumaça
		box(root, 0.78, 0.0, 0.10, 0.10, LIGHT, 1, z)
		box(root, 0.18, 0.62, 0.14, 0.12, win, nil, z + 1)
		box(root, 0.43, 0.62, 0.14, 0.12, win, nil, z + 1)
		box(root, 0.68, 0.70, 0.14, 0.22, dark, nil, z + 1) -- porta
	elseif kind == "defense" then
		-- castelo: muralha com ameias, torres e portão
		box(root, 0.12, 0.40, 0.76, 0.52, col, nil, z)
		box(root, 0.04, 0.24, 0.24, 0.68, col, nil, z)
		box(root, 0.72, 0.24, 0.24, 0.68, col, nil, z)
		for _, x in { 0.04, 0.16, 0.72, 0.84 } do
			box(root, x, 0.12, 0.10, 0.14, col, nil, z)
		end
		for _, x in { 0.32, 0.46, 0.60 } do
			box(root, x, 0.30, 0.09, 0.12, col, nil, z)
		end
		box(root, 0.39, 0.62, 0.22, 0.30, dark, 0.5, z + 1) -- portão arredondado
		box(root, 0.39, 0.78, 0.22, 0.14, dark, nil, z + 1)
		box(root, 0.11, 0.40, 0.08, 0.12, dark, nil, z + 1)
		box(root, 0.81, 0.40, 0.08, 0.12, dark, nil, z + 1)
	elseif kind == "missile" then
		-- foguete em pé: corpo, ogiva, aletas e chama
		box(root, 0.38, 0.08, 0.24, 0.66, col, 0.5, z)
		box(root, 0.38, 0.30, 0.24, 0.44, col, nil, z)
		box(root, 0.44, 0.30, 0.12, 0.12, LIGHT, 1, z + 1) -- janela
		box(root, 0.22, 0.56, 0.16, 0.22, dark, 0.3, z)
		box(root, 0.62, 0.56, 0.16, 0.22, dark, 0.3, z)
		box(root, 0.40, 0.74, 0.20, 0.06, dark, nil, z)
		box(root, 0.41, 0.80, 0.18, 0.16, Color3.fromRGB(140, 146, 158), 1, z) -- chama
		box(root, 0.45, 0.82, 0.10, 0.10, LIGHT, 1, z + 1)
	elseif kind == "port" then
		-- âncora: argola, haste, travessa e braços curvos
		local ring = box(root, 0.40, 0.04, 0.20, 0.20, col, 1, z)
		box(ring, 0.3, 0.3, 0.4, 0.4, Color3.fromRGB(30, 35, 50), 1, z + 1)
		box(root, 0.45, 0.20, 0.10, 0.66, col, nil, z)
		box(root, 0.26, 0.32, 0.48, 0.09, col, 0.5, z)
		box(root, 0.12, 0.66, 0.76, 0.12, col, 0.5, z)
		box(root, 0.10, 0.52, 0.12, 0.24, col, 0.5, z)
		box(root, 0.78, 0.52, 0.12, 0.24, col, 0.5, z)
		box(root, 0.38, 0.78, 0.24, 0.12, col, 0.5, z)
	elseif kind == "silo" then
		-- lançador: base com rodas, trilho inclinado e míssil em cima
		box(root, 0.06, 0.70, 0.88, 0.14, dark, 0.3, z)
		for _, x in { 0.12, 0.42, 0.72 } do
			box(root, x, 0.80, 0.16, 0.16, col, 1, z + 1)
		end
		local rail = box(root, 0.20, 0.44, 0.66, 0.12, col, 0.3, z)
		rail.Rotation = -35
		local m = box(root, 0.30, 0.28, 0.56, 0.12, LIGHT, 0.5, z + 1)
		m.Rotation = -35
		box(root, 0.18, 0.56, 0.14, 0.16, col, nil, z)
	elseif kind == "aa" then
		-- antiaéreo: base, torre e dois canos apontando para o céu
		box(root, 0.10, 0.74, 0.80, 0.16, dark, 0.3, z)
		box(root, 0.26, 0.48, 0.48, 0.30, col, 0.4, z)
		local c1 = box(root, 0.30, 0.20, 0.08, 0.40, col, 0.3, z)
		c1.Rotation = 28
		local c2 = box(root, 0.50, 0.16, 0.08, 0.40, col, 0.3, z)
		c2.Rotation = 28
		box(root, 0.40, 0.56, 0.20, 0.10, LIGHT, 0.5, z + 1)
		box(root, 0.66, 0.06, 0.12, 0.12, LIGHT, 1, z)
	elseif kind == "train" then
		-- locomotiva: corpo, cabine, chaminé e rodas
		box(root, 0.06, 0.40, 0.62, 0.36, col, 0.15, z)
		box(root, 0.58, 0.20, 0.36, 0.56, col, 0.15, z)
		box(root, 0.66, 0.28, 0.20, 0.18, LIGHT, 0.2, z + 1)
		box(root, 0.16, 0.18, 0.14, 0.24, col, nil, z)
		box(root, 0.12, 0.12, 0.22, 0.08, dark, 0.3, z)
		box(root, 0.0, 0.62, 0.10, 0.14, dark, nil, z)
		for _, x in { 0.10, 0.36, 0.66 } do
			box(root, x, 0.70, 0.22, 0.22, dark, 1, z + 1)
		end
	end
	return root
end

return Icons
