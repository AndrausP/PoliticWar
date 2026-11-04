-- Tela de carregamento: aparece antes de tudo (ReplicatedFirst) e some quando o mapa
-- está desenhado. O script do cliente informa o progresso pelos atributos do jogador:
-- LoadStep (texto), LoadPct (0..1) e MapReady (true).
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in props do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local BG = Color3.fromRGB(44, 104, 168)
local DARK = Color3.fromRGB(22, 26, 38)
local GOLD = Color3.fromRGB(245, 200, 70)
local TEXT = Color3.fromRGB(235, 238, 245)
local MUTED = Color3.fromRGB(190, 205, 225)

local gui = new("ScreenGui", { Name = "Loading", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 1000 }, nil)
local bg = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = BG, BorderSizePixel = 0 }, gui)
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(Color3.fromRGB(62, 128, 194), Color3.fromRGB(30, 78, 134)),
}, bg)

local center = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(520, 260), BackgroundTransparency = 1 }, bg)
new("UIScale", { Scale = 1 }, center)

-- "globo" girando: anel com dois arcos
local globe = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(64, 64), BackgroundColor3 = Color3.fromRGB(232, 221, 192) }, center)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, globe)
new("UIStroke", { Color = DARK, Thickness = 3 }, globe)
local band = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.36, 1), BackgroundTransparency = 1 }, globe)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, band)
new("UIStroke", { Color = DARK, Thickness = 3 }, band)
new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = DARK, BorderSizePixel = 0 }, globe)

new("TextLabel", {
	Position = UDim2.fromOffset(0, 78),
	Size = UDim2.new(1, 0, 0, 52),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextSize = 46,
	TextColor3 = TEXT,
	Text = "DOMÍNIO MUNDIAL",
	TextStrokeTransparency = 0.6,
}, center)
local tip = new("TextLabel", {
	Position = UDim2.fromOffset(0, 130),
	Size = UDim2.new(1, 0, 0, 22),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	TextSize = 16,
	TextColor3 = MUTED,
	Text = "",
}, center)
local barBg = new("Frame", { Position = UDim2.fromOffset(60, 178), Size = UDim2.new(1, -120, 0, 12), BackgroundColor3 = DARK, BackgroundTransparency = 0.2, BorderSizePixel = 0 }, center)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, barBg)
local bar = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = GOLD, BorderSizePixel = 0 }, barBg)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, bar)
local status = new("TextLabel", {
	Position = UDim2.fromOffset(0, 198),
	Size = UDim2.new(1, 0, 0, 22),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextColor3 = TEXT,
	Text = "Carregando o jogo...",
}, center)

gui.Parent = player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

local TIPS = {
	"Escolha um país real e comande a sua conquista",
	"Países grandes têm mais tropas; países pequenos crescem rápido",
	"Escolha quantas tropas mandar: 10%, 25%, 35%, 50% ou 75%",
	"Sem fronteira? Clique do outro lado do mar para mandar um barco",
	"Cidades aumentam o limite de tropas; fábricas dão ouro",
	"Fortalezas fazem o inimigo pagar 2,5x mais tropas",
	"Foi eliminado? Assuma outro país controlado por bot",
	"Domine 80% do mundo para vencer a rodada",
}
local tipIndex = math.random(#TIPS)
tip.Text = TIPS[tipIndex]

local shown = 0
local t0 = os.clock()
local lastTip = os.clock()
local timedOut = false
while not player:GetAttribute("MapReady") do
	-- segurança: se algo travar, não deixa a tela de carregamento eterna
	if os.clock() - t0 > 45 then
		timedOut = true
		break
	end
	local dt = RunService.RenderStepped:Wait()
	local target = player:GetAttribute("LoadPct")
	if target == nil then
		-- antes do script do jogo começar: avança devagar enquanto o jogo baixa
		target = if game:IsLoaded() then 0.12 else math.min(0.1, (os.clock() - t0) * 0.02)
	end
	shown += (target - shown) * math.min(1, dt * 6)
	bar.Size = UDim2.fromScale(math.clamp(shown, 0.02, 1), 1)
	status.Text = player:GetAttribute("LoadStep") or (if game:IsLoaded() then "Iniciando..." else "Carregando o jogo...")
	globe.Rotation = math.sin(os.clock() * 2) * 12
	band.Size = UDim2.fromScale(0.15 + math.abs(math.sin(os.clock() * 1.5)) * 0.7, 1)
	if os.clock() - lastTip > 4 then
		lastTip = os.clock()
		tipIndex = tipIndex % #TIPS + 1
		tip.Text = TIPS[tipIndex]
	end
end

-- completa a barra e some
status.Text = timedOut and "Demorou demais: veja o Output (F9) para o erro" or "Pronto!"
if timedOut then
	warn("[Loading] O cliente não avisou que o mapa ficou pronto em 45 s. Veja os erros do script Client no Output.")
	task.wait(2)
end
TweenService:Create(bar, TweenInfo.new(0.25), { Size = UDim2.fromScale(1, 1) }):Play()
task.wait(0.3)
local fade = TweenInfo.new(0.5)
TweenService:Create(bg, fade, { BackgroundTransparency = 1 }):Play()
for _, d in bg:GetDescendants() do
	if d:IsA("TextLabel") then
		TweenService:Create(d, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	elseif d:IsA("Frame") then
		TweenService:Create(d, fade, { BackgroundTransparency = 1 }):Play()
	elseif d:IsA("UIStroke") then
		TweenService:Create(d, fade, { Transparency = 1 }):Play()
	end
end
task.wait(0.55)
gui:Destroy()
