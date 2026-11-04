--!nocheck
-- Menu "Escolha sua nação": lista dos países (busca, tamanho, tropas, quem joga),
-- seleção pela lista ou pelo mapa e botão para confirmar.
local NationMenu = {}
NationMenu.__index = NationMenu

local DARK = Color3.fromRGB(22, 26, 38)
local DARK2 = Color3.fromRGB(36, 42, 58)
local ROW = Color3.fromRGB(30, 35, 50)
local TEXT = Color3.fromRGB(235, 238, 245)
local MUTED = Color3.fromRGB(140, 148, 170)
local GOLD = Color3.fromRGB(245, 200, 70)
local GREEN = Color3.fromRGB(90, 220, 120)

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in props do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function corner(p, r)
	new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, p)
end

-- busca sem acentos e sem maiúsculas
local ACCENTS = {
	["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a",
	["é"] = "e", ["ê"] = "e", ["è"] = "e", ["í"] = "i", ["î"] = "i",
	["ó"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o", ["ú"] = "u", ["ü"] = "u", ["ç"] = "c",
	["Á"] = "a", ["Â"] = "a", ["Ã"] = "a", ["É"] = "e", ["Ê"] = "e", ["Í"] = "i",
	["Ó"] = "o", ["Ô"] = "o", ["Õ"] = "o", ["Ú"] = "u", ["Ç"] = "c",
}
local function norm(s)
	s = string.gsub(s, "[\192-\255][\128-\191]*", function(ch)
		return ACCENTS[ch] or ch
	end)
	return string.lower(s)
end

-- fmt: função de formatar números do cliente
function NationMenu.new(parent, fmt, onConfirm, onFocus)
	local self = setmetatable({}, NationMenu)
	self.fmt = fmt
	self.onConfirm = onConfirm
	self.onFocus = onFocus
	self.rows = {}
	self.selected = nil
	self.query = ""

	local panel = new("Frame", {
		Name = "NationMenu",
		Position = UDim2.fromOffset(12, 96),
		Size = UDim2.new(0, 340, 1, -236),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Active = true,
		Visible = false,
	}, parent)
	corner(panel, 14)
	new("UIStroke", { Color = Color3.fromRGB(70, 80, 105), Transparency = 0.4 }, panel)
	self.panel = panel

	new("TextLabel", {
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -32, 0, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		TextColor3 = TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "🏳️ ESCOLHA SUA NAÇÃO",
	}, panel)
	self.subtitle = new("TextLabel", {
		Position = UDim2.fromOffset(16, 38),
		Size = UDim2.new(1, -32, 0, 18),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Clique na lista ou no mapa",
	}, panel)

	local search = new("TextBox", {
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.new(1, -32, 0, 32),
		BackgroundColor3 = DARK2,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextColor3 = TEXT,
		PlaceholderText = "🔍 Buscar país...",
		PlaceholderColor3 = MUTED,
		Text = "",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, panel)
	corner(search, 8)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10) }, search)
	search:GetPropertyChangedSignal("Text"):Connect(function()
		self.query = norm(search.Text)
		self:refresh()
	end)

	-- cabeçalho das colunas
	local head = new("Frame", { Position = UDim2.fromOffset(16, 102), Size = UDim2.new(1, -32, 0, 16), BackgroundTransparency = 1 }, panel)
	for _, col in { { "PAÍS", 26, Enum.TextXAlignment.Left }, { "TERRA", -112, Enum.TextXAlignment.Right }, { "TROPAS", -56, Enum.TextXAlignment.Right } } do
		new("TextLabel", {
			Position = if col[2] > 0 then UDim2.fromOffset(col[2], 0) else UDim2.new(1, col[2] - 50, 0, 0),
			Size = UDim2.fromOffset(if col[2] > 0 then 120 else 50, 16),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 11,
			TextColor3 = MUTED,
			TextXAlignment = col[3],
			Text = col[1],
		}, head)
	end

	local list = new("ScrollingFrame", {
		Position = UDim2.fromOffset(10, 122),
		Size = UDim2.new(1, -20, 1, -122 - 92),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = MUTED,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, panel)
	new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 10) }, list)
	self.list = list

	-- rodapé: seleção + confirmar
	local foot = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -12), Size = UDim2.new(1, -32, 0, 76), BackgroundTransparency = 1 }, panel)
	self.selInfo = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		RichText = true,
		Text = "Nenhuma nação selecionada",
	}, foot)
	local btn = new("TextButton", {
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = GOLD,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		TextSize = 17,
		TextColor3 = Color3.fromRGB(30, 30, 30),
		Text = "SELECIONE UMA NAÇÃO",
		AutoButtonColor = true,
	}, foot)
	corner(btn, 10)
	btn.Activated:Connect(function()
		if self.selected and self.canPick then
			self.onConfirm(self.selected)
		end
	end)
	self.button = btn
	return self
