--!nocheck
-- Janelas do jogo: Exércitos, Diplomacia, Habilidades, Mercado e Política.
-- ctx: { gui, fmt, send(op, tbl), civ(), nations(), nationsById(), me(), focusNation(id), setArmyMode(id), showRoute(route), toast }
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local D = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CivData"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Panels = {}

local DARK = Color3.fromRGB(22, 26, 38)
local DARK2 = Color3.fromRGB(36, 42, 58)
local ROW = Color3.fromRGB(30, 35, 50)
local TEXT = Color3.fromRGB(235, 238, 245)
local MUTED = Color3.fromRGB(140, 148, 170)
local GOLD = Color3.fromRGB(245, 200, 70)
local GREEN = Color3.fromRGB(90, 220, 120)
local RED = Color3.fromRGB(240, 90, 90)
local BLUE = Color3.fromRGB(90, 150, 240)

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
local function label(parent, props)
	local l = new("TextLabel", { BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, parent)
	for k, v in props do
		l[k] = v
	end
	return l
end
local function button(parent, text, color, props, onClick)
	local b = new("TextButton", {
		BackgroundColor3 = color or DARK2,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = (color == GOLD or color == GREEN) and Color3.fromRGB(25, 25, 30) or TEXT,
		Text = text,
		AutoButtonColor = true,
	}, parent)
	for k, v in props or {} do
		b[k] = v
	end
	corner(b, 7)
	new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.85, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 210)) }, b)
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end
local function scroll(parent, props)
	local s = new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = MUTED,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, parent)
	for k, v in props do
		s[k] = v
	end
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, s)
	new("UIPadding", { PaddingRight = UDim.new(0, 8) }, s)
	return s
end
local function clear(f)
	for _, c in f:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end
local function bar(parent, props, frac, color)
	local bg = new("Frame", { BackgroundColor3 = DARK2, BorderSizePixel = 0 }, parent)
	for k, v in props do
		bg[k] = v
	end
	corner(bg, 4)
	local f = new("Frame", { Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1), BackgroundColor3 = color, BorderSizePixel = 0 }, bg)
	corner(f, 4)
	return bg, f
end

-- janela base
local function window(ctx, title)
	local w = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, -170, 0.5, 20),
		Size = UDim2.fromOffset(780, 540),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.02,
		BorderSizePixel = 0,
		Active = true,
		Visible = false,
		ZIndex = 30,
	}, ctx.gui)
	corner(w, 14)
	new("UIStroke", { Color = Color3.fromRGB(90, 100, 135), Transparency = 0.15, Thickness = 1.5 }, w)
	local head = new("Frame", { Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = Color3.fromRGB(32, 38, 56), BorderSizePixel = 0 }, w)
	corner(head, 14)
	new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(60, 70, 110), Color3.fromRGB(28, 32, 48)) }, head)
	new("Frame", { Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = GOLD, BorderSizePixel = 0 }, w)

	label(w, { Position = UDim2.fromOffset(18, 12), Size = UDim2.new(1, -80, 0, 28), TextSize = 22, Font = Enum.Font.GothamBlack, Text = title })
	local sub = label(w, { Position = UDim2.fromOffset(18, 40), Size = UDim2.new(1, -80, 0, 18), TextSize = 13, Font = Enum.Font.GothamMedium, TextColor3 = MUTED, Text = "" })
	button(w, "✕", DARK2, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(32, 32), TextSize = 16 }, function()
		w.Visible = false
	end)
	local body = new("Frame", { Position = UDim2.fromOffset(18, 66), Size = UDim2.new(1, -36, 1, -80), BackgroundTransparency = 1 }, w)
	return w, body, sub
end

