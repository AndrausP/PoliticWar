-- Cliente: mapa 2D (MapView), pan/zoom, HUD, rótulos das nações, barcos e entrada.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
-- progresso para a tela de carregamento (src/first/Loading.client.luau)
local function loadStep(text, pct)
	player:SetAttribute("LoadStep", text)
	player:SetAttribute("LoadPct", pct)
	task.wait() -- deixa a tela de carregamento desenhar
end
loadStep("Iniciando...", 0.15)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Sim = require(Shared:WaitForChild("Sim"))
local WorldMap = require(Shared:WaitForChild("WorldMap"))
local MapView = require(script.Parent:WaitForChild("MapView"))
local Icons = require(script.Parent:WaitForChild("Icons"))
local DetailView = require(script.Parent:WaitForChild("DetailView"))
local Panels = require(script.Parent:WaitForChild("Panels"))
local Portraits = require(script.Parent:WaitForChild("Portraits"))
local CivData = require(Shared:WaitForChild("CivData"))
local Civ = require(Shared:WaitForChild("Civ"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CivEv = Remotes:WaitForChild("Civ")
local RailsEv = Remotes:WaitForChild("Rails")
local Action = Remotes:WaitForChild("Action")
local StateEv = Remotes:WaitForChild("State")
local Notify = Remotes:WaitForChild("Notify")
local Effect = Remotes:WaitForChild("Effect")
local MapFull = Remotes:WaitForChild("MapFull")
local MapDelta = Remotes:WaitForChild("MapDelta")
local NationsEv = Remotes:WaitForChild("Nations")
local NationMenu = require(script.Parent:WaitForChild("NationMenu"))

local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable
camera.CFrame = CFrame.new(0, 10000, 0) * CFrame.Angles(math.rad(90), 0, 0) -- olha para o céu vazio: nada 3D para renderizar

for _, t in { Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu } do
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, t, false)
end

-- geometria do mapa (mesma da simulação do servidor)
loadStep("Lendo o mapa-múndi...", 0.25)
local geo = Sim.new(Config, 1, WorldMap)
Civ.computeBiomes(geo, WorldMap) -- terreno para a visão detalhada
loadStep("Preparando a imagem do mapa...", 0.45)
local W, H = geo.W, geo.H

---------------------------------------------------------------- estado
local state = nil
local me = nil
local meAt = 0
local nationsById = {}
local pctIndex = Config.DEFAULT_PCT_INDEX
local buildMode: string? = nil
local mapRound = 0
local civData = nil -- dados de civilização do jogador (remote Civ)

---------------------------------------------------------------- utilidades
local function fmt(n: number): string
	n = math.floor(n or 0)
	local a = math.abs(n)
	local function sig(v, suf)
		if v < 10 then
			return string.format("%.2f%s", v, suf)
		elseif v < 100 then
			return string.format("%.1f%s", v, suf)
		end
		return string.format("%d%s", math.floor(v), suf)
	end
	if a >= 1e6 then
		return sig(n / 1e6, "M")
	elseif a >= 1e3 then
		return sig(n / 1e3, "K")
	end
	return tostring(n)
end

local function pctText(v)
	if v < 0.1 then
		return string.format("%.2f%%", v)
	end
	return string.format("%.1f%%", v)
end

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in props do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function corner(p, r)
	new("UICorner", { CornerRadius = UDim.new(0, r or 10) }, p)
end

local DARK = Color3.fromRGB(22, 26, 38)
local DARK2 = Color3.fromRGB(36, 42, 58)
local TEXT = Color3.fromRGB(235, 238, 245)
local MUTED = Color3.fromRGB(140, 148, 170)
local GREEN = Color3.fromRGB(90, 220, 120)
local GOLD = Color3.fromRGB(245, 200, 70)
local RED = Color3.fromRGB(240, 90, 90)
local OCEAN = Color3.fromRGB(MapView.DEEP[1], MapView.DEEP[2], MapView.DEEP[3])

local function panel(props, parent)
	local f = new("Frame", props, parent)
	f.BackgroundColor3 = DARK
	f.BackgroundTransparency = 0.06
	f.BorderSizePixel = 0
	f.Active = true -- não deixa o clique atravessar para o mapa
	corner(f, 14)
	new("UIStroke", { Color = Color3.fromRGB(70, 80, 105), Transparency = 0.5, Thickness = 1 }, f)
	return f
end

local function label(props, parent)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = TEXT,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	for k, v in props do
		l[k] = v
	end
	return l
end

---------------------------------------------------------------- mapa (GUI)
local playerGui = player:WaitForChild("PlayerGui")
local mapGui = new("ScreenGui", { Name = "Map", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 0, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
new("Frame", { Name = "Ocean", Size = UDim2.fromScale(1, 1), BackgroundColor3 = OCEAN, BorderSizePixel = 0 }, mapGui)
local mapFrame = new("Frame", { Name = "World", BackgroundColor3 = OCEAN, BorderSizePixel = 0 }, mapGui)
local view = MapView.new(geo, Config, mapFrame)
-- cópias à esquerda e à direita: o mundo dá a volta sem corte
local ghosts = {}
for i, side in { -1, 1 } do
	local g = new("Frame", { Name = "WorldCopy" .. i, BackgroundColor3 = OCEAN, BorderSizePixel = 0 }, mapGui)
	view:attach(g)
	ghosts[i] = { frame = g, side = side }
end
local overlay = new("Frame", { Name = "Overlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5 }, mapFrame)
local labelLayer = new("Frame", { Name = "Labels", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 8 }, mapFrame)

local zoom = 4 -- pixels de tela por célula
local pan = Vector2.zero -- canto superior esquerdo do mapa na tela

local function minZoom()
	return math.max(camera.ViewportSize.X, 200) / W -- no máximo, o mundo inteiro na largura da tela
end

local function clampPan()
	local v = camera.ViewportSize
	local mw, mh = W * zoom, H * zoom
	-- horizontal: dá a volta; mantém o centro da tela dentro da cópia do meio
	local px = pan.X
	while v.X / 2 - px < 0 do
		px -= mw
	end
	while v.X / 2 - px > mw do
		px += mw
	end
	-- vertical: sem sair do mapa (o oceano em volta tem a mesma cor do fundo)
	local free = v.Y - mh
	local py = if free >= 0 then free / 2 else math.clamp(pan.Y, free, 0)
	pan = Vector2.new(px, py)
end

local labelsDirty = true
local function applyView()
	clampPan()
	local size = UDim2.fromOffset(W * zoom, H * zoom)
	mapFrame.Size = size
	mapFrame.Position = UDim2.fromOffset(math.floor(pan.X), math.floor(pan.Y))
	for _, g in ghosts do
		g.frame.Size = size
		g.frame.Position = UDim2.fromOffset(math.floor(pan.X + g.side * W * zoom), math.floor(pan.Y))
	end
end

local function fitWorld()
	local v = camera.ViewportSize
	zoom = minZoom()
	pan = Vector2.new((v.X - W * zoom) / 2, (v.Y - H * zoom) / 2)
	labelsDirty = true
	applyView()
end
fitWorld()

local function zoomAt(m: Vector2, factor)
	local tile = (m - pan) / zoom
	local z = math.clamp(zoom * factor, minZoom(), Config.MAX_ZOOM)
	if z == zoom then
		return
	end
	zoom = z
	pan = m - tile * zoom
	labelsDirty = true
	applyView()
end

local function screenToCell(m: Vector2)
	local p = (m - pan) / zoom
	local x, y = math.floor(p.X) % W, math.floor(p.Y)
	if y < 0 or y >= H then
		return nil
	end
	return x, y
end

---------------------------------------------------------------- HUD
local gui = new("ScreenGui", { Name = "HUD", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
local uiScale = new("UIScale", {}, gui)
local function rescale()
	local v = camera.ViewportSize
	uiScale.Scale = math.clamp(math.min(v.X / 1280, v.Y / 720), 0.55, 1.2)
end
rescale()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	rescale()
	-- ao entrar, a tela pode começar com tamanho errado: se o mapa ficou pequeno demais, reencaixa
	if zoom < minZoom() * 0.999 or zoom > Config.MAX_ZOOM then
		fitWorld()
	else
		applyView()
	end
end)

-- topo: fase/tempo + controle mundial
local top = panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(600, 70) }, gui)
local phaseLbl = label({ Position = UDim2.fromOffset(18, 10), Size = UDim2.fromOffset(150, 16), TextSize = 13, TextColor3 = GREEN, Text = "" }, top)
local timerLbl = label({ Position = UDim2.fromOffset(18, 28), Size = UDim2.fromOffset(150, 30), TextSize = 28, Font = Enum.Font.GothamBlack, Text = "0:00", TextColor3 = GREEN }, top)
new("Frame", { Position = UDim2.fromOffset(178, 12), Size = UDim2.fromOffset(1, 46), BackgroundColor3 = DARK2, BorderSizePixel = 0 }, top)
label({ Position = UDim2.fromOffset(194, 8), Size = UDim2.fromOffset(200, 16), TextSize = 12, TextColor3 = MUTED, Text = "🌐 CONTROLE MUNDIAL" }, top)
label({ Position = UDim2.fromOffset(394, 8), Size = UDim2.fromOffset(190, 16), TextSize = 12, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Right, Text = "META " .. math.floor(Config.WIN_SHARE * 100) .. "%" }, top)
local barBg = new("Frame", { Position = UDim2.fromOffset(194, 30), Size = UDim2.fromOffset(390, 6), BackgroundColor3 = DARK2, BorderSizePixel = 0 }, top)
corner(barBg, 3)
local leaderFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(80, 120, 230), BackgroundTransparency = 0.45, BorderSizePixel = 0 }, barBg)
corner(leaderFill, 3)
local myFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = GOLD, BorderSizePixel = 0 }, barBg)
corner(myFill, 3)
new("Frame", { Position = UDim2.new(Config.WIN_SHARE, -1, 0, -4), Size = UDim2.new(0, 2, 1, 8), BackgroundColor3 = GOLD, BorderSizePixel = 0 }, barBg)
local youLbl = label({ Position = UDim2.fromOffset(194, 44), Size = UDim2.fromOffset(180, 16), TextSize = 13, Text = "Você 0%" }, top)
local leaderLbl = label({ Position = UDim2.fromOffset(384, 44), Size = UDim2.fromOffset(200, 16), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right, Text = "", TextTruncate = Enum.TextTruncate.AtEnd }, top)