end

function NationMenu:setVisible(v)
	self.panel.Visible = v
end

function NationMenu:isVisible()
	return self.panel.Visible
end

local function makeRow(self, id)
	local row = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = ROW,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = true,
	}, self.list)
	corner(row, 6)
	local stroke = new("UIStroke", { Color = GOLD, Thickness = 2, Enabled = false, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, row)
	local sw = new("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(14, 14), BorderSizePixel = 0 }, row)
	corner(sw, 3)
	local name = new("TextLabel", {
		Position = UDim2.fromOffset(30, 0),
		Size = UDim2.new(1, -150, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		RichText = true,
	}, row)
	local land = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -62, 0, 0),
		Size = UDim2.fromOffset(52, 30),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, row)
	local troops = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 0),
		Size = UDim2.fromOffset(52, 30),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = TEXT,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, row)
	row.Activated:Connect(function()
		self:select(id)
		if self.onFocus then
			self.onFocus(id)
		end
	end)
	local r = { row = row, sw = sw, name = name, land = land, troops = troops, stroke = stroke }
	self.rows[id] = r
	return r
end

-- nations: lista de nações vivas do cliente (com i, n, c, t, tr, u, pl); land: total de terra
function NationMenu:update(nations, land, phaseText)
	self.nations = nations
	self.land = land
	if phaseText then
		self.subtitle.Text = phaseText
	end
	if self.panel.Visible then
		self:refresh()
	end
end

function NationMenu:refresh()
	local nations = self.nations
	if not nations then
		return
	end
	local sorted = table.clone(nations)
	table.sort(sorted, function(a, b)
		return a.t > b.t
	end)
	local seen = {}
	local order = 0
	for _, n in sorted do
		local r = self.rows[n.i] or makeRow(self, n.i)
		seen[n.i] = true
		if self.query == "" or string.find(norm(n.n), self.query, 1, true) then
			order += 1
			r.row.Visible = true
			r.row.LayoutOrder = order
			r.sw.BackgroundColor3 = n.c
			local taken = (n.u or 0) > 0
			r.name.Text = if taken then string.format('%s <font color="#5ADC78">· %s</font>', n.n, n.pl or "jogador") else n.n
			r.name.TextColor3 = if taken then MUTED else TEXT
			r.land.Text = string.format("%.1f%%", n.t / math.max(1, self.land) * 100)
			r.troops.Text = self.fmt(n.tr)
			r.stroke.Enabled = self.selected == n.i
		else
			r.row.Visible = false
		end
	end
	for id, r in self.rows do
		if not seen[id] then
			r.row:Destroy()
			self.rows[id] = nil
		end
	end
	self:refreshSelection()
end

function NationMenu:select(id)
	self.selected = id
	for rid, r in self.rows do
		r.stroke.Enabled = rid == id
	end
	self:refreshSelection()
end

function NationMenu:refreshSelection()
	local n
	for _, v in self.nations or {} do
		if v.i == self.selected then
			n = v
			break
		end
	end
	if not n then
		self.canPick = false
		self.selInfo.Text = "Nenhuma nação selecionada"
		self.button.Text = "SELECIONE UMA NAÇÃO"
		self.button.BackgroundColor3 = DARK2
		self.button.TextColor3 = MUTED
		return
	end
	local taken = (n.u or 0) > 0
	self.canPick = not taken
	self.selInfo.Text = string.format('<font color="#%s">■</font> %s  <font color="#8c94aa">%.1f%% · %s tropas</font>', n.c:ToHex(), n.n, n.t / math.max(1, self.land) * 100, self.fmt(n.tr))
	if taken then
		self.button.Text = "JÁ TEM JOGADOR"
		self.button.BackgroundColor3 = DARK2
		self.button.TextColor3 = MUTED
	else
		self.button.Text = "JOGAR COMO " .. n.n
		self.button.BackgroundColor3 = GOLD
		self.button.TextColor3 = Color3.fromRGB(30, 30, 30)
	end
end

return NationMenu
