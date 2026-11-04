--!nocheck
-- Desenha o mapa em EditableImages (3x3 pixels por célula), divididas em faixas verticais
-- de até 1024 px (limite do Roblox). Só as faixas de linhas que mudaram são reenviadas.
-- A mesma imagem pode aparecer em várias cópias (o mapa dá a volta na horizontal).
-- Sem permissão de EditableImage, cai para um plano B com Frames por linha.
local AssetService = game:GetService("AssetService")

local MapView = {}
MapView.__index = MapView

local NEUTRAL = { 232, 221, 192 }
MapView.DEEP = { 44, 104, 168 } -- igual ao fundo da tela: sem "corte" na borda do mapa
local DEEP = MapView.DEEP
local DEPTH_MAX = 7

local function clamp255(v)
	v = math.floor(v + 0.5)
	return if v < 0 then 0 elseif v > 255 then 255 else v
end

local function pack(r, g, b)
	return clamp255(r) + clamp255(g) * 256 + clamp255(b) * 65536 + 4278190080
end

function MapView.new(geo, cfg, parent)
	local self = setmetatable({}, MapView)
	self.geo = geo
	self.W, self.H = geo.W, geo.H
	self.S = cfg.PIXELS_PER_TILE
	self.PH = self.H * self.S
	self.owner = table.create(self.W * self.H, 0)
	self.colors = {}
	self.dirty = {}
	self.anyDirty = false
	self.rails = {} -- [célula] = true
	self.flash = {} -- [célula] = os.clock() da conquista (brilho rápido)
	self.flashQ = {}
	self.listeners = {} -- funções chamadas com (célula) quando ela muda (visão detalhada)

	local n = self.W * self.H
	self.shade = table.create(n, 1)
	self.depth = table.create(n, 99)
	for t = 1, n do
		local x, y = geo:xy(t)
		local h = math.sin(x * 12.9898 + y * 78.233) * 43758.5453
		self.shade[t] = 0.96 + (h - math.floor(h)) * 0.06
	end
	local q, head = {}, 1
	for t = 1, n do
		if geo.land[t] then
			self.depth[t] = 0
			q[#q + 1] = t
		end
	end
	while head <= #q do
		local c = q[head]
		head += 1
		local d = self.depth[c] + 1
		if d <= DEPTH_MAX then
			for _, nb in geo:around(c) do
				if self.depth[nb] > d then
					self.depth[nb] = d
					q[#q + 1] = nb
				end
			end
		end
	end

	-- faixas verticais (chunks) de até 1024 px de largura
	self.CW = math.floor(1024 / self.S)
	self.chunks = {}
	local ok = true
	local x0 = 0
	while x0 < self.W do
		local cols = math.min(self.CW, self.W - x0)
		local ch = { x0 = x0, cols = cols, PW = cols * self.S }
		ch.buf = buffer.create(ch.PW * self.PH * 4)
		local okc, img = pcall(function()
			return AssetService:CreateEditableImage({ Size = Vector2.new(ch.PW, self.PH) })
		end)
		if not okc or not img then
			warn("[MapView] EditableImage indisponível, usando modo compatível:", img)
			ok = false
			break
		end
		ch.img = img
		ch.content = Content.fromObject(img)
		self.chunks[#self.chunks + 1] = ch
		x0 += cols
	end
	self.useImages = ok
	if not ok then
		for _, ch in self.chunks do
			ch.img:Destroy()
		end
		self.chunks = {}
		self.rows = {}
	end
	self.attached = {}
	self:attach(parent)
	-- o desenho completo acontece em loadOwners (quando chega o mapa do servidor)
	return self
end

-- mostra o mapa dentro de "parent" (pode ser chamado mais de uma vez para cópias)
function MapView:attach(parent)
	if self.useImages then
		for _, ch in self.chunks do
			local label = Instance.new("ImageLabel")
			label.Name = "MapChunk"
			label.BackgroundTransparency = 1
			label.BorderSizePixel = 0
			label.Position = UDim2.fromScale(ch.x0 / self.W, 0)
			label.Size = UDim2.fromScale(ch.cols / self.W, 1)
			label.ResampleMode = Enum.ResamplerMode.Pixelated
			label.ImageContent = ch.content
			label.Parent = parent
			self.attached[#self.attached + 1] = { label = label, chunk = ch }
		end
		return true
	end
	if self.holder then
		return false -- plano B não tem cópias
	end
	local holder = Instance.new("Frame")
	holder.Name = "MapRows"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = parent
	self.holder = holder
	return true
end

function MapView:tileColor(t)
	local o = self.owner[t]
	local s = self.shade[t]
	if o == 0 then
		local cid = self.geo.country and self.geo.country[t] or 0
		local k = s * (0.94 + ((cid * 37) % 7) * 0.012)
		return NEUTRAL[1] * k, NEUTRAL[2] * k, NEUTRAL[3] * k
	end
	local c = self.colors[o] or NEUTRAL
	return (NEUTRAL[1] + (c[1] - NEUTRAL[1]) * 0.55) * s, (NEUTRAL[2] + (c[2] - NEUTRAL[2]) * 0.55) * s, (NEUTRAL[3] + (c[3] - NEUTRAL[3]) * 0.55) * s
end

local DEEP_PACKED = pack(DEEP[1], DEEP[2], DEEP[3])

function MapView:drawTile(t)
	local geo, S = self.geo, self.S
	local x, y = geo:xy(t)
	local ch = self.chunks[x // self.CW + 1]
	local PW, buf = ch.PW, ch.buf
	local base = (y * S * PW + (x - ch.x0) * S) * 4
	if not geo.land[t] then
		local col = DEEP_PACKED -- oceano numa cor só (sem brilho na costa)
		for j = 0, S - 1 do
			local row = base + j * PW * 4
			for i = 0, S - 1 do
				buffer.writeu32(buf, row + i * 4, col)
			end
		end
		return
	end
	local o = self.owner[t]
	local r, g, b = self:tileColor(t)
	local fl = self.flash[t]
	if fl then
		local k = if os.clock() - fl < 0.45 then 1 else 0
		if k > 0 then
			r, g, b = r + (255 - r) * 0.55 * k, g + (255 - g) * 0.55 * k, b + (255 - b) * 0.55 * k
		end
	end
	local inner = pack(r, g, b)
	local W, H = self.W, self.H
	local land, owner, country = geo.land, self.owner, geo.country
	local myCountry = country and country[t]
	local function other(nx, ny)
		if ny < 0 or ny >= H then
			return true, true
		end
		local nb = ny * W + (nx % W) + 1
		if not land[nb] then
			return true, true
		end
		if owner[nb] ~= o then
			return true, false
		end
		if o == 0 and country and country[nb] ~= myCountry then
			return true, false
		end
		return false, false
	end
	local dR = other(x + 1, y)
	local dL, wL = other(x - 1, y)
	local dD = other(x, y + 1)
	local dU, wU = other(x, y - 1)
	local edge
	if o == 0 then
		edge = pack(r * 0.86, g * 0.86, b * 0.86)
		dL = dL and wL
		dU = dU and wU
	else
		local c = self.colors[o] or NEUTRAL
		edge = pack(c[1] * 0.78, c[2] * 0.78, c[3] * 0.78)
	end
	for j = 0, S - 1 do
		local row = base + j * PW * 4
		for i = 0, S - 1 do
			local e = (i == 0 and dL) or (i == S - 1 and dR) or (j == 0 and dU) or (j == S - 1 and dD)
			buffer.writeu32(buf, row + i * 4, e and edge or inner)
		end
	end
	-- trilho: centro + braços só para os vizinhos com trilho (horizontal/vertical)
	if self.rails[t] and S >= 3 then
		local rail = pack(62, 60, 68)
		local mid = S // 2
		local function px(i, j)
			buffer.writeu32(buf, base + (j * PW + i) * 4, rail)
		end
		px(mid, mid)
		local rails = self.rails
		local function has(nx, ny)
			if ny < 0 or ny >= H then
				return false
			end
			return rails[ny * W + (nx % W) + 1] == true
		end
		if has(x - 1, y) then
			for i = 0, mid - 1 do
				px(i, mid)
			end
		end
		if has(x + 1, y) then
			for i = mid + 1, S - 1 do
				px(i, mid)
			end
		end
		if has(x, y - 1) then
			for j = 0, mid - 1 do
				px(mid, j)
			end
		end
		if has(x, y + 1) then
			for j = mid + 1, S - 1 do
				px(mid, j)
			end
		end
	end
end

function MapView:markDirty(t)
	if not self.dirty[t] then
		self.dirty[t] = true
		self.anyDirty = true
	end
end

function MapView:setOwner(t, o)
	if self.owner[t] == o then
		return
	end
	self.owner[t] = o
	-- brilho de conquista
	self.flash[t] = os.clock()
	self.flashQ[#self.flashQ + 1] = t
	for _, f in self.listeners do
		f(t)
	end
	self:markDirty(t)
	for _, nb in self.geo:around(t) do
		self:markDirty(nb)
	end
end

function MapView:addRail(t)
	if self.rails[t] then
		return
	end
	self.rails[t] = true
	self:markDirty(t)
	for _, nb in self.geo:around(t) do
		self:markDirty(nb)
	end
	for _, f in self.listeners do
		f(t)
	end
end

function MapView:setColor(id, rgb)
	local c = self.colors[id]
	if c and c[1] == rgb[1] and c[2] == rgb[2] and c[3] == rgb[3] then
		return false
	end
	self.colors[id] = rgb
	return true
end

function MapView:repaintOwners(set)
	for t = 1, self.W * self.H do
		local o = self.owner[t]
		if o ~= 0 and set[o] then
			self:markDirty(t)
			for _, nb in self.geo:around(t) do
				self:markDirty(nb)
			end
		end
	end
end

function MapView:loadOwners(buf)
	for t = 1, self.W * self.H do
		self.owner[t] = buffer.readu8(buf, t - 1)
	end
	self:redrawAll()
end

function MapView:redrawAll()
	table.clear(self.dirty)
	self.anyDirty = false
	if self.useImages then
		for t = 1, self.W * self.H do
			self:drawTile(t)
		end
		for _, ch in self.chunks do
			ch.img:WritePixelsBuffer(Vector2.zero, Vector2.new(ch.PW, self.PH), ch.buf)
		end
		-- reatribui o conteúdo para garantir que as ImageLabels mostrem a imagem nova
		for _, a in self.attached do
			a.label.ImageContent = Content.fromObject(a.chunk.img)
		end
	else
		for y = 0, self.H - 1 do
			self:buildRow(y)
		end
	end
end

function MapView:buildRow(y)
	local frames = self.rows[y] or {}
	self.rows[y] = frames
	local used = 0
	local W = self.W
	local x = 0
	while x < W do
		local t = y * W + x + 1
		if self.geo.land[t] then
			local o = self.owner[t]
			local cid = self.geo.country and self.geo.country[t] or 0
			local x2 = x
			while x2 + 1 < W do
				local nb = t + (x2 + 1 - x)
				if not self.geo.land[nb] or self.owner[nb] ~= o or (o == 0 and self.geo.country[nb] ~= cid) then
					break
				end
				x2 += 1
			end
			used += 1
			local f = frames[used]
			if not f then
				f = Instance.new("Frame")
				f.BorderSizePixel = 0
				f.Parent = self.holder
				frames[used] = f
			end
			local r, g, b = self:tileColor(t)
			f.BackgroundColor3 = Color3.fromRGB(clamp255(r), clamp255(g), clamp255(b))
			f.Position = UDim2.fromScale(x / W, y / self.H)
			f.Size = UDim2.fromScale((x2 - x + 1) / W, 1 / self.H)
			f.Visible = true
			x = x2 + 1
		else
			x += 1
		end
	end
	for i = used + 1, #frames do
		frames[i].Visible = false
	end
end

function MapView:flush()
	-- células cujo brilho acabou voltam à cor normal
	if #self.flashQ > 0 then
		local now = os.clock()
		local keep = {}
		for _, t in self.flashQ do
			local fl = self.flash[t]
			if fl and now - fl < 0.45 then
				keep[#keep + 1] = t -- ainda brilhando: redesenha só quando acabar (mais leve)
			elseif fl then
				self.flash[t] = nil
				self:markDirty(t)
			end
		end
		self.flashQ = keep
	end
	if not self.anyDirty then
		return
	end
	self.anyDirty = false
	if not self.useImages then
		local rows = {}
		for t in self.dirty do
			local _, y = self.geo:xy(t)
			rows[y] = true
		end
		table.clear(self.dirty)
		for y in rows do
			self:buildRow(y)
		end
		return
	end
	-- por chunk: para cada linha suja, a menor e a maior coluna (local) sujas
	local rowsBy = {}
	for t in self.dirty do
		local x, y = self.geo:xy(t)
		local ci = x // self.CW + 1
		local lx = x - self.chunks[ci].x0
		local rows = rowsBy[ci]
		if not rows then
			rows = {}
			rowsBy[ci] = rows
		end
		local r = rows[y]
		if r then
			if lx < r[1] then
				r[1] = lx
			end
			if lx > r[2] then
				r[2] = lx
			end
		else
			rows[y] = { lx, lx }
		end
		self:drawTile(t)
	end
	table.clear(self.dirty)
	local S = self.S
	for ci, rows in rowsBy do
		local ch = self.chunks[ci]
		local PW = ch.PW
		local y = 0
		while y < self.H do
			local r = rows[y]
			if r then
				-- junta linhas próximas numa faixa e usa o retângulo que cobre todas
				local y2, gap, k = y, 0, y + 1
				local x1, x2 = r[1], r[2]
				while k < self.H and gap <= 3 do
					local rk = rows[k]
					if rk then
						y2 = k
						gap = 0
						if rk[1] < x1 then
							x1 = rk[1]
						end
						if rk[2] > x2 then
							x2 = rk[2]
						end
					else
						gap += 1
					end
					k += 1
				end
				local px, pw = x1 * S, (x2 - x1 + 1) * S
				local py, ph = y * S, (y2 - y + 1) * S
				local slice = buffer.create(pw * ph * 4)
				for row = 0, ph - 1 do
					buffer.copy(slice, row * pw * 4, ch.buf, ((py + row) * PW + px) * 4, pw * 4)
				end
				ch.img:WritePixelsBuffer(Vector2.new(px, py), Vector2.new(pw, ph), slice)
				y = y2 + 1
			else
				y += 1
			end
		end
	end
end

return MapView