-- canto superior direito: ranking + ver mundo
local rankBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 10),
	Size = UDim2.fromOffset(170, 40),
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.06,
	TextColor3 = TEXT,
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	Text = "📊 #- · 0%",
}, gui)
corner(rankBtn, 20)
local worldBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -190, 0, 10),
	Size = UDim2.fromOffset(40, 40),
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.06,
	TextColor3 = TEXT,
	Font = Enum.Font.GothamBold,
	TextSize = 20,
	Text = "🌍",
}, gui)
corner(worldBtn, 20)
worldBtn.Activated:Connect(fitWorld)
local board = panel({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -324, 0, 58), Size = UDim2.fromOffset(300, 300), Visible = false }, gui)
label({ Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 20), Text = "🏆 RANKING", TextColor3 = GOLD }, board)
local boardRows = {}
for i = 1, 12 do
	boardRows[i] = label({ Position = UDim2.fromOffset(14, 8 + i * 22), Size = UDim2.new(1, -28, 0, 20), TextSize = 13, Text = "", RichText = true, TextTruncate = Enum.TextTruncate.AtEnd }, board)
end
rankBtn.Activated:Connect(function()
	board.Visible = not board.Visible
end)

-- HUD lateral em módulos (cartões empilhados à direita)
local bottom = new("Frame", { Name = "SideHud", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 58), Size = UDim2.fromOffset(300, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, gui)
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, bottom)
local function card(h, order, title)
	local c = panel({ Size = UDim2.fromOffset(300, h), LayoutOrder = order }, bottom)
	if title then
		label({ Position = UDim2.fromOffset(12, 6), Size = UDim2.fromOffset(150, 16), TextSize = 11, TextColor3 = MUTED, Text = title }, c)
	end
	return c
end

-- nação
local sName = card(112, 1)
local mySwatch = new("Frame", { Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = GOLD, BorderSizePixel = 0 }, sName)
corner(mySwatch, 4)
local myNameLbl = label({ Position = UDim2.fromOffset(32, 8), Size = UDim2.fromOffset(160, 22), TextSize = 17, Font = Enum.Font.GothamBlack, Text = player.DisplayName, TextTruncate = Enum.TextTruncate.AtEnd }, sName)
local govBadge = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 9), Size = UDim2.fromOffset(98, 20), TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0, BackgroundColor3 = DARK2, Text = "" }, sName)
corner(govBadge, 10)
local myShareLbl = label({ Position = UDim2.fromOffset(12, 32), Size = UDim2.fromOffset(276, 16), TextSize = 12, TextColor3 = MUTED, Font = Enum.Font.GothamMedium, Text = "0% do mundo" }, sName)
local happyLbl = label({ Position = UDim2.fromOffset(12, 52), Size = UDim2.fromOffset(276, 16), TextSize = 12, Text = "Felicidade" }, sName)
local happyBarBg = new("Frame", { Position = UDim2.fromOffset(12, 72), Size = UDim2.fromOffset(276, 6), BackgroundColor3 = DARK2, BorderSizePixel = 0 }, sName)
corner(happyBarBg, 3)
local happyBar = new("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = GREEN, BorderSizePixel = 0 }, happyBarBg)
corner(happyBar, 3)
local infoLbl = label({ Position = UDim2.fromOffset(12, 86), Size = UDim2.fromOffset(276, 16), TextSize = 12, TextColor3 = MUTED, Font = Enum.Font.GothamMedium, Text = "" }, sName)

-- tropas
local sTroops = card(66, 2, "TROPAS")
local troopRateLbl = label({ Position = UDim2.fromOffset(150, 6), Size = UDim2.fromOffset(138, 16), TextSize = 12, TextColor3 = GREEN, TextXAlignment = Enum.TextXAlignment.Right, Text = "+0/s" }, sTroops)
local troopsLbl = label({ Position = UDim2.fromOffset(12, 24), Size = UDim2.fromOffset(276, 24), TextSize = 21, Font = Enum.Font.GothamBlack, Text = "0", RichText = true }, sTroops)
local troopBarBg = new("Frame", { Position = UDim2.fromOffset(12, 52), Size = UDim2.fromOffset(276, 4), BackgroundColor3 = DARK2, BorderSizePixel = 0 }, sTroops)
corner(troopBarBg, 2)
local troopBar = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = GREEN, BorderSizePixel = 0 }, troopBarBg)
corner(troopBar, 2)

-- ataque
local sAtk = card(112, 3, "EXÉRCITOS")
local legacy = new("Frame", { Visible = false, BackgroundTransparency = 1 }, sAtk) -- antigo ataque rápido (desativado)
local atkPctLbl = label({ Position = UDim2.fromOffset(150, 6), Size = UDim2.fromOffset(138, 16), TextSize = 12, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Right, Text = "" }, legacy)
local pctRow = new("Frame", { Position = UDim2.fromOffset(12, 24), Size = UDim2.fromOffset(276, 26), BackgroundColor3 = DARK2, BorderSizePixel = 0 }, legacy)
corner(pctRow, 8)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center }, pctRow)
local pctButtons = {}
local sendLbl = label({ Position = UDim2.fromOffset(12, 52), Size = UDim2.fromOffset(276, 16), TextSize = 12, TextColor3 = MUTED, Font = Enum.Font.GothamMedium, Text = "" }, legacy)

local armyRows = new("Frame", { Position = UDim2.fromOffset(12, 26), Size = UDim2.fromOffset(276, 80), BackgroundTransparency = 1 }, sAtk)
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, armyRows)
local armyFormBtn = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 4), Size = UDim2.fromOffset(84, 18), BackgroundColor3 = DARK2, BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = GOLD, Text = "+ Formar / ver" }, sAtk)
corner(armyFormBtn, 6)

-- economia: ouro + recursos
local sGold = card(138, 4, "ECONOMIA")
local goldRateLbl = label({ Position = UDim2.fromOffset(150, 6), Size = UDim2.fromOffset(138, 16), TextSize = 12, TextColor3 = GREEN, TextXAlignment = Enum.TextXAlignment.Right, Text = "+0/s" }, sGold)
local goldLbl = label({ Position = UDim2.fromOffset(12, 22), Size = UDim2.fromOffset(276, 24), TextSize = 21, Font = Enum.Font.GothamBlack, TextColor3 = GOLD, Text = "0" }, sGold)
local resRows = {}
for i, r in CivData.RESOURCES do
	local y = 50 + (i - 1) * 16
	local dot = new("Frame", { Position = UDim2.fromOffset(12, y + 4), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = CivData.RES[r].color, BorderSizePixel = 0 }, sGold)
	corner(dot, 4)
	local nm = label({ Position = UDim2.fromOffset(26, y), Size = UDim2.fromOffset(110, 16), TextSize = 12, Font = Enum.Font.GothamMedium, Text = CivData.RES[r].name }, sGold)
	local st = label({ Position = UDim2.fromOffset(130, y), Size = UDim2.fromOffset(70, 16), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Text = "0" }, sGold)
	local net = label({ Position = UDim2.fromOffset(208, y), Size = UDim2.fromOffset(80, 16), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Text = "" }, sGold)
	resRows[r] = { name = nm, stock = st, net = net }