---------------------------------------------------------------- EXÉRCITOS
local function armiesPanel(ctx)
	local w, body, sub = window(ctx, "⚔ Exércitos e Generais")
	local left = new("Frame", { Size = UDim2.new(0.55, -8, 1, 0), BackgroundTransparency = 1 }, body)
	local right = new("Frame", { Position = UDim2.new(0.55, 8, 0, 0), Size = UDim2.new(0.45, -8, 1, 0), BackgroundTransparency = 1 }, body)
	label(left, { Size = UDim2.new(1, 0, 0, 20), Text = "SEUS EXÉRCITOS", TextColor3 = GOLD, TextSize = 13 })
	local list = scroll(left, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 1, -24) })
	label(right, { Size = UDim2.new(1, 0, 0, 20), Text = "FORMAR EXÉRCITO", TextColor3 = GOLD, TextSize = 13 })
	local pct = 0.25
	local genChoice = nil
	local pctRow = new("Frame", { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, right)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, pctRow)
	local pctBtns = {}
	local genBtn, formBtn, amountLbl
	local function refreshForm()
		local me = ctx.me()
		for p, b in pctBtns do
			b.BackgroundColor3 = p == pct and GOLD or DARK2
			b.TextColor3 = p == pct and Color3.fromRGB(25, 25, 30) or TEXT
		end
		amountLbl.Text = "Tropas: " .. ctx.fmt((me and me.troops or 0) * pct)
		local civ = ctx.civ()
		local g
		for _, gg in civ and civ.generals or {} do
			if gg.id == genChoice then
				g = gg
			end
		end
		genBtn.Text = g and ("General: " .. g.name .. " (nível " .. g.level .. ")") or "General: nenhum (toque para trocar)"
	end
	for _, p in { 0.1, 0.25, 0.5, 0.75 } do
		pctBtns[p] = button(pctRow, math.floor(p * 100) .. "%", DARK2, { Size = UDim2.fromOffset(62, 28) }, function()
			pct = p
			refreshForm()
		end)
	end
	amountLbl = label(right, { Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 0, 20), TextSize = 13, Font = Enum.Font.GothamMedium })
	genBtn = button(right, "", DARK2, { Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Left }, function()
		-- alterna entre generais livres
		local civ = ctx.civ()
		if not civ then
			return
		end
		local busy = {}
		for _, a in civ.armies do
			if a.gen then
				busy[a.gen] = true
			end
		end
		local free = { false }
		for _, g in civ.generals do
			if not busy[g.id] then
				free[#free + 1] = g.id
			end
		end
		local idx = table.find(free, genChoice or false) or 1
		local nxt = free[idx % #free + 1]
		genChoice = nxt or nil
		refreshForm()
	end)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10) }, genBtn)
	formBtn = button(right, "FORMAR EXÉRCITO", GOLD, { Position = UDim2.fromOffset(0, 120), Size = UDim2.new(1, 0, 0, 36), TextSize = 15 }, function()
		local me = ctx.me()
		ctx.send("army_create", { troops = math.floor((me and me.troops or 0) * pct), gen = genChoice })
		genChoice = nil
	end)
	label(right, { Position = UDim2.fromOffset(0, 168), Size = UDim2.new(1, 0, 0, 20), Text = "GENERAIS", TextColor3 = GOLD, TextSize = 13 })
	local glist = scroll(right, { Position = UDim2.fromOffset(0, 192), Size = UDim2.new(1, 0, 1, -236) })
	button(right, "Recrutar general (" .. D.GENERAL_COST .. " de ouro)", DARK2, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 34) }, function()
		ctx.send("recruit_general", {})
	end)

	local function traitOf(key)
		for _, t in D.TRAITS do
			if t.key == key then
				return t
			end
		end
	end

	local panel = { frame = w }
	function panel.refresh()
		local civ = ctx.civ()
		if not civ then
			return
		end
		sub.Text = "Forme exércitos com parte das tropas, escolha um general e mande atacar. Cada célula tomada dá experiência ao general."
		refreshForm()
		clear(list)
		local gens = {}
		for _, g in civ.generals do
			gens[g.id] = g
		end
		if #civ.armies == 0 then
			label(list, { Size = UDim2.new(1, 0, 0, 40), TextColor3 = MUTED, TextWrapped = true, Font = Enum.Font.GothamMedium, Text = "Nenhum exército. Forme um ao lado." })
		end
		for i, a in civ.armies do
			local r = new("Frame", { Size = UDim2.new(1, 0, 0, 74), BackgroundColor3 = ROW, LayoutOrder = i }, list)
			corner(r, 8)
			local g = a.gen and gens[a.gen]
			label(r, { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 18), Text = a.name .. "  ·  " .. ctx.fmt(a.troops) .. " tropas" })
			label(r, {
				Position = UDim2.fromOffset(10, 26),
				Size = UDim2.new(1, -20, 0, 16),
				TextSize = 12,
				Font = Enum.Font.GothamMedium,
				TextColor3 = MUTED,
				Text = (g and (g.name .. " · " .. (traitOf(g.trait) or {}).name .. " · nível " .. g.level) or "Sem general") .. "  ·  " .. a.tiles .. " células tomadas",
			})
			label(r, { Position = UDim2.fromOffset(10, 48), Size = UDim2.fromOffset(110, 18), TextSize = 12, Text = a.busy and "⚔ Em combate" or "✓ Pronto", TextColor3 = a.busy and RED or GREEN })
			button(r, "Enviar", GOLD, { Position = UDim2.new(1, -236, 0, 44), Size = UDim2.fromOffset(72, 24) }, function()
				if a.busy then
					ctx.toast("Esse exército já está em combate", "error")
					return
				end
				w.Visible = false
				ctx.setArmyMode(a.id, a.name)
			end)
			button(r, "+25%", DARK2, { Position = UDim2.new(1, -158, 0, 44), Size = UDim2.fromOffset(64, 24) }, function()
				local me = ctx.me()
				ctx.send("army_reinforce", { army = a.id, troops = math.floor((me and me.troops or 0) * 0.25) })
			end)
			button(r, "Desfazer", DARK2, { Position = UDim2.new(1, -88, 0, 44), Size = UDim2.fromOffset(78, 24) }, function()
				ctx.send("army_disband", { army = a.id })
			end)
		end
		clear(glist)
		for i, g in civ.generals do
			local t = traitOf(g.trait) or { name = "?", desc = "" }
			local r = new("Frame", { Size = UDim2.new(1, 0, 0, 54), BackgroundColor3 = ROW, LayoutOrder = i }, glist)
			corner(r, 8)
			label(r, { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 18), Text = g.name .. "  ·  nível " .. g.level })
			label(r, { Position = UDim2.fromOffset(10, 22), Size = UDim2.new(1, -20, 0, 14), TextSize = 12, Font = Enum.Font.GothamMedium, TextColor3 = MUTED, Text = t.name .. ": " .. t.desc })
			bar(r, { Position = UDim2.fromOffset(10, 42), Size = UDim2.new(1, -20, 0, 5) }, g.xp / (D.GENERAL_LEVEL_XP * g.level), GOLD)
		end
	end
	return panel
end

