--!nocheck
-- Personagens desenhados com Frames (sem imagens externas): rosto, cabelo, roupa e humor.
-- Portraits.make(parent, { seed, suit = Color3, hat = "cap"|"beret"|"none", mood = -1..1, military = bool })
local Portraits = {}

local SKINS = {
	Color3.fromRGB(255, 220, 185), Color3.fromRGB(240, 196, 150), Color3.fromRGB(205, 150, 105),
	Color3.fromRGB(160, 110, 75), Color3.fromRGB(110, 75, 50),
}
local HAIRS = {
	Color3.fromRGB(40, 30, 25), Color3.fromRGB(90, 60, 35), Color3.fromRGB(150, 110, 60),
	Color3.fromRGB(200, 200, 205), Color3.fromRGB(20, 20, 22), Color3.fromRGB(170, 70, 40),
}

local function box(parent, x, y, w, h, color, round, z)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.ZIndex = z
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(round, 0)
		c.Parent = f
	end
	f.Parent = parent
	return f
end

local function pick(list, seed, salt)
	local h = math.sin(seed * 12.9898 + salt * 78.233) * 43758.5453
	h -= math.floor(h)
	return list[math.floor(h * #list) + 1]
end

function Portraits.make(parent, o)
	local z = o.z or 5
	local seed = o.seed or 1
	local root = Instance.new("Frame")
	root.Name = "Portrait"
	root.BackgroundColor3 = (o.suit or Color3.fromRGB(80, 90, 120)):Lerp(Color3.new(1, 1, 1), 0.55)
	root.Size = UDim2.fromScale(1, 1)
	root.ClipsDescendants = true
	root.ZIndex = z
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(1, 0)
	rc.Parent = root
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.Parent = root
	root.Parent = parent

	local skin = pick(SKINS, seed, 1)
	local hair = pick(HAIRS, seed, 2)
	local suit = o.suit or Color3.fromRGB(60, 70, 100)
	local dark = Color3.fromRGB(30, 30, 35)

	-- corpo
	box(root, 0.12, 0.70, 0.76, 0.45, suit, 0.4, z)
	if o.military then
		box(root, 0.30, 0.78, 0.07, 0.06, Color3.fromRGB(240, 200, 60), 1, z + 1) -- medalhas
		box(root, 0.40, 0.78, 0.07, 0.06, Color3.fromRGB(220, 60, 60), 1, z + 1)
		box(root, 0.58, 0.74, 0.18, 0.04, Color3.fromRGB(240, 200, 60), nil, z + 1) -- dragona
	else
		box(root, 0.42, 0.70, 0.16, 0.16, Color3.fromRGB(245, 245, 245), nil, z + 1) -- camisa
		box(root, 0.47, 0.72, 0.06, 0.2, pick({ dark, Color3.fromRGB(170, 40, 40), Color3.fromRGB(40, 60, 140) }, seed, 3), 0.3, z + 2) -- gravata
	end
	-- pescoço e cabeça
	box(root, 0.43, 0.58, 0.14, 0.14, skin, nil, z)
	local head = box(root, 0.29, 0.22, 0.42, 0.42, skin, 1, z + 1)
	-- cabelo (3 estilos)
	local style = math.floor((math.sin(seed * 3.7) * 0.5 + 0.5) * 3)
	if o.hat == "none" or not o.hat then
		if style == 0 then
			box(root, 0.28, 0.17, 0.44, 0.16, hair, 0.5, z + 2)
		elseif style == 1 then
			box(root, 0.27, 0.18, 0.46, 0.13, hair, 0.5, z + 2)
			box(root, 0.27, 0.24, 0.08, 0.18, hair, 0.5, z + 2)
			box(root, 0.65, 0.24, 0.08, 0.18, hair, 0.5, z + 2)
		else
			box(root, 0.33, 0.19, 0.34, 0.08, hair, 0.5, z + 2) -- careca nos lados
		end
	end
	-- olhos e sobrancelhas (humor)
	local mood = math.clamp(o.mood or 0, -1, 1)
	box(head, 0.24, 0.42, 0.11, 0.11, dark, 1, z + 3)
	box(head, 0.65, 0.42, 0.11, 0.11, dark, 1, z + 3)
	local b1 = box(head, 0.18, 0.3, 0.22, 0.05, hair, 0.5, z + 3)
	local b2 = box(head, 0.6, 0.3, 0.22, 0.05, hair, 0.5, z + 3)
	b1.Rotation = mood < -0.2 and 18 or -6
	b2.Rotation = mood < -0.2 and -18 or 6
	-- boca: sorriso, reta ou bravo
	local mouthColor = Color3.fromRGB(120, 40, 40)
	box(head, 0.36, 0.72, 0.28, 0.06, mouthColor, 0.5, z + 3)
	if mood > 0.2 then
		local l = box(head, 0.28, 0.66, 0.12, 0.06, mouthColor, 0.5, z + 3)
		l.Rotation = 35
		local r = box(head, 0.6, 0.66, 0.12, 0.06, mouthColor, 0.5, z + 3)
		r.Rotation = -35
	elseif mood < -0.2 then
		local l = box(head, 0.28, 0.77, 0.12, 0.06, mouthColor, 0.5, z + 3)
		l.Rotation = -35
		local r = box(head, 0.6, 0.77, 0.12, 0.06, mouthColor, 0.5, z + 3)
		r.Rotation = 35
	end
	-- chapéus
	if o.hat == "cap" then
		box(root, 0.26, 0.12, 0.48, 0.16, suit:Lerp(dark, 0.3), 0.3, z + 3)
		box(root, 0.24, 0.25, 0.52, 0.05, dark, 0.5, z + 3)
		box(root, 0.45, 0.15, 0.1, 0.08, Color3.fromRGB(240, 200, 60), 1, z + 4)
	elseif o.hat == "beret" then
		local bt = box(root, 0.25, 0.13, 0.5, 0.15, suit:Lerp(dark, 0.2), 1, z + 3)
		bt.Rotation = -10
	end
	return root
end

return Portraits