end

-- construções
local sBuildCard = card(136, 5, "CONSTRUÇÕES (1-7)")
local sBuild = new("Frame", { Position = UDim2.fromOffset(12, 24), Size = UDim2.fromOffset(276, 104), BackgroundTransparency = 1 }, sBuildCard)
new("UIGridLayout", { CellSize = UDim2.fromOffset(64, 50), CellPadding = UDim2.fromOffset(6, 4), SortOrder = Enum.SortOrder.LayoutOrder }, sBuild)
local buildButtons = {}

-- menu das janelas
local sMenu = card(84, 6)
local menuGrid = new("Frame", { Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(280, 70), BackgroundTransparency = 1 }, sMenu)
new("UIGridLayout", { CellSize = UDim2.fromOffset(88, 32), CellPadding = UDim2.fromOffset(4, 4), SortOrder = Enum.SortOrder.LayoutOrder }, menuGrid)
local menuButtons = {}
for i, m in { { "armies", "⚔ Exércitos" }, { "diplomacy", "🤝 Diplomacia" }, { "skills", "🧬 Pesquisa" }, { "market", "📈 Mercado" }, { "politics", "🏛 Política" } } do
	local b = new("TextButton", { BackgroundColor3 = DARK2, BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = TEXT, Text = m[2], LayoutOrder = i }, menuGrid)
	corner(b, 8)
	menuButtons[m[1]] = b
end


local hint = label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -108), Size = UDim2.fromOffset(900, 22), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 15, TextStrokeTransparency = 0.4, Text = "", RichText = true }, gui)
local banner = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96), Size = UDim2.fromOffset(900, 44), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 34, Font = Enum.Font.GothamBlack, TextStrokeTransparency = 0.2, Text = "" }, gui)
local subBanner = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 140), Size = UDim2.fromOffset(900, 24), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 18, TextStrokeTransparency = 0.3, Text = "" }, gui)

-- tooltip
local tip = panel({ Size = UDim2.fromOffset(270, 120), Visible = false, ZIndex = 20 }, gui)
tip.Active = false
local tipSwatch = new("Frame", { Position = UDim2.fromOffset(14, 16), Size = UDim2.fromOffset(12, 12), BorderSizePixel = 0, ZIndex = 21 }, tip)
corner(tipSwatch, 3)
local tipName = label({ Position = UDim2.fromOffset(32, 10), Size = UDim2.fromOffset(160, 22), TextSize = 16, ZIndex = 21, TextTruncate = Enum.TextTruncate.AtEnd }, tip)
local tipTag = label({ Position = UDim2.fromOffset(190, 12), Size = UDim2.fromOffset(66, 18), TextSize = 11, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0, BackgroundColor3 = DARK2, ZIndex = 21 }, tip)
corner(tipTag, 9)
local tipBody = label({ Position = UDim2.fromOffset(14, 36), Size = UDim2.fromOffset(242, 50), TextSize = 13, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(200, 205, 220), TextYAlignment = Enum.TextYAlignment.Top, RichText = true, ZIndex = 21 }, tip)
local tipHint = label({ Position = UDim2.fromOffset(14, 92), Size = UDim2.fromOffset(242, 18), TextSize = 12, Font = Enum.Font.GothamMedium, TextColor3 = MUTED, ZIndex = 21 }, tip)

-- notificações
local toastHolder = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 176), Size = UDim2.fromOffset(600, 200), BackgroundTransparency = 1 }, gui)
new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, toastHolder)
local toastN = 0
local function toast(text, kind)
	toastN += 1
	local color = ({ error = RED, kill = Color3.fromRGB(255, 150, 90), win = GOLD, war = RED, ok = GREEN, missile = Color3.fromRGB(255, 140, 40) })[kind] or TEXT
	local f = panel({ Size = UDim2.fromOffset(10, 34), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = toastN }, toastHolder)
	f.Active = false
	new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, f)
	local l = label({ Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, Text = text, TextColor3 = color, TextSize = 15 }, f)
	local frames = {}
	for _, k in toastHolder:GetChildren() do
		if k:IsA("Frame") then
			frames[#frames + 1] = k
		end
	end
	if #frames > 4 then
		table.sort(frames, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		frames[1]:Destroy()
	end
	task.delay(4, function()
		if f.Parent then
			TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			task.wait(0.45)
			f:Destroy()
		end
	end)
end
Notify.OnClientEvent:Connect(toast)

---------------------------------------------------------------- botões
local function refreshPct()
	for i, b in pctButtons do
		local sel = i == pctIndex
		b.BackgroundColor3 = sel and GOLD or DARK2
		b.BackgroundTransparency = sel and 0 or 1
		b.TextColor3 = sel and Color3.fromRGB(30, 30, 30) or TEXT
	end
	atkPctLbl.Text = math.floor(Config.ATTACK_PCTS[pctIndex] * 100 + 0.5) .. "%"
end
for i, p in Config.ATTACK_PCTS do
	local b = new("TextButton", { Size = UDim2.fromOffset(50, 22), Font = Enum.Font.GothamBold, TextSize = 13, Text = math.floor(p * 100 + 0.5) .. "%", AutoButtonColor = false, BorderSizePixel = 0 }, pctRow)
	corner(b, 6)
	b.Activated:Connect(function()
		pctIndex = i
		refreshPct()
	end)
	pctButtons[i] = b
end
refreshPct()

local function setBuildMode(kind)
	if buildMode == kind then
		kind = nil
	end
	if kind == "missile" and me and not me.silo then
		toast("Construa um Lançador primeiro (tecla 5)", "error")
		kind = nil
	end
	buildMode = kind
	for k, b in buildButtons do
		b.stroke.Color = (k == buildMode) and GOLD or Color3.fromRGB(70, 80, 105)
		b.stroke.Thickness = (k == buildMode) and 2 or 1
	end
end

for i, kind in Config.BUILD_ORDER do
	local def = Config.BUILDINGS[kind]
	local b = new("TextButton", { BackgroundColor3 = DARK2, Text = "", BorderSizePixel = 0, LayoutOrder = i }, sBuild)
	corner(b, 10)
	local stroke = new("UIStroke", { Color = Color3.fromRGB(70, 80, 105), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	label({ Position = UDim2.fromOffset(6, 3), Size = UDim2.fromOffset(20, 12), TextSize = 10, TextColor3 = MUTED, Text = tostring(i) }, b)
	local iconHolder = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(26, 26) }, b)
	Icons.make(kind, iconHolder, 2)
	local cost = label({ Position = UDim2.fromOffset(0, 31), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 12, TextColor3 = RED, Text = fmt(def.cost) }, b)
	b.Activated:Connect(function()
		setBuildMode(kind)
	end)
	buildButtons[kind] = { button = b, cost = cost, stroke = stroke, def = def }
end

---------------------------------------------------------------- rótulos das nações
local labels = {}

local function makeLabel(n)
	local root = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), ZIndex = 8 }, labelLayer)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, root)
	local row = new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), LayoutOrder = 1, ZIndex = 8 }, root)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	local isPlayer = (n.u or 0) > 0
	local avatar
	if isPlayer then
		avatar = new("ImageLabel", { BackgroundColor3 = DARK, Image = "rbxthumb://type=AvatarHeadShot&id=" .. n.u .. "&w=150&h=150", LayoutOrder = 1, ZIndex = 8 }, row)
		corner(avatar, 999)
		new("UIStroke", { Color = n.c, Thickness = 2 }, avatar)
	end
	local textColor = isPlayer and Color3.fromRGB(24, 24, 28) or n.c:Lerp(Color3.new(0, 0, 0), 0.35)
	local strokeColor = isPlayer and n.c:Lerp(Color3.new(1, 1, 1), 0.2) or Color3.fromRGB(250, 248, 240)
	local nameL = new("TextLabel", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), Font = Enum.Font.GothamBlack, Text = n.n, TextColor3 = textColor, LayoutOrder = 2, ZIndex = 8 }, row)
	local nameStroke = new("UIStroke", { Color = strokeColor, Thickness = 2, LineJoinMode = Enum.LineJoinMode.Round }, nameL)
	local troopL = new("TextLabel", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), Font = Enum.Font.GothamBlack, Text = "", TextColor3 = textColor, LayoutOrder = 2, ZIndex = 8 }, root)
	local troopStroke = new("UIStroke", { Color = strokeColor, Thickness = 2, LineJoinMode = Enum.LineJoinMode.Round }, troopL)
	return { root = root, avatar = avatar, nameL = nameL, troopL = troopL, nameStroke = nameStroke, troopStroke = troopStroke, name = n.n .. "|" .. (n.u or 0), isPlayer = isPlayer }
end