---------------------------------------------------------------- DIPLOMACIA
local KIND_NAME = { trade = "rota de comércio", nap = "pacto de não-agressão", alliance = "aliança", aid = "ajuda financeira" }
local function diplomacyPanel(ctx)
	local w, body, sub = window(ctx, "🤝 Diplomacia")
	local props = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, body)
	new("UIListLayout", { Padding = UDim.new(0, 4) }, props)
	local main = new("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1 }, body)
	local left = new("Frame", { Size = UDim2.new(0.42, -8, 1, 0), BackgroundTransparency = 1 }, main)
	local right = new("Frame", { Position = UDim2.new(0.42, 8, 0, 0), Size = UDim2.new(0.58, -8, 1, 0), BackgroundTransparency = 1 }, main)
	local search = new("TextBox", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = DARK2, BorderSizePixel = 0, Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = TEXT, PlaceholderText = "Buscar país...", PlaceholderColor3 = MUTED, Text = "", ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left }, left)
	corner(search, 7)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10) }, search)
	local list = scroll(left, { Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 1, -36) })
	local selected
	local panel = { frame = w }

	local function rel(civ, id)
		return civ.rel[tostring(id)] or 0
	end

	local detail = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, right)
	local function showDetail()
		clear(detail)
		local civ = ctx.civ()
		local n = selected and ctx.nationsById()[selected]
		if not civ or not n then
			label(detail, { Size = UDim2.new(1, 0, 0, 40), TextColor3 = MUTED, TextWrapped = true, Font = Enum.Font.GothamMedium, Text = "Escolha um país na lista ou clique com o botão direito num país do mapa." })
			return
		end
		local r = rel(civ, n.i)
		local p = civ.pacts[tostring(n.i)] or {}
		new("Frame", { Position = UDim2.fromOffset(0, 4), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = n.c, BorderSizePixel = 0 }, detail)
		label(detail, { Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -26, 0, 26), TextSize = 20, Font = Enum.Font.GothamBlack, Text = n.n .. ((n.u or 0) > 0 and " (jogador)" or "") })
		label(detail, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, Font = Enum.Font.GothamMedium, TextColor3 = MUTED, Text = string.format("Terra %s  ·  Tropas %s", string.format("%.1f%%", n.t / math.max(1, ctx.land()) * 100), ctx.fmt(n.tr)) })
		label(detail, { Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, Text = "Relação: " .. r, TextColor3 = r >= 0 and GREEN or RED })
		bar(detail, { Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 0, 8) }, (r + 100) / 200, r >= 0 and GREEN or RED)
		local tags = {}
		if p.alliance then
			tags[#tags + 1] = "🤝 Aliados"
		end
		if p.nap then
			tags[#tags + 1] = "🕊 Não-agressão (" .. p.nap .. " s)"
		end
		if p.trade then
			tags[#tags + 1] = "💰 Rota de comércio"
		end
		label(detail, { Position = UDim2.fromOffset(0, 92), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = GOLD, Text = #tags > 0 and table.concat(tags, "   ") or "Sem acordos" })
		local grid = new("Frame", { Position = UDim2.fromOffset(0, 122), Size = UDim2.new(1, 0, 0, 200), BackgroundTransparency = 1 }, detail)
		new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 40), CellPadding = UDim2.fromOffset(8, 8) }, grid)
		local function act(text, kind, color)
			button(grid, text, color, {}, function()
				ctx.send("dip", { target = n.i, kind = kind })
			end)
		end
		act("💰 Propor comércio", "trade", GOLD)
		act("🕊 Não-agressão", "nap", DARK2)
		act("🤝 Propor aliança", "alliance", DARK2)
		act("🪙 Pedir dinheiro", "aid", DARK2)
		act("🎁 Enviar 5.000 de ouro", "gift", DARK2)
		if p.trade then
			act("✂ Cancelar comércio", "cancel_trade", DARK2)
		end
		act("⚔ Declarar guerra", "war", RED)
		button(detail, "Ver no mapa", DARK2, { Position = UDim2.fromOffset(0, 340), Size = UDim2.fromOffset(140, 32) }, function()
			ctx.focusNation(n.i)
		end)
		-- rota com esse país
		for _, rt in civ.routes do
			if rt.other == n.i then
				button(detail, rt.kind == "train" and "🚂 Mostrar a rota de trem" or "⛵ Rota por navio (sem trilho)", DARK2, { Position = UDim2.fromOffset(150, 340), Size = UDim2.fromOffset(240, 32) }, function()
					ctx.showRoute(rt)
				end)
			end
		end
		label(detail, {
			Position = UDim2.fromOffset(0, 384),
			Size = UDim2.new(1, 0, 0, 60),
			TextSize = 12,
			Font = Enum.Font.GothamMedium,
			TextColor3 = MUTED,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = "Comércio: comboios levam ouro para os dois países. Se houver caminho por terra vira trem com trilhos (rota aparece no mapa); senão vai de navio. Bots aceitam conforme a relação e o regime.",
		})
	end

	function panel.select(id)
		selected = id
		showDetail()
	end

	function panel.refresh()
		local civ = ctx.civ()
		if not civ then
			return
		end
		sub.Text = "Selecione um país (ou clique com o botão direito no mapa). Relações dependem do regime, comércio e guerras."
		-- propostas recebidas
		clear(props)
		local ph = 0
		for _, pr in civ.proposals do
			local from = ctx.nationsById()[pr.from]
			local r = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Color3.fromRGB(50, 44, 20) }, props)
			corner(r, 8)
			label(r, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -200, 1, 0), TextSize = 13, Text = string.format("📨 %s propõe %s (%d s)", from and from.n or "?", KIND_NAME[pr.kind] or pr.kind, pr.left) })
			button(r, "Aceitar", GREEN, { Position = UDim2.new(1, -186, 0, 4), Size = UDim2.fromOffset(84, 26) }, function()
				ctx.send("answer", { id = pr.id, accept = true })
			end)
			button(r, "Recusar", DARK2, { Position = UDim2.new(1, -96, 0, 4), Size = UDim2.fromOffset(84, 26) }, function()
				ctx.send("answer", { id = pr.id, accept = false })
			end)
			ph += 38
		end
		main.Position = UDim2.fromOffset(0, ph)
		main.Size = UDim2.new(1, 0, 1, -ph)
		-- lista de países
		clear(list)
		local q = string.lower(search.Text)
		local items = {}
		for _, n in ctx.nations() do
			local me = ctx.me()
			if (not me or n.i ~= me.id) and (q == "" or string.find(string.lower(n.n), q, 1, true)) then
				items[#items + 1] = n
			end
		end
		table.sort(items, function(a, b)
			local pa, pb = civ.pacts[tostring(a.i)] and 1 or 0, civ.pacts[tostring(b.i)] and 1 or 0
			if pa ~= pb then
				return pa > pb
			end
			return a.t > b.t
		end)
		for i, n in items do
			if i > 80 then
				break
			end
			local r = rel(civ, n.i)
			local row = button(list, "", n.i == selected and DARK2 or ROW, { Size = UDim2.new(1, 0, 0, 28), LayoutOrder = i }, function()
				panel.select(n.i)
			end)
			new("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = n.c, BorderSizePixel = 0 }, row)
			local p = civ.pacts[tostring(n.i)]
			local badge = p and ((p.alliance and "🤝") or (p.nap and "🕊") or "") .. (p.trade and "💰" or "") or ""
			label(row, { Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -90, 1, 0), TextSize = 13, Text = n.n .. " " .. badge })
			label(row, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.fromOffset(50, 28), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Text = (r > 0 and "+" or "") .. r, TextColor3 = r >= 0 and GREEN or RED })
		end
		showDetail()
	end
	search:GetPropertyChangedSignal("Text"):Connect(function()
		panel.refresh()
	end)
	return panel