local function sizeLabel(L, tiles)
	local fs = math.floor(math.clamp(math.sqrt(tiles) * zoom * 0.3, 0, 70))
	if fs < 9 then
		L.root.Visible = false
		return
	end
	L.root.Visible = true
	L.nameL.TextSize = fs
	L.troopL.TextSize = math.max(8, math.floor(fs * 0.72))
	local th = math.clamp(fs / 12, 1.2, 4)
	L.nameStroke.Thickness = th
	L.troopStroke.Thickness = th
	if L.avatar then
		L.avatar.Size = UDim2.fromOffset(fs * 1.25, fs * 1.25)
	end
end

local function updateLabels()
	local seen = {}
	for _, n in state.nations do
		if n.ax >= 0 then
			seen[n.i] = true
			local L = labels[n.i]
			if L and L.name ~= n.n .. "|" .. (n.u or 0) then
				L.root:Destroy()
				L = nil
			end
			if not L then
				L = makeLabel(n)
				labels[n.i] = L
			end
			L.tiles = n.t
			L.root.Position = UDim2.fromScale((n.ax + 0.5) / W, (n.ay + 0.5) / H)
			L.troopL.Text = fmt(n.tr)
			sizeLabel(L, n.t)
		end
	end
	for id, L in labels do
		if not seen[id] then
			L.root:Destroy()
			labels[id] = nil
		end
	end
end

local function resizeAllLabels()
	for _, L in labels do
		sizeLabel(L, L.tiles or 1)
	end
end

local function clearLabels()
	for id, L in labels do
		L.root:Destroy()
		labels[id] = nil
	end
end

---------------------------------------------------------------- construções e barcos (sobre o mapa)
local buildingIcons = {}
local ring -- definido mais abaixo (efeito de anel no mapa)
local boatIcons = {}

local function iconSize()
	return math.clamp(zoom * 2.4, 10, 44)
end

local function updateBuildings()
	local seen = {}
	for _, b in state.buildings or {} do
		local t, kind, owner, prog = b[1], b[2], b[3], b[4] or 1
		local key = t .. kind
		seen[key] = true
		local ic = buildingIcons[key]
		if not ic then
			local x, y = geo:xy(t)
			ic = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale((x + 0.5) / W, (y + 0.5) / H),
				BackgroundColor3 = DARK,
				BackgroundTransparency = 0,
				ZIndex = 6,
			}, overlay)
			corner(ic, 6)
			new("UIStroke", { Thickness = 2 }, ic)
			new("UIPadding", { PaddingLeft = UDim.new(0.12, 0), PaddingRight = UDim.new(0.12, 0), PaddingTop = UDim.new(0.12, 0), PaddingBottom = UDim.new(0.12, 0) }, ic)
			Icons.make(kind, ic, 7)
			buildingIcons[key] = ic
		end
		local n = nationsById[owner]
		ic:FindFirstChildOfClass("UIStroke").Color = n and n.c or TEXT
		-- em obra: ícone apagado + barra de progresso
		local pb = ic:FindFirstChild("Progress")
		if prog < 1 then
			if not pb then
				pb = new("Frame", { Name = "Progress", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 3), Size = UDim2.new(1.1, 0, 0, 4), BackgroundColor3 = DARK, BorderSizePixel = 0, ZIndex = 8 }, ic)
				new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 9 }, pb)
			end
			TweenService:Create(pb.Fill, TweenInfo.new(0.4), { Size = UDim2.fromScale(prog, 1) }):Play()
			ic.BackgroundTransparency = 0.5
		elseif pb then
			pb:Destroy()
			ic.BackgroundTransparency = 0
			ring(geo:xy(t), (select(2, geo:xy(t))), GOLD, 2, 0.5)
		end
		local s = iconSize()
		ic.Size = UDim2.fromOffset(s, s)
	end
	for key, ic in buildingIcons do
		if not seen[key] then
			ic:Destroy()
			buildingIcons[key] = nil
		end
	end
end

local function updateBoats()
	local seen = {}
	for _, b in state.boats or {} do
		local x, y, from, tr, id = b[1], b[2], b[3], b[4], b[5]
		seen[id] = true
		local pos = UDim2.fromScale((x + 0.5) / W, (y + 0.5) / H)
		local ic = boatIcons[id]
		if not ic then
			ic = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Position = pos, Text = "⛵", TextScaled = true, ZIndex = 7 }, overlay)
			local n = nationsById[from]
			new("TextLabel", {
				Name = "Troops",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.9),
				Size = UDim2.fromScale(2.4, 0.55),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack,
				TextScaled = true,
				TextColor3 = Color3.new(1, 1, 1),
				TextStrokeTransparency = 0,
				TextStrokeColor3 = n and n.c:Lerp(Color3.new(0, 0, 0), 0.4) or DARK,
				Text = fmt(tr),
				ZIndex = 7,
			}, ic)
			boatIcons[id] = ic
		else
			TweenService:Create(ic, TweenInfo.new(0.4, Enum.EasingStyle.Linear), { Position = pos }):Play()
			ic.Troops.Text = fmt(tr)
		end
		local s = iconSize()
		ic.Size = UDim2.fromOffset(s, s)
	end
	for id, ic in boatIcons do
		if not seen[id] then
			ic:Destroy()
			boatIcons[id] = nil
		end
	end
end

-- tropas na linha de ataque
local attackTags = {}
local function updateAttacks()
	local seen = {}
	for _, a in state.attacks or {} do
		local id, x, y, tr, from = a[1], a[2], a[3], a[4], a[5]
		seen[id] = true
		local pos = UDim2.fromScale((x + 0.5) / W, (y + 0.5) / H)
		local tag = attackTags[id]
		local n = nationsById[from]
		local mine = me and from == me.id
		if not tag then
			tag = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = pos,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 18),
				BackgroundColor3 = DARK,
				BackgroundTransparency = 0.1,
				ZIndex = 9,
			}, overlay)
			corner(tag, 9)
			new("UIStroke", { Name = "Stroke", Thickness = 2, Color = n and n.c or TEXT }, tag)
			new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, tag)
			new("TextLabel", {
				Name = "Txt",
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromScale(0, 1),
				Font = Enum.Font.GothamBlack,
				TextColor3 = TEXT,
				ZIndex = 9,
			}, tag)
			attackTags[id] = tag
		else
			TweenService:Create(tag, TweenInfo.new(0.4, Enum.EasingStyle.Linear), { Position = pos }):Play()
		end
		local h = math.floor(math.clamp(zoom * (mine and 3.2 or 2.4), 12, mine and 26 or 20))
		tag.Size = UDim2.fromOffset(0, h)
		tag.Txt.TextSize = h - 5
		tag.Txt.Text = "⚔ " .. fmt(tr)
		tag.Txt.TextColor3 = mine and GOLD or TEXT
		tag.Visible = mine or zoom >= 2.2
	end
	for id, tag in attackTags do
		if not seen[id] then
			tag:Destroy()
			attackTags[id] = nil
		end
	end
end

-- trens andando entre as paradas
local trainIcons = {}
local function updateTrains()
	local seen = {}
	local s = math.clamp(zoom * 1.8, 8, 30)
	for _, tr in state.trains or {} do
		local id, x, y, owner = tr[1], tr[2], tr[3], tr[4]
		seen[id] = true
		local pos = UDim2.fromScale((x + 0.5) / W, (y + 0.5) / H)
		local ic = trainIcons[id]
		if not ic then
			ic = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, BackgroundTransparency = 1, ZIndex = 7 }, overlay)
			if tr[5] == 2 then
				new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "⛵", TextScaled = true, ZIndex = 7 }, ic)
				ic:SetAttribute("Bob", true)
			else
				Icons.make("train", ic, 7)
			end
			trainIcons[id] = ic
		else
			TweenService:Create(ic, TweenInfo.new(0.4, Enum.EasingStyle.Linear), { Position = pos }):Play()
		end
		ic.Size = UDim2.fromOffset(s, s)
		ic.Visible = zoom >= 1.6 or (me and owner == me.id)
	end
	for id, ic in trainIcons do
		if not seen[id] then
			ic:Destroy()
			trainIcons[id] = nil
		end
	end
end

-- mísseis no ar: trajetória, alvo e o míssil andando (animado a cada quadro)
local flightGfx = {}
local flightAt = 0
local function updateFlights()
	flightAt = os.clock()
	local seen = {}
	for _, f in state.flights or {} do
		local id = f[1]
		seen[id] = true
		local g = flightGfx[id]
		if not g then
			g = { data = f }
			g.line = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = RED, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 9 }, overlay)
			g.target = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Position = UDim2.fromScale((f[4] + 0.5) / W, (f[5] + 0.5) / H), ZIndex = 9 }, overlay)
			corner(g.target, 999)
			new("UIStroke", { Color = RED, Thickness = 2 }, g.target)
			g.icon = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 10 }, overlay)
			Icons.make("missile", g.icon, 10)
			flightGfx[id] = g
		end
		g.data = f
	end
	for id, g in flightGfx do
		if not seen[id] then
			g.line:Destroy()
			g.target:Destroy()
			g.icon:Destroy()
			flightGfx[id] = nil
		end
	end
end

local function animateFlights()
	local since = os.clock() - flightAt
	for _, g in flightGfx do
		local _, sx, sy, tx, ty, t, dur = table.unpack(g.data)
		local dx = tx - sx
		if math.abs(dx) > W / 2 then
			dx -= math.sign(dx) * W
		end
		local dy = ty - sy
		local k = math.clamp((t + since) / dur, 0, 1)
		-- em pixels dentro do mapa
		local ax, ay = (sx + 0.5) * zoom, (sy + 0.5) * zoom
		local bx, by = ax + dx * zoom, ay + dy * zoom
		local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
		g.line.Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2)
		g.line.Size = UDim2.fromOffset(len, 2)
		g.line.Rotation = math.deg(math.atan2(by - ay, bx - ax))
		local r = math.clamp(Config.BUILDINGS.missile.radius * 2 * zoom, 12, 400)
		g.target.Size = UDim2.fromOffset(r, r)
		local s = math.clamp(zoom * 3, 14, 40)
		g.icon.Size = UDim2.fromOffset(s, s)
		g.icon.Position = UDim2.fromOffset(ax + (bx - ax) * k, ay + (by - ay) * k)
		g.icon.Rotation = math.deg(math.atan2(by - ay, bx - ax)) + 90
	end
end

-- "+ouro" subindo da parada do trem
local function goldPopup(x, y, amount)
	local l = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale((x + 0.5) / W, (y + 0.5) / H),
		Size = UDim2.fromOffset(80, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = math.clamp(zoom * 3, 12, 22),
		TextColor3 = GOLD,
		TextStrokeTransparency = 0.2,
		Text = "+" .. fmt(amount),
		ZIndex = 11,
	}, overlay)
	TweenService:Create(l, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new((x + 0.5) / W, 0, (y + 0.5) / H, -40),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1.5, function()
		l:Destroy()
	end)
end

local function resizeIcons()
	local s = iconSize()
	for _, ic in buildingIcons do
		ic.Size = UDim2.fromOffset(s, s)
	end
	for _, ic in boatIcons do
		ic.Size = UDim2.fromOffset(s, s)
	end
end

function ring(x, y, color, radiusTiles, duration)
	local c = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale((x + 0.5) / W, (y + 0.5) / H),
		Size = UDim2.fromScale(0, 0),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.25,
		ZIndex = 9,
	}, overlay)
	corner(c, 999)
	TweenService:Create(c, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(radiusTiles * 2 / W, radiusTiles * 2 / H),
		BackgroundTransparency = 1,
	}):Play()
	task.delay(duration + 0.05, function()
		c:Destroy()
	end)
end

---------------------------------------------------------------- rede do mapa
local gotMap, gotState, ready = false, false, false
local function checkReady()
	if ready or not (gotMap and gotState) then
		return
	end
	ready = true
	fitWorld()
	labelsDirty = true
	task.defer(function()
		fitWorld()
		player:SetAttribute("LoadPct", 1)
		player:SetAttribute("MapReady", true)
	end)
end

MapFull.OnClientEvent:Connect(function(round, buf)
	mapRound = round
	if not ready then
		loadStep("Desenhando o mundo...", 0.85)
	end
	view:loadOwners(buf)
	gotMap = true
	checkReady()
end)

MapDelta.OnClientEvent:Connect(function(round, buf)
	if round ~= mapRound then
		return
	end
	local n = buffer.len(buf) // 5
	for i = 0, n - 1 do
		view:setOwner(buffer.readu32(buf, i * 5) + 1, buffer.readu8(buf, i * 5 + 4))
	end
end)

---------------------------------------------------------------- ações
local menu -- NationMenu (criado mais abaixo)
local armyMode = nil -- { id, name } quando o jogador escolhe o alvo de um exército
local function act(m: Vector2)
	if not state then
		return
	end
	local x, y = screenToCell(m)
	if not x then
		return
	end
	if menu and menu:isVisible() then
		local o = view.owner[geo:idx(x, y)]
		if o and o ~= 0 then
			menu:select(o)
			ring(x, y, GOLD, 4, 0.5)
		end
		return
	end
	if not me or state.phase ~= "play" or not me.alive then
		return
	end
	if armyMode then
		Action:FireServer("civ", 0, 0, { op = "army_send", army = armyMode.id, x = x, y = y })
		ring(x, y, GOLD, 4, 0.5)
		armyMode = nil
		return
	end
	if false then
		return
	end
	if buildMode then
		Action:FireServer("build", x, y, buildMode)
		ring(x, y, GOLD, 3, 0.5)
		if buildMode == "missile" or not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			setBuildMode(nil)
		end
		return
	end
	local o = view.owner[geo:idx(x, y)]
	if o ~= me.id and geo.land[geo:idx(x, y)] then
		toast("Para atacar, escolha um exército no cartão EXÉRCITOS e clique em Atacar", "info")
	end
end

---------------------------------------------------------------- entrada
local pressing, dragging, pressStart, lastPos, rightDrag = false, false, Vector2.zero, nil, false
local rightStart = nil
local openDiplomacy -- definido junto com as janelas
local pinchLast = nil

local function inputPos(input: InputObject): Vector2
	if input.UserInputType == Enum.UserInputType.Touch then
		return Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
	end
	return UserInputService:GetMouseLocation()
end

UserInputService.InputBegan:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.Keyboard then
		if processed then
			return
		end
		local k = input.KeyCode
		for i, code in { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven } do
			if k == code then
				setBuildMode(Config.BUILD_ORDER[i])
			end
		end
		if k == Enum.KeyCode.Escape then
			armyMode = nil
		end
		if k == Enum.KeyCode.Escape or k == Enum.KeyCode.Q then
			setBuildMode(nil)
		elseif k == Enum.KeyCode.Tab then
			board.Visible = not board.Visible
		elseif k == Enum.KeyCode.E then
			pctIndex = pctIndex % #Config.ATTACK_PCTS + 1
			refreshPct()
		elseif k == Enum.KeyCode.R then
			pctIndex = (pctIndex - 2) % #Config.ATTACK_PCTS + 1
			refreshPct()
		elseif k == Enum.KeyCode.Space then
			fitWorld()
		end
		return
	end
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		pressing, dragging = true, false
		pressStart = inputPos(input)
		lastPos = pressStart
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3 then
		rightDrag = true
		lastPos = UserInputService:GetMouseLocation()
		rightStart = lastPos
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		if not processed then
			zoomAt(UserInputService:GetMouseLocation(), 1.15 ^ input.Position.Z)
		end
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		if (pressing or rightDrag) and lastPos then
			local pos = inputPos(input)
			if pressing and not dragging and (pos - pressStart).Magnitude > 8 then
				dragging = true
			end
			if dragging or rightDrag then
				pan += pos - lastPos
				applyView()
			end
			lastPos = pos
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if pressing and not dragging and pinchLast == nil then
			act(inputPos(input))
		end
		pressing, dragging = false, false
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3 then
		rightDrag = false
		local m = UserInputService:GetMouseLocation()
		if input.UserInputType == Enum.UserInputType.MouseButton2 and rightStart and (m - rightStart).Magnitude < 6 then
			local x, y = screenToCell(m)
			local o = x and view.owner[geo:idx(x, y)]
			if o and o ~= 0 and (not me or o ~= me.id) and openDiplomacy then
				openDiplomacy(o)
			end
		end
		rightStart = nil
	end
end)

UserInputService.TouchPinch:Connect(function(positions, scale, _, st, processed)
	if processed then
		return
	end
	if st == Enum.UserInputState.Begin then
		pinchLast = scale
		dragging = true
	elseif st == Enum.UserInputState.Change and pinchLast then
		local center = (positions[1] + (positions[2] or positions[1])) / 2 + GuiService:GetGuiInset()
		zoomAt(center, scale / pinchLast)
		pinchLast = scale
	else
		pinchLast = nil
	end
end)

---------------------------------------------------------------- tooltip
local function nbHas(id)
	return me ~= nil and me.nb ~= nil and table.find(me.nb, id) ~= nil
end