end

---------------------------------------------------------------- HABILIDADES
local function skillsPanel(ctx)
	local w, body, sub = window(ctx, "🌳 Pesquisa — Raízes da Doutrina")
	local tabs = new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1 }, body)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, tabs)
	-- área das raízes (fundo de terra)
	local soil = new("Frame", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -146), BackgroundColor3 = Color3.fromRGB(34, 28, 24), ClipsDescendants = true }, body)
	corner(soil, 10)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(70, 56, 40), Color3.fromRGB(24, 20, 18)) }, soil)
	local info = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 98), BackgroundColor3 = ROW }, body)
	corner(info, 10)
	local infoName = label(info, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -180, 0, 22), TextSize = 17, Font = Enum.Font.GothamBlack, Text = "Escolha uma raiz" })
	local infoDesc = label(info, { Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -180, 0, 64), TextSize = 12, Font = Enum.Font.GothamMedium, TextColor3 = TEXT, TextWrapped = true, RichText = true, TextYAlignment = Enum.TextYAlignment.Top, Text = "" })
	local selected
	local resBtn = button(info, "PESQUISAR", GOLD, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(150, 44), TextSize = 15 }, function()
		if selected then
			ctx.send("research", { id = selected })
		end
	end)
	local tree = nil
	local panel = { frame = w }
	local tabBtns = {}

	local function findTree(key)
		for _, t in D.TREES do
			if t.key == key then
				return t
			end
		end
	end
	-- ramos bloqueados para a nação (seguiu a raiz oposta)
	local function blockedBy(own, T, bi)
		for id in own do
			local sk = D.SKILLS[id]
			if sk.tree == T.key and (D.opposite(sk.branch) == bi or D.opposite(bi) == sk.branch) then
				return T.branches[sk.branch].name
			end
		end
		return nil
	end

	local function drawInfo(civ)
		local sk = selected and D.SKILLS[selected]
		if not sk then
			return
		end
		local own = {}
		for _, s in civ.skills do
			own[s] = true
		end
		local T = findTree(sk.tree)
		local cost = math.floor(sk.cost * (sk.tree == civ.gov and 1 or 1.5))
		local reqs = {}
		for _, r in sk.req do
			reqs[#reqs + 1] = (own[r] and "✓ " or "✗ ") .. D.SKILLS[r].name
		end
		local opp = T.branches[D.opposite(sk.branch)].name
		local blk = blockedBy(own, T, sk.branch)
		infoName.Text = sk.name .. "  ·  " .. cost .. " pontos"
		infoDesc.Text = string.format(
			'<font color="#5ADC78">Ganha: %s</font>\n<font color="#F05A5A">Perde: %s</font>\n<font color="#8c94aa">%s%s</font>',
			sk.desc,
			sk.badDesc ~= "" and sk.badDesc or "nada",
			blk and ("BLOQUEADA: você seguiu a raiz " .. blk .. ". ") or ("Seguir esta raiz bloqueia a raiz " .. opp .. ". "),
			#reqs > 0 and ("Requer: " .. table.concat(reqs, ", ")) or ""
		)
		resBtn.Text = own[selected] and "PESQUISADA" or (blk and "BLOQUEADA" or "PESQUISAR")
		resBtn.BackgroundColor3 = (own[selected] or blk) and DARK2 or GOLD
	end

	-- linha entre dois pontos (em pixels dentro do solo)
	local function line(x1, y1, x2, y2, color, thick)
		local dx, dy = x2 - x1, y2 - y1
		local len = math.sqrt(dx * dx + dy * dy)
		local f = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2),
			Size = UDim2.fromOffset(len, thick),
			Rotation = math.deg(math.atan2(dy, dx)),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		}, soil)
		corner(f, 4)
		return f
	end

	function panel.refresh()
		local civ = ctx.civ()
		if not civ then
			return
		end
		tree = tree or civ.gov
		sub.Text = string.format("Pontos de pesquisa: %d  ·  Regime: %s (outras doutrinas custam 1,5x)  ·  Cada raiz dá bônus mas cobra um preço", civ.rp, D.GOVS[civ.gov].name)
		for k, b in tabBtns do
			b.BackgroundColor3 = k == tree and GOLD or DARK2
			b.TextColor3 = k == tree and Color3.fromRGB(25, 25, 30) or TEXT
		end
		clear(soil)
		local own = {}
		for _, s in civ.skills do
			own[s] = true
		end
		local T = findTree(tree)
		local W, H = soil.AbsoluteSize.X, soil.AbsoluteSize.Y
		if W < 10 then
			W, H = 744, 300
		end
		local NW, NH = 118, 38
		local cols = #T.branches
		local function pos(bi, lvl)
			-- raízes se abrem para os lados conforme descem
			local spread = (bi - (cols + 1) / 2) * (W / cols)
			local x = W / 2 + spread * (0.55 + lvl * 0.09)
			local y = 58 + (lvl - 1) * ((H - 58 - NH / 2 - 6) / 4.4)
			return x, y
		end
		-- tronco
		local trunkX, trunkY = W / 2, 18
		local trunk = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(trunkX, trunkY), Size = UDim2.fromOffset(200, 28), BackgroundColor3 = Color3.fromRGB(110, 80, 50), ZIndex = 3 }, soil)
		corner(trunk, 14)
		label(trunk, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 13, Font = Enum.Font.GothamBlack, Text = "🌳 " .. D.TRUNK[T.key], ZIndex = 4 })
		local ROOT = Color3.fromRGB(150, 110, 70)
		for bi, br in T.branches do
			local blk = blockedBy(own, T, bi)
			local hx, hy = pos(bi, 0.35)
			line(trunkX, trunkY + 12, hx, hy, blk and Color3.fromRGB(70, 50, 40) or ROOT, 6)
			label(soil, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(hx, hy - 2), Size = UDim2.fromOffset(NW + 10, 14), TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = blk and RED or GOLD, Text = blk and ("✗ " .. string.upper(br.name)) or string.upper(br.name), ZIndex = 3 })
			local px, py = hx, hy
			for lvl, id in br.skills do
				local sk = D.SKILLS[id]
				local x, y = pos(bi, lvl)
				local avail = not blk
				for _, r in sk.req do
					if not own[r] then
						avail = false
					end
				end
				line(px, py + 6, x, y, own[id] and Color3.fromRGB(110, 200, 110) or (blk and Color3.fromRGB(70, 50, 40) or ROOT), own[id] and 5 or 4)
				-- elo cruzado (nível 4 exige o nível 2 da raiz vizinha)
				if lvl == 4 then
					local nx, ny = pos(bi % cols + 1, 2)
					local cl = line(x, y, nx, ny, Color3.fromRGB(120, 100, 80), 2)
					cl.BackgroundTransparency = 0.5
				end
				px, py = x, y
				local cost = math.floor(sk.cost * (sk.tree == civ.gov and 1 or 1.5))
				local color = own[id] and Color3.fromRGB(46, 120, 70)
					or (blk and Color3.fromRGB(60, 34, 34))
					or (avail and (civ.rp >= cost and Color3.fromRGB(150, 120, 30) or Color3.fromRGB(80, 70, 40)))
					or Color3.fromRGB(48, 42, 38)
				local b = button(soil, "", color, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(NW, NH), ZIndex = 4 }, function()
					selected = id
					panel.refresh()
				end)
				if selected == id then
					new("UIStroke", { Color = GOLD, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
				end
				label(b, { Position = UDim2.fromOffset(6, 2), Size = UDim2.new(1, -12, 0, 20), TextSize = 11, TextWrapped = true, Text = sk.name, TextColor3 = (own[id] or avail) and TEXT or MUTED, ZIndex = 5 })
				label(b, { Position = UDim2.new(0, 6, 1, -15), Size = UDim2.new(1, -12, 0, 13), TextSize = 10, Font = Enum.Font.GothamMedium, TextColor3 = own[id] and GREEN or (blk and RED or MUTED), Text = own[id] and "✓ pesquisada" or (blk and "bloqueada" or (cost .. " pts")), ZIndex = 5 })
			end
		end
		drawInfo(civ)
	end
	for _, t in D.TREES do
		local col = D.GOVS[t.key].color
		tabBtns[t.key] = button(tabs, "    " .. t.name, DARK2, { Size = UDim2.fromOffset(170, 32) }, function()
			tree = t.key
			selected = nil
			panel.refresh()
		end)
		local dot = new("Frame", { Position = UDim2.fromOffset(12, 11), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = Color3.fromRGB(col[1], col[2], col[3]), BorderSizePixel = 0 }, tabBtns[t.key])
		corner(dot, 5)
	end
	return panel
end

---------------------------------------------------------------- MERCADO
local function marketPanel(ctx)
	local w, body, sub = window(ctx, "📈 Mercado Mundial")
	local tbl = new("Frame", { Size = UDim2.new(1, 0, 0, 160), BackgroundTransparency = 1 }, body)
	local form = new("Frame", { Position = UDim2.fromOffset(0, 168), Size = UDim2.new(0.45, -8, 1, -168), BackgroundColor3 = ROW }, body)
	corner(form, 10)
	local offersF = new("Frame", { Position = UDim2.new(0.45, 8, 0, 168), Size = UDim2.new(0.55, -8, 1, -168), BackgroundTransparency = 1 }, body)
	local res, pct = "food", 0.25
	local resBtns, pctBtns = {}, {}
	label(form, { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 18), Text = "VENDER PARA O EXTERIOR", TextColor3 = GOLD, TextSize = 13 })
	local resRow = new("Frame", { Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 28), BackgroundTransparency = 1 }, form)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }, resRow)
	local pctRow = new("Frame", { Position = UDim2.fromOffset(12, 64), Size = UDim2.new(1, -24, 0, 28), BackgroundTransparency = 1 }, form)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }, pctRow)
	local amountLbl = label(form, { Position = UDim2.fromOffset(12, 98), Size = UDim2.new(1, -24, 0, 18), TextSize = 13, Font = Enum.Font.GothamMedium })
	label(form, { Position = UDim2.fromOffset(12, 122), Size = UDim2.fromOffset(120, 28), TextSize = 13, Text = "Preço por unidade:" })
	local priceBox = new("TextBox", { Position = UDim2.fromOffset(140, 122), Size = UDim2.new(1, -152, 0, 28), BackgroundColor3 = DARK2, BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = GOLD, Text = "", ClearTextOnFocus = false }, form)
	corner(priceBox, 6)
	local warn = label(form, { Position = UDim2.fromOffset(12, 158), Size = UDim2.new(1, -24, 0, 34), TextSize = 11, Font = Enum.Font.GothamMedium, TextColor3 = MUTED, TextWrapped = true, Text = "" })
	local panel = { frame = w }
	local function refreshForm()
		local civ = ctx.civ()
		if not civ then
			return
		end
		for k, b in resBtns do
			b.BackgroundColor3 = k == res and GOLD or DARK2
			b.TextColor3 = k == res and Color3.fromRGB(25, 25, 30) or TEXT
		end
		for p, b in pctBtns do
			b.BackgroundColor3 = p == pct and GOLD or DARK2
			b.TextColor3 = p == pct and Color3.fromRGB(25, 25, 30) or TEXT
		end
		local stock = civ.stock[res] or 0
		amountLbl.Text = string.format("Quantidade: %s de %s (estoque %s)", ctx.fmt(stock * pct), D.RES[res].name, ctx.fmt(stock))
		if priceBox:IsFocused() == false and (priceBox.Text == "" or priceBox:GetAttribute("res") ~= res) then
			priceBox.Text = tostring(civ.market.ref[res])
			priceBox:SetAttribute("res", res)
		end
		local net = (civ.prod[res] or 0) - (civ.need[res] or 0)
		warn.Text = net < 0 and "⚠ Seu país consome mais do que produz disso. Vender agora pode gerar falta e revolta!"
			or "O mercado externo e os outros países decidem se compram: preço acima da referência vende devagar."
		warn.TextColor3 = net < 0 and RED or MUTED
	end
	for _, r in D.RESOURCES do
		resBtns[r] = button(resRow, D.RES[r].name, DARK2, { Size = UDim2.fromOffset(62, 28), TextSize = 11 }, function()
			res = r
			refreshForm()
		end)
	end
	for _, p in { 0.1, 0.25, 0.5, 0.9 } do
		pctBtns[p] = button(pctRow, math.floor(p * 100) .. "%", DARK2, { Size = UDim2.fromOffset(62, 28) }, function()
			pct = p
			refreshForm()
		end)
	end
	button(form, "PUBLICAR OFERTA", GOLD, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.new(1, -24, 0, 38), TextSize = 15 }, function()
		local civ = ctx.civ()
		local price = tonumber((string.gsub(priceBox.Text, ",", ".")))
		if not civ or not price then
			ctx.toast("Preço inválido", "error")
			return
		end
		ctx.send("offer", { res = res, amount = math.floor((civ.stock[res] or 0) * pct), price = price })
	end)
	label(offersF, { Size = UDim2.new(1, 0, 0, 18), Text = "OFERTAS DE OUTROS PAÍSES", TextColor3 = GOLD, TextSize = 13 })
	local olist = scroll(offersF, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 1, -22) })

	function panel.refresh()
		local civ = ctx.civ()
		if not civ then
			return
		end
		local fm = table.find(civ.laws, "free_market") ~= nil
		sub.Text = "Livre mercado: " .. (fm and "ATIVO (compra e vende sozinho)" or "inativo (aprove a lei na Política)")
		clear(tbl)
		local head = { "RECURSO", "ESTOQUE", "PRODUZ/s", "CONSOME/s", "SALDO/s", "PREÇO" }
		for i, h in head do
			label(tbl, { Position = UDim2.new((i - 1) / 6, 0, 0, 0), Size = UDim2.new(1 / 6, 0, 0, 18), TextSize = 11, TextColor3 = MUTED, Text = h })
		end
		for ri, r in D.RESOURCES do
			local y = 22 + (ri - 1) * 26
			local net = civ.prod[r] - civ.need[r]
			local vals = {
				D.RES[r].name .. (civ.short[r] and " ⚠" or ""),
				ctx.fmt(civ.stock[r]),
				string.format("%.1f", civ.prod[r]),
				string.format("%.1f", civ.need[r]),
				string.format("%+.1f", net),
				string.format("%.2f", civ.market.ref[r]),
			}
			for i, v in vals do
				label(tbl, {
					Position = UDim2.new((i - 1) / 6, 0, 0, y),
					Size = UDim2.new(1 / 6, 0, 0, 22),
					TextSize = 13,
					Text = v,
					TextColor3 = (i == 1 and civ.short[r] and RED) or (i == 5 and (net >= 0 and GREEN or RED)) or (i == 6 and GOLD) or TEXT,
				})
			end
		end
		refreshForm()
		clear(olist)
		local order = 0
		for _, o in civ.market.mine do
			order += 1
			local row = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(40, 50, 40), LayoutOrder = order }, olist)
			corner(row, 6)
			label(row, { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -100, 1, 0), TextSize = 12, Text = string.format("Sua oferta: %s de %s a %.2f", ctx.fmt(o.amount), D.RES[o.res].name, o.price) })
			button(row, "Cancelar", DARK2, { Position = UDim2.new(1, -88, 0, 3), Size = UDim2.fromOffset(82, 24), TextSize = 12 }, function()
				ctx.send("cancel_offer", { id = o.id })
			end)
		end
		local byId = ctx.nationsById()
		for _, o in civ.market.offers do
			order += 1
			local s = byId[o.seller]
			local row = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = ROW, LayoutOrder = order }, olist)
			corner(row, 6)
			local cheap = o.price <= civ.market.ref[o.res]
			label(row, { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -170, 1, 0), TextSize = 12, Text = string.format("%s: %s de %s a %.2f", s and s.n or "?", ctx.fmt(o.amount), D.RES[o.res].name, o.price), TextColor3 = cheap and GREEN or TEXT })
			button(row, "25%", DARK2, { Position = UDim2.new(1, -160, 0, 3), Size = UDim2.fromOffset(60, 24), TextSize = 12 }, function()
				ctx.send("buy", { id = o.id, amount = math.max(1, math.floor(o.amount * 0.25)) })
			end)
			button(row, "Tudo", GOLD, { Position = UDim2.new(1, -94, 0, 3), Size = UDim2.fromOffset(88, 24), TextSize = 12 }, function()
				ctx.send("buy", { id = o.id, amount = o.amount })
			end)
		end
	end
	return panel