local lastTipKey = nil
local function updateTooltip()
	if not state or dragging then
		tip.Visible = false
		return
	end
	local m = UserInputService:GetMouseLocation()
	local x, y = screenToCell(m)
	local t = x and geo:idx(x, y)
	if not t or not geo.land[t] then
		tip.Visible = false
		return
	end
	tip.Visible = true
	local s = uiScale.Scale
	local vp = camera.ViewportSize
	local px, py = m.X / s + 18, m.Y / s + 18
	if (px + 270) * s > vp.X then
		px = m.X / s - 288
	end
	if (py + 120) * s > vp.Y - 110 * s then
		py = m.Y / s - 138
	end
	tip.Position = UDim2.fromOffset(px, py)

	local owner = view.owner[t]
	local cname = geo.names and geo.names[geo.country[t]] or ""
	local key = owner .. "|" .. cname .. "|" .. tostring(buildMode) .. "|" .. state.phase .. "|" .. tostring(meAt)
	if key == lastTipKey then
		return
	end
	lastTipKey = key

	local hintText
	if menu and menu:isVisible() then
		local n = nationsById[owner]
		hintText = if owner == 0 then "Terra sem dono" elseif n and (n.u or 0) > 0 then "Já tem jogador" else "🖱 Clique para escolher esta nação"
	end
	local function reach(id)
		if armyMode then
			return (nbHas(id) and "🖱 Mandar " or "⛵ Mandar (de barco) ") .. armyMode.name .. " aqui"
		elseif nbHas(id) or (me and me.coast) then
			return "⚔ Escolha um exército para atacar"
		end
		return "ⓘ Sem fronteira ou rota marítima"
	end
	if owner == 0 then
		tipSwatch.BackgroundColor3 = Color3.fromRGB(232, 221, 192)
		tipName.Text = cname ~= "" and cname or "Terra neutra"
		tipTag.Text = "NEUTRO"
		tipBody.Text = "Terra sem dono\nCusto: <b>" .. Config.NEUTRAL_COST .. " tropas</b> por célula"
		hintText = hintText or reach(0)
	else
		local n = nationsById[owner]
		if not n then
			tip.Visible = false
			return
		end
		tipSwatch.BackgroundColor3 = n.c
		tipName.Text = n.n
		local mine = me and owner == me.id
		tipTag.Text = mine and "VOCÊ" or (n.b and "BOT" or "JOGADOR")
		if not n.b and not mine then
			tipName.Text = n.n .. " (" .. (n.pl or "jogador") .. ")"
		end
		tipBody.Text = string.format("Tropas  <b>%s</b>\nTerra  <b>%s</b>  ·  %s", fmt(n.tr), pctText(n.t / state.land * 100), cname)
		if not hintText then
			if mine then
				hintText = buildMode and "🖱 Clique para construir aqui" or "Seu território (1-4 para construir)"
			elseif state.prot > 0 then
				hintText = "🛡 Protegido até a guerra começar"
			else
				hintText = reach(owner)
			end
		end
	end
	if buildMode == "missile" and state.phase == "play" then
		hintText = "🚀 Clique para lançar o míssil aqui"
	end
	tipHint.Text = hintText
end

---------------------------------------------------------------- HUD
local function fmtTime(s)
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function updateHud()
	if state.phase == "select" then
		phaseLbl.Text = "🏳️ ESCOLHA A NAÇÃO"
		phaseLbl.TextColor3 = GOLD
		timerLbl.TextColor3 = GOLD
		timerLbl.Text = fmtTime(state.left)
	elseif state.phase == "play" and state.prot > 0 then
		phaseLbl.Text = "🛡 PROTEGIDO"
		phaseLbl.TextColor3 = GREEN
		timerLbl.TextColor3 = GREEN
		timerLbl.Text = fmtTime(state.prot)
	elseif state.phase == "play" then
		phaseLbl.Text = "⚔️ GUERRA"
		phaseLbl.TextColor3 = RED
		timerLbl.TextColor3 = RED
		timerLbl.Text = fmtTime(state.left)
	else
		phaseLbl.Text = "🏁 FIM DA RODADA"
		phaseLbl.TextColor3 = MUTED
		timerLbl.TextColor3 = TEXT
		timerLbl.Text = fmtTime(state.left)
	end

	local sorted = table.clone(state.nations)
	table.sort(sorted, function(a, b)
		return a.t > b.t
	end)
	local myRank, myShare = nil, 0
	for i, n in sorted do
		if me and n.i == me.id then
			myRank = i
			myShare = n.t / state.land
		end
	end
	local leader = sorted[1]
	myFill.Size = UDim2.fromScale(math.clamp(myShare, 0, 1), 1)
	youLbl.Text = "Você " .. pctText(myShare * 100)
	if leader then
		leaderFill.Size = UDim2.fromScale(math.clamp(leader.t / state.land, 0, 1), 1)
		leaderFill.BackgroundColor3 = leader.c
		leaderLbl.Text = "👑 " .. leader.n .. " " .. pctText(leader.t / state.land * 100)
	else
		leaderLbl.Text = ""
	end
	rankBtn.Text = "📊 " .. (myRank and ("#" .. myRank) or "-") .. " · " .. pctText(myShare * 100)
	if board.Visible then
		for i, row in boardRows do
			local n = sorted[i]
			if n then
				local mine = me and n.i == me.id
				row.Text = string.format('<font color="#%s">■</font> %s%d. %s%s   <font color="#8c94aa">%s · %s</font>', n.c:ToHex(), mine and "<b>" or "", i, n.n, mine and "</b>" or "", pctText(n.t / state.land * 100), fmt(n.tr))
			else
				row.Text = ""
			end
		end
	end

	if me then
		local n = nationsById[me.id]
		if n then
			mySwatch.BackgroundColor3 = n.c
			myFill.BackgroundColor3 = n.c:Lerp(GOLD, 0.3)
		end
		myNameLbl.Text = n and n.n or "-"
		myShareLbl.Text = pctText(myShare * 100) .. " do mundo" .. (civData and string.format("  ·  %.0f mi de habitantes", civData.pop) or "")
		troopRateLbl.Text = "+" .. fmt(me.rate) .. "/s"
		goldRateLbl.Text = "+" .. fmt(me.goldRate) .. "/s"
	end

	if state.phase == "end" then
		local w = state.winner and nationsById[state.winner]
		banner.Text = "🏆 " .. (w and w.n or "Ninguém") .. " dominou o mundo!"
		banner.TextColor3 = GOLD
		subBanner.Text = "Nova rodada em " .. state.left .. "s"
	elseif me and not me.alive then
		banner.Text = "💀 Você foi eliminado"
		banner.TextColor3 = RED
		subBanner.Text = "Escolha outra nação no menu para continuar"
	elseif state.phase == "select" then
		local mine = me and nationsById[me.id]
		banner.Text = if mine then "✅ Você é " .. mine.n .. "! (dá para trocar até começar)" else "🏳️ Escolha sua nação"
		banner.TextColor3 = TEXT
		subBanner.Text = "A partida começa em " .. state.left .. "s"
	elseif not me then
		banner.Text = "🏳️ Escolha uma nação no menu para entrar na guerra"
		banner.TextColor3 = TEXT
		subBanner.Text = ""
	else
		banner.Text = ""
		subBanner.Text = ""
	end

	local parts = {}
	if armyMode then
		parts[#parts + 1] = "<b>⚔ " .. armyMode.name .. "</b>: clique no território que ele deve atacar  <font color='#8c94aa'>(Esc cancela)</font>"
	elseif buildMode then
		local def = Config.BUILDINGS[buildMode]
		parts[#parts + 1] = string.format("<b>%s</b>: %s (obra: %d s)  <font color='#8c94aa'>(clique no mapa · Esc cancela)</font>", def.name, def.desc, def.time or 0)
	elseif me and me.attacks and #me.attacks > 0 then
		local list = {}
		for _, a in me.attacks do
			local nm = a.to == 0 and "Terra neutra" or (nationsById[a.to] and nationsById[a.to].n or "?")
			list[#list + 1] = nm .. " (" .. fmt(a.tr) .. ")"
		end
		parts[#parts + 1] = "⚔️ Atacando: " .. table.concat(list, " · ")
	end
	hint.Text = table.concat(parts, "  ")
end

-- dados fixos das nações (nome, cor, jogador), por rodada
local meta = {}
local metaRound = 0
local function applyColors()
	local recolor, any = {}, false
	for id, n in meta do
		local rgb = { math.floor(n.c.R * 255 + 0.5), math.floor(n.c.G * 255 + 0.5), math.floor(n.c.B * 255 + 0.5) }
		if view:setColor(id, rgb) then
			recolor[id] = true
			any = true
		end
	end
	if any then
		view:repaintOwners(recolor)
	end
end
NationsEv.OnClientEvent:Connect(function(round, list)
	if round ~= metaRound then
		metaRound = round
		table.clear(meta)
	end
	for _, m in list do
		local n = meta[m.i] or {}
		n.i, n.n, n.c, n.u, n.pl = m.i, m.n, m.c, m.u, m.pl
		n.b = (m.u or 0) == 0
		meta[m.i] = n
	end
	applyColors()
end)

local hadNation = nil
local updateArmyCard, updateCharacters -- definidos mais abaixo
local panels -- criado mais abaixo (Panels.new)
local detail = DetailView.new(geo, view, mapFrame)
local function focusNation(id)
	local n = nationsById[id]
	if not n or n.ax < 0 then
		return
	end
	local v = camera.ViewportSize
	zoom = math.clamp(math.max(minZoom() * 2.5, 600 / math.max(8, math.sqrt(n.t) * 3)), minZoom(), 24)
	pan = Vector2.new(v.X / 2, v.Y / 2) - Vector2.new(n.ax + 0.5, n.ay + 0.5) * zoom
	labelsDirty = true
	applyView()
end

menu = NationMenu.new(gui, fmt, function(id)
	Action:FireServer("choose", id, 0)
end, focusNation)

StateEv.OnClientEvent:Connect(function(s)
	local roundChanged = state ~= nil and state.round ~= s.round
	-- junta os números com os dados fixos: { id, células, tropas, ax, ay }
	local list = {}
	table.clear(nationsById)
	if s.round == metaRound then
		for _, e in s.nations do
			local n = meta[e[1]]
			if n then
				n.t, n.tr, n.ax, n.ay = e[2], e[3], e[4], e[5]
				list[#list + 1] = n
				nationsById[n.i] = n
			end
		end
	end
	s.nations = list
	state = s
	me = s.me
	meAt = os.clock()

	-- menu de nações: na fase de escolha, ou quando não há nação viva
	local needMenu = s.phase == "select" or not me or not me.alive
	if s.phase == "end" then
		needMenu = false
	end
	menu:setVisible(needMenu)
	bottom.Visible = me ~= nil and me.alive
	local phaseText = if s.phase == "select" then "A partida começa em " .. s.left .. "s · clique na lista ou no mapa" else "Assuma um país controlado por bot"
	menu:update(list, s.land, phaseText)
	if me and me.id ~= hadNation then
		hadNation = me.id
		menu:select(me.id)
		task.defer(focusNation, me.id)
	elseif not me then
		hadNation = nil
	end
	if roundChanged then
		clearLabels()
		setBuildMode(nil)
		fitWorld()
	end
	updateLabels()
	updateBuildings()
	updateBoats()
	updateAttacks()
	updateTrains()
	updateFlights()
	updateHud()
	if not gotState then
		gotState = true
		checkReady()
	end
end)

Effect.OnClientEvent:Connect(function(kind, x, y, r)
	if kind == "gold" then
		goldPopup(x, y, r)
	elseif kind == "missile" then
		ring(x, y, Color3.fromRGB(255, 150, 40), (r or 5) * 1.6, 1.2)
		ring(x, y, Color3.fromRGB(255, 240, 180), (r or 5) * 0.8, 0.6)
	elseif kind == "intercept" then
		ring(x, y, Color3.fromRGB(200, 230, 255), 3, 0.6)
		local l = new("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale((x + 0.5) / W, (y + 0.5) / H),
			Size = UDim2.fromOffset(160, 22),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			TextSize = 16,
			TextColor3 = Color3.fromRGB(200, 230, 255),
			TextStrokeTransparency = 0.2,
			Text = "INTERCEPTADO!",
			ZIndex = 11,
		}, overlay)
		TweenService:Create(l, TweenInfo.new(1.5), { Position = UDim2.new((x + 0.5) / W, 0, (y + 0.5) / H, -36), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.delay(1.6, function()
			l:Destroy()
		end)
	end
end)

---------------------------------------------------------------- trilhos
RailsEv.OnClientEvent:Connect(function(round, buf, full)
	if full then
		table.clear(view.rails)
	end
	local n = buffer.len(buf) // 4
	for i = 0, n - 1 do
		local t = buffer.readu32(buf, i * 4) + 1
		if full then
			view.rails[t] = true
		else
			view:addRail(t)
		end
	end
	if full then
		view:redrawAll()
		detail:reset()
	end
end)

---------------------------------------------------------------- cartão de exércitos
local armyRowCache = ""
function updateArmyCard(data)
	local gens = {}
	for _, g in data.generals do
		gens[g.id] = g
	end
	local key = ""
	for _, a in data.armies do
		key ..= a.id .. ":" .. a.troops .. ":" .. tostring(a.busy) .. ";"
	end
	key ..= tostring(armyMode and armyMode.id)
	if key == armyRowCache then
		return
	end
	armyRowCache = key
	for _, c in armyRows:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	if #data.armies == 0 then
		label({ Size = UDim2.fromOffset(276, 36), TextSize = 12, TextWrapped = true, Font = Enum.Font.GothamMedium, TextColor3 = MUTED, Text = "Nenhum exército. Clique em \"+ Formar\" para criar um." }, armyRows)
	end
	for i, a in data.armies do
		if i > 3 then
			label({ Size = UDim2.fromOffset(276, 14), TextSize = 11, TextColor3 = MUTED, Text = "+" .. (#data.armies - 3) .. " exército(s) na janela Exércitos", LayoutOrder = 9 }, armyRows)
			break
		end
		local sel = armyMode and armyMode.id == a.id
		local row = new("Frame", { Size = UDim2.fromOffset(276, 22), BackgroundColor3 = sel and Color3.fromRGB(70, 60, 20) or DARK2, BorderSizePixel = 0, LayoutOrder = i }, armyRows)
		corner(row, 6)
		local g = a.gen and gens[a.gen]
		label({ Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(196, 22), TextSize = 12, RichText = true, Text = string.format("%s  <font color=\"#F5C846\">%s</font>  <font color=\"#8c94aa\">%s</font>", a.name, fmt(a.troops), g and ("Nv" .. g.level) or "") }, row)
		if a.busy then
			label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), Size = UDim2.fromOffset(70, 22), TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = RED, Text = "em combate" }, row)
		else
			local b = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -3, 0.5, 0), Size = UDim2.fromOffset(64, 18), BackgroundColor3 = sel and GREEN or GOLD, BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Color3.fromRGB(25, 25, 30), Text = sel and "Alvo?" or "Atacar" }, row)
			corner(b, 5)
			b.Activated:Connect(function()
				setBuildMode(nil)
				armyMode = if sel then nil else { id = a.id, name = a.name }
				armyRowCache = ""
				updateArmyCard(data)
			end)
		end
	end
end

---------------------------------------------------------------- personagens (você, líderes de partido e generais)
local LEADERS = { "Helena Prado", "Otávio Reis", "Marta Kovač", "Ivan Sokol", "Lúcia Ferraz", "Bruno Taveira", "Ana Lindqvist", "Jorge Matos", "Sofia Arendt", "Raul Benítez", "Clara Moura", "Tomás Wolff" }
local TITLES = { cap = "Presidente", com = "Secretário-Geral", fas = "Líder Supremo" }
local IDEO_COLOR = { cap = Color3.fromRGB(70, 110, 190), com = Color3.fromRGB(190, 50, 50), fas = Color3.fromRGB(110, 95, 70) }
local charStrip = new("Frame", { Name = "Characters", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.fromOffset(0, 104), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Visible = false }, gui)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Bottom, SortOrder = Enum.SortOrder.LayoutOrder }, charStrip)
local charKey = ""

local function charCard(order, big, name, role, roleColor, draw, onClick)
	local w = big and 92 or 70
	local c = new("TextButton", { Size = UDim2.fromOffset(w, big and 104 or 88), BackgroundColor3 = DARK, BackgroundTransparency = 0.06, BorderSizePixel = 0, Text = "", AutoButtonColor = true, LayoutOrder = order }, charStrip)
	corner(c, 12)
	new("UIStroke", { Color = big and GOLD or Color3.fromRGB(70, 80, 105), Thickness = big and 2 or 1, Transparency = big and 0 or 0.4 }, c)
	local holder = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(w - 16, w - 16), BackgroundTransparency = 1 }, c)
	draw(holder)
	label({ Position = UDim2.new(0, 4, 1, -30), Size = UDim2.new(1, -8, 0, 14), TextSize = big and 11 or 10, TextXAlignment = Enum.TextXAlignment.Center, Text = name }, c)
	label({ Position = UDim2.new(0, 4, 1, -16), Size = UDim2.new(1, -8, 0, 12), TextSize = 9, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = roleColor or MUTED, Text = role }, c)
	if onClick then
		c.Activated:Connect(onClick)
	end
	return c
end