end

---------------------------------------------------------------- POLÍTICA
local function politicsPanel(ctx)
	local w, body, sub = window(ctx, "🏛 Política e Leis")
	local left = new("Frame", { Size = UDim2.new(0.42, -8, 1, 0), BackgroundTransparency = 1 }, body)
	local right = new("Frame", { Position = UDim2.new(0.42, 8, 0, 0), Size = UDim2.new(0.58, -8, 1, 0), BackgroundTransparency = 1 }, body)
	local govBox = new("Frame", { Size = UDim2.new(1, 0, 0, 150), BackgroundColor3 = ROW }, left)
	corner(govBox, 10)
	local happyBox = scroll(left, { Position = UDim2.fromOffset(0, 158), Size = UDim2.new(1, 0, 1, -158) })
	label(right, { Size = UDim2.new(1, 0, 0, 18), Text = "LEIS", TextColor3 = GOLD, TextSize = 13 })
	local laws = scroll(right, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0.5, -26) })
	local parl = new("Frame", { Position = UDim2.new(0, 0, 0.5, 4), Size = UDim2.new(1, 0, 0.5, -4), BackgroundColor3 = ROW }, right)
	corner(parl, 10)
	local panel = { frame = w }
	function panel.refresh()
		local civ = ctx.civ()
		if not civ then
			return
		end
		local gov = D.GOVS[civ.gov]
		sub.Text = string.format("Influência: %d  ·  Felicidade: %d%s", civ.influence, math.floor(civ.happy), civ.happy < 20 and "  ·  ⚠ RISCO DE REVOLUÇÃO!" or "")
		-- regime
		clear(govBox)
		new("Frame", { Position = UDim2.fromOffset(12, 14), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.fromRGB(gov.color[1], gov.color[2], gov.color[3]), BorderSizePixel = 0 }, govBox)
		label(govBox, { Position = UDim2.fromOffset(32, 8), Size = UDim2.new(1, -44, 0, 26), TextSize = 18, Font = Enum.Font.GothamBlack, Text = gov.name })
		label(govBox, { Position = UDim2.fromOffset(12, 36), Size = UDim2.new(1, -24, 0, 50), TextSize = 12, Font = Enum.Font.GothamMedium, TextColor3 = MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = gov.desc .. " Aprovação: " .. math.floor(gov.threshold * 100) .. "% da câmara." })
		local x = 12
		for _, g in D.GOV_ORDER do
			if g ~= civ.gov then
				button(govBox, "Mudar p/ " .. D.GOVS[g].name, DARK2, { Position = UDim2.fromOffset(x, 100), Size = UDim2.fromOffset(140, 36), TextSize = 11 }, function()
					ctx.send("regime", { gov = g })
				end)
				x += 148
			end
		end
		-- felicidade
		clear(happyBox)
		label(happyBox, { Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = GOLD, Text = string.format("FELICIDADE %d → %d", math.floor(civ.happy), math.floor(civ.happyTarget)), LayoutOrder = 0 })
		for i, p in civ.happyParts or {} do
			label(happyBox, { Size = UDim2.new(1, 0, 0, 18), TextSize = 12, Font = Enum.Font.GothamMedium, LayoutOrder = i, Text = string.format("%s  %+d", p[1], math.floor(p[2])), TextColor3 = p[2] >= 0 and GREEN or RED })
		end
		label(happyBox, { Size = UDim2.new(1, 0, 0, 34), TextSize = 11, Font = Enum.Font.GothamMedium, LayoutOrder = 99, TextWrapped = true, TextColor3 = MUTED, Text = "Abaixo de 20 o povo pode fazer uma revolução e trocar o regime (a Lei Marcial impede)." })
		-- leis
		clear(laws)
		local active = {}
		for _, l in civ.laws do
			active[l] = true
		end
		for i, law in D.LAWS do
			local allowed = law.govs == nil or law.govs[civ.gov]
			local row = new("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = active[law.id] and Color3.fromRGB(36, 64, 44) or ROW, LayoutOrder = i }, laws)
			corner(row, 6)
			label(row, { Position = UDim2.fromOffset(8, 3), Size = UDim2.new(1, -110, 0, 18), TextSize = 13, Text = law.name .. (active[law.id] and "  ✓" or ""), TextColor3 = allowed and TEXT or MUTED })
			label(row, { Position = UDim2.fromOffset(8, 22), Size = UDim2.new(1, -110, 0, 20), TextSize = 11, Font = Enum.Font.GothamMedium, TextColor3 = MUTED, TextWrapped = true, Text = law.desc .. " · " .. law.cost .. " de ouro" })
			if active[law.id] then
				button(row, "Revogar", DARK2, { Position = UDim2.new(1, -96, 0, 10), Size = UDim2.fromOffset(88, 26), TextSize = 12 }, function()
					ctx.send("law", { law = law.id, repeal = true })
				end)
			elseif allowed then
				button(row, "Propor", GOLD, { Position = UDim2.new(1, -96, 0, 10), Size = UDim2.fromOffset(88, 26), TextSize = 12 }, function()
					ctx.send("law", { law = law.id })
				end)
			else
				label(row, { Position = UDim2.new(1, -100, 0, 10), Size = UDim2.fromOffset(92, 26), TextSize = 10, TextColor3 = MUTED, TextWrapped = true, Text = "não existe neste regime" })
			end
		end
		-- câmara
		clear(parl)
		if not civ.parliament then
			label(parl, { Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -24, 0, 40), TextSize = 13, TextWrapped = true, Font = Enum.Font.GothamMedium, TextColor3 = MUTED, Text = "Proponha uma lei para a câmara votar." })
			return
		end
		local bill = civ.bill and D.LAW_BY_ID[civ.bill.law]
		label(parl, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -150, 0, 20), TextSize = 13, TextColor3 = GOLD, Text = bill and ("VOTAÇÃO: " .. (civ.bill.repeal and "revogar " or "") .. bill.name) or "CÂMARA (sem votação)" })
		local yes = 0
		for i, p in civ.parliament do
			local y = 30 + (i - 1) * 34
			local amb = D.AMBITIONS[p.amb]
			label(parl, { Position = UDim2.fromOffset(12, y), Size = UDim2.new(0.42, 0, 0, 16), TextSize = 12, Text = string.format("%s (%d)", p.name, p.seats) })
			label(parl, { Position = UDim2.fromOffset(12, y + 15), Size = UDim2.new(0.42, 0, 0, 14), TextSize = 10, Font = Enum.Font.GothamMedium, TextColor3 = MUTED, Text = "Ambição: " .. amb.name })
			if p.sup then
				if p.sup > 0 then
					yes += p.seats
				end
				bar(parl, { Position = UDim2.new(0.44, 0, 0, y + 8), Size = UDim2.new(0.18, 0, 0, 8) }, (p.sup + 1) / 2, p.sup > 0 and GREEN or RED)
				button(parl, "Convencer", DARK2, { Position = UDim2.new(0.64, 0, 0, y + 2), Size = UDim2.new(0.17, -4, 0, 26), TextSize = 11 }, function()
					ctx.send("lobby", { party = i, how = "persuade" })
				end)
				button(parl, "Propina", Color3.fromRGB(110, 80, 20), { Position = UDim2.new(0.82, 0, 0, y + 2), Size = UDim2.new(0.17, -8, 0, 26), TextSize = 11 }, function()
					ctx.send("lobby", { party = i, how = "bribe" })
				end)
			end
		end
		if bill then
			local need = math.floor(gov.threshold * 100) + 1
			button(parl, string.format("VOTAR (%d/%d)", yes, need), yes >= need and GREEN or GOLD, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 4), Size = UDim2.fromOffset(130, 24), TextSize = 12 }, function()
				ctx.send("vote", {})
			end)
		end
	end
	return panel
end

function Panels.new(ctx)
	local all = {
		armies = armiesPanel(ctx),
		diplomacy = diplomacyPanel(ctx),
		skills = skillsPanel(ctx),
		market = marketPanel(ctx),
		politics = politicsPanel(ctx),
	}
	local api = { all = all }
	function api.open(name)
		for k, p in all do
			p.frame.Visible = k == name and not p.frame.Visible
		end
		if all[name].frame.Visible then
			all[name].refresh()
		end
	end
	function api.show(name)
		for k, p in all do
			p.frame.Visible = k == name
		end
		all[name].refresh()
	end
	function api.refresh()
		for _, p in all do
			if p.frame.Visible then
				p.refresh()
			end
		end
	end
	function api.closeAll()
		for _, p in all do
			p.frame.Visible = false
		end
	end
	function api.anyOpen()
		for _, p in all do
			if p.frame.Visible then
				return true
			end
		end
		return false
	end
	api.diplomacy = all.diplomacy
	return api
end

return Panels