function updateCharacters(data)
	charStrip.Visible = me ~= nil
	-- humor dos partidos: apoio ao projeto em votação (ou felicidade geral)
	local key = data.gov .. (data.bill and data.bill.law or "") .. #data.generals
	for _, p in data.parliament or {} do
		key ..= p.name .. (p.sup and (p.sup > 0.2 and "+" or (p.sup < -0.2 and "-" or "0")) or "")
	end
	for _, g in data.generals do
		key ..= g.level
	end
	key ..= math.floor(data.happy / 20)
	if key == charKey then
		return
	end
	charKey = key
	for _, c in charStrip:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	-- você (avatar de verdade do jogador)
	charCard(1, true, player.DisplayName, TITLES[data.gov] or "Líder", GOLD, function(h)
		local img = new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = DARK2, Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150" }, h)
		corner(img, 999)
	end, function()
		panels.show("politics")
	end)
	-- líderes dos partidos
	local parties = data.parliament
	if not parties then
		parties = {}
		for _, p in CivData.PARTIES[data.gov] do
			parties[#parties + 1] = { name = p.name, seats = 0, amb = p.amb }
		end
	end
	for i, p in parties do
		local def = CivData.PARTIES[data.gov][i] or {}
		local col = Color3.fromRGB(90, 90, 100)
		for k, w in def.ideo or {} do
			col = col:Lerp(IDEO_COLOR[k], w * 0.8)
		end
		local mood = p.sup or ((data.happy - 50) / 50)
		local seed = (me and me.id or 1) * 13 + i * 7
		local leader = LEADERS[(seed % #LEADERS) + 1]
		local role = p.sup and (p.sup > 0 and "a favor" or "contra") or ((p.seats or 0) > 0 and (p.seats .. " cadeiras") or p.name)
		charCard(1 + i, false, leader, role, p.sup and (p.sup > 0 and GREEN or RED) or MUTED, function(h)
			Portraits.make(h, { seed = seed, suit = col, hat = "none", mood = mood, z = 6 })
		end, function()
			panels.show("politics")
		end)
	end
	-- generais
	for i, g in data.generals do
		if i > 3 then
			break
		end
		charCard(10 + i, false, g.name, "General Nv" .. g.level, GOLD, function(h)
			Portraits.make(h, { seed = g.id * 3 + 1, suit = Color3.fromRGB(85, 100, 60), hat = (g.id % 2 == 0) and "beret" or "cap", military = true, mood = 0.5, z = 6 })
		end, function()
			panels.show("armies")
		end)
	end
end

---------------------------------------------------------------- civilização (dados do jogador) e janelas
CivEv.OnClientEvent:Connect(function(round, data)
	civData = data
	-- HUD lateral
	local gov = CivData.GOVS[data.gov]
	govBadge.Text = gov.name
	govBadge.BackgroundColor3 = Color3.fromRGB(gov.color[1], gov.color[2], gov.color[3])
	local h = math.floor(data.happy)
	happyLbl.Text = string.format("Felicidade %d%s", h, h < 20 and "  ⚠ risco de revolução" or "")
	happyLbl.TextColor3 = h < 20 and RED or TEXT
	TweenService:Create(happyBar, TweenInfo.new(0.5), { Size = UDim2.fromScale(math.clamp(data.happy / 100, 0, 1), 1) }):Play()
	happyBar.BackgroundColor3 = h >= 50 and GREEN or (h >= 25 and GOLD or RED)
	infoLbl.Text = string.format("Influência %d  ·  Pesquisa %d pts  ·  %d exércitos", data.influence, data.rp, #data.armies)
	for r, row in resRows do
		local net = (data.prod[r] or 0) - (data.need[r] or 0)
		row.stock.Text = fmt(data.stock[r] or 0)
		row.net.Text = string.format("%+.1f/s", net)
		row.net.TextColor3 = net >= 0 and GREEN or RED
		row.name.TextColor3 = data.short[r] and RED or TEXT
	end
	updateArmyCard(data)
	updateCharacters(data)
	menuButtons.diplomacy.Text = #data.proposals > 0 and ("🤝 Diplomacia (" .. #data.proposals .. ")") or "🤝 Diplomacia"
	menuButtons.diplomacy.BackgroundColor3 = #data.proposals > 0 and Color3.fromRGB(110, 90, 20) or DARK2
	panels.refresh()
end)

local routeLines = {}
local routeData = nil
local routeZoom = 0
local function drawRoute()
	for _, f in routeLines do
		f:Destroy()
	end
	table.clear(routeLines)
	if not routeData then
		return
	end
	local pts = routeData.pts
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local ax, ay = (a[1] + 0.5) * zoom, (a[2] + 0.5) * zoom
		local bx, by = (b[1] + 0.5) * zoom, (b[2] + 0.5) * zoom
		if math.abs(b[1] - a[1]) <= W / 2 then
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2),
				Size = UDim2.fromOffset(math.max(3, math.abs(bx - ax) + 3), math.max(3, math.abs(by - ay) + 3)),
				BackgroundColor3 = GOLD,
				BackgroundTransparency = 0.15,
				BorderSizePixel = 0,
				ZIndex = 6,
			}, overlay)
			routeLines[#routeLines + 1] = f
		end
	end
end

panels = Panels.new({
	gui = gui,
	fmt = fmt,
	send = function(op, t)
		t.op = op
		Action:FireServer("civ", 0, 0, t)
	end,
	civ = function()
		return civData
	end,
	nations = function()
		return state and state.nations or {}
	end,
	nationsById = function()
		return nationsById
	end,
	land = function()
		return state and state.land or 1
	end,
	me = function()
		return me
	end,
	focusNation = function(id)
		focusNation(id)
	end,
	setArmyMode = function(id, name)
		setBuildMode(nil)
		armyMode = { id = id, name = name }
	end,
	showRoute = function(rt)
		if not rt.pts then
			toast("Rota por navio: só o barco aparece no mapa", "info")
			return
		end
		routeData = rt
		drawRoute()
		local mid = rt.pts[math.max(1, #rt.pts // 2)]
		local v = camera.ViewportSize
		pan = Vector2.new(v.X / 2, v.Y / 2) - Vector2.new(mid[1] + 0.5, mid[2] + 0.5) * zoom
		applyView()
		task.delay(10, function()
			if routeData == rt then
				routeData = nil
				drawRoute()
			end
		end)
	end,
	toast = toast,
})
armyFormBtn.Activated:Connect(function()
	if me then
		panels.show("armies")
	end
end)
for name, b in menuButtons do
	b.Activated:Connect(function()
		if not me then
			toast("Escolha uma nação primeiro", "error")
			return
		end
		panels.open(name)
	end)
end
function openDiplomacy(id)
	if not me then
		return
	end
	panels.show("diplomacy")
	panels.diplomacy.select(id)
end

-- pede o mapa completo agora que tudo está conectado
loadStep("Conectando ao servidor...", 0.6)
Action:FireServer("sync", 0, 0)

---------------------------------------------------------------- loop por quadro
local flushAcc = 0
RunService.RenderStepped:Connect(function(dt)
	if not UserInputService:GetFocusedTextBox() then
		local move = Vector2.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
			move += Vector2.new(0, 1)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
			move += Vector2.new(0, -1)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
			move += Vector2.new(1, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
			move += Vector2.new(-1, 0)
		end
		if move.Magnitude > 0 then
			pan += move * 700 * dt
			applyView()
		end
	end

	if labelsDirty then
		labelsDirty = false
		resizeAllLabels()
		resizeIcons()
	end

	-- desenha as células que mudaram (até 20x por segundo)
	flushAcc += dt
	if flushAcc >= 0.05 then
		flushAcc = 0
		view:flush()
	end

	-- números suaves entre pacotes do servidor
	if me then
		local since = os.clock() - meAt
		local troops = math.min(me.max, me.troops + me.rate * since)
		local gold = me.gold + me.goldRate * since
		troopsLbl.Text = fmt(troops) .. ' <font size="15" color="#8c94aa">/ ' .. fmt(me.max) .. "</font>"
		troopBar.Size = UDim2.fromScale(math.clamp(troops / math.max(1, me.max), 0, 1), 1)
		goldLbl.Text = fmt(gold)
		sendLbl.Text = "Envia " .. fmt(troops * Config.ATTACK_PCTS[pctIndex]) .. " tropas"
		for kind, b in buildButtons do
			local cost = me.costs and me.costs[kind] or b.def.cost
			if kind == "missile" and not me.silo then
				b.cost.Text = "travado"
				b.cost.TextColor3 = MUTED
			else
				b.cost.Text = fmt(cost)
				b.cost.TextColor3 = (gold >= cost) and GOLD or RED
			end
		end
	end
	animateFlights()
	-- visão detalhada no zoom alto
	local vp = camera.ViewportSize
	local center = (vp / 2 - pan) / zoom
	detail:update(zoom >= Config.DETAIL_ZOOM, center.X % W, center.Y)
	-- barcos balançando
	local tnow = os.clock()
	for id, ic in boatIcons do
		ic.Rotation = math.sin(tnow * 3 + id) * 7
	end
	for id, ic in trainIcons do
		if ic:GetAttribute("Bob") then
			ic.Rotation = math.sin(tnow * 3 + id) * 7
		end
	end
	if routeData and routeZoom ~= zoom then
		routeZoom = zoom
		drawRoute()
	end
	updateTooltip()
end)
