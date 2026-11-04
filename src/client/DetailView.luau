--!nocheck
-- Visão detalhada: no zoom alto, uma imagem extra de 8x8 pixels por célula cobre a região da tela,
-- com textura do terreno (floresta, deserto, montanha...), ondas no mar, fronteiras finas e trilhos.
local AssetService = game:GetService("AssetService")

local DetailView = {}
DetailView.__index = DetailView

local P = 8 -- pixels por célula
local RW, RH = 120, 76 -- tamanho da região em células (960 x 608 px)

local BIOME_COL = {
	{ 132, 176, 92 }, -- planície
	{ 74, 128, 66 }, -- floresta
	{ 52, 112, 58 }, -- selva
	{ 224, 198, 134 }, -- deserto
	{ 146, 136, 124 }, -- montanha
	{ 206, 212, 208 }, -- tundra
}
local WATER = { 44, 104, 168 }

local function c255(v)
	v = math.floor(v + 0.5)
	return if v < 0 then 0 elseif v > 255 then 255 else v
end
local function pack(r, g, b)
	return c255(r) + c255(g) * 256 + c255(b) * 65536 + 4278190080
end
local function hash(x, y)
	local h = math.sin(x * 12.9898 + y * 78.233) * 43758.5453
	return h - math.floor(h)
end

function DetailView.new(geo, view, parent)
	local self = setmetatable({}, DetailView)
	self.geo, self.view = geo, view
	self.W, self.H = geo.W, geo.H
	self.rx, self.ry = -1000, -1000
	self.dirty = {}
	local ok, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(RW * P, RH * P) })
	end)
	if not ok or not img then
		return self -- sem EditableImage: fica só o mapa normal
	end
	self.img = img
	self.buf = buffer.create(RW * P * RH * P * 4)
	local label = Instance.new("ImageLabel")
	label.Name = "Detail"
	label.BackgroundTransparency = 1
	label.ResampleMode = Enum.ResamplerMode.Pixelated
	label.ImageContent = Content.fromObject(img)
	label.Size = UDim2.fromScale(RW / self.W, RH / self.H)
	label.Visible = false
	label.ZIndex = 2
	label.Parent = parent
	self.label = label
	table.insert(view.listeners, function(t)
		self.dirty[t] = true
	end)
	return self
end

function DetailView:drawTile(t)
	local geo, view = self.geo, self.view
	local x, y = geo:xy(t)
	local lx, ly = x - self.rx, y - self.ry
	if lx < 0 or ly < 0 or lx >= RW or ly >= RH then
		return
	end
	local PW = RW * P
	local buf = self.buf
	local base = (ly * P * PW + lx * P) * 4
	local W, H = self.W, self.H
	if not geo.land[t] then
		-- mar com ondas leves e espuma perto da costa
		local d = view.depth[t]
		for j = 0, P - 1 do
			for i = 0, P - 1 do
				local gx, gy = x * P + i, y * P + j
				local wave = math.sin(gx * 0.55 + gy * 0.9) * 0.5 + 0.5
				local k = 1 + (wave > 0.86 and 0.1 or 0) + (d <= 1 and 0.14 or 0)
				buffer.writeu32(buf, base + (j * PW + i) * 4, pack(WATER[1] * k, WATER[2] * k, WATER[3] * k))
			end
		end
		return
	end
	local bio = geo.biome and geo.biome[t] or 1
	local bc = BIOME_COL[bio]
	local o = view.owner[t]
	local nc = o ~= 0 and view.colors[o]
	local tint = 0.38
	local land, owner = geo.land, view.owner
	local function diff(nx, ny)
		if ny < 0 or ny >= H then
			return false
		end
		local nb = ny * W + (nx % W) + 1
		return land[nb] and owner[nb] ~= o
	end
	local function coast(nx, ny)
		if ny < 0 or ny >= H then
			return true
		end
		return not land[ny * W + (nx % W) + 1]
	end
	local dL, dR, dU, dD = diff(x - 1, y), diff(x + 1, y), diff(x, y - 1), diff(x, y + 1)
	local cL, cR, cU, cD = coast(x - 1, y), coast(x + 1, y), coast(x, y - 1), coast(x, y + 1)
	for j = 0, P - 1 do
		for i = 0, P - 1 do
			local gx, gy = x * P + i, y * P + j
			local n = hash(gx, gy)
			local r, g, b = bc[1], bc[2], bc[3]
			local k = 0.94 + n * 0.1
			-- textura por bioma
			if bio == 2 or bio == 3 then
				-- copas de árvores: bolinhas escuras
				local cx, cy = (gx % 4) - 1.5, (gy % 4) - 1.5
				if cx * cx + cy * cy < (bio == 3 and 2.6 or 1.8) then
					k *= 0.78
				end
			elseif bio == 4 then
				-- dunas
				if math.sin(gx * 0.7 + math.sin(gy * 0.35) * 2) > 0.7 then
					k *= 1.08
				end
			elseif bio == 5 then
				-- picos com neve
				local px, py = gx % 8, gy % 8
				if py >= 2 and math.abs(px - 4) <= (py - 2) * 0.6 then
					k *= 0.82
					if py <= 3 then
						r, g, b = 240, 240, 245
						k = 1
					end
				end
			elseif bio == 1 then
				if n > 0.93 then
					k *= 1.15 -- florzinhas
				end
			end
			r, g, b = r * k, g * k, b * k
			if nc then
				r, g, b = r + (nc[1] - r) * tint, g + (nc[2] - g) * tint, b + (nc[3] - b) * tint
			end
			-- areia na costa
			if (cL and i == 0) or (cR and i == P - 1) or (cU and j == 0) or (cD and j == P - 1) then
				r, g, b = 236, 220, 170
			end
			-- fronteira fina (2 px) na cor do dono
			if nc and ((dL and i < 2) or (dR and i >= P - 2) or (dU and j < 2) or (dD and j >= P - 2)) then
				r, g, b = nc[1] * 0.7, nc[2] * 0.7, nc[3] * 0.7
			end
			buffer.writeu32(buf, base + (j * PW + i) * 4, pack(r, g, b))
		end
	end
	-- trilhos: dois trilhos com dormentes, só nas direções com trilho vizinho
	if view.rails[t] then
		local rails = view.rails
		local function has(nx, ny)
			return ny >= 0 and ny < H and rails[ny * W + (nx % W) + 1] == true
		end
		local steel, wood = pack(70, 70, 78), pack(120, 86, 56)
		local function px(i, j, c)
			buffer.writeu32(buf, base + (j * PW + i) * 4, c)
		end
		local h = has(x - 1, y) or has(x + 1, y)
		local v = has(x, y - 1) or has(x, y + 1)
		if not h and not v then
			h = true
		end
		if h then
			local i0 = has(x - 1, y) and 0 or 3
			local i1 = has(x + 1, y) and P - 1 or 4
			for i = i0, i1 do
				if i % 2 == 0 then
					for j = 2, 5 do
						px(i, j, wood)
					end
				end
				px(i, 2, steel)
				px(i, 5, steel)
			end
		end
		if v then
			local j0 = has(x, y - 1) and 0 or 3
			local j1 = has(x, y + 1) and P - 1 or 4
			for j = j0, j1 do
				if j % 2 == 0 then
					for i = 2, 5 do
						px(i, j, wood)
					end
				end
				px(2, j, steel)
				px(5, j, steel)
			end
		end
	end
end

-- chamada a cada quadro: mostra/esconde e mantém a região em volta do centro da tela
function DetailView:update(active, cx, cy)
	if not self.img then
		return
	end
	self.label.Visible = active
	if not active then
		return
	end
	local W, H = self.W, self.H
	local tx = math.clamp(math.floor(cx - RW / 2), 0, W - RW)
	local ty = math.clamp(math.floor(cy - RH / 2), 0, H - RH)
	-- região nova: desenha aos poucos (8 linhas por quadro) e só troca quando terminar
	if not self.job and (math.abs(tx - self.rx) > RW * 0.25 or math.abs(ty - self.ry) > RH * 0.25) then
		self.job = { tx = tx, ty = ty, row = 0, orx = self.rx, ory = self.ry }
		self.rx, self.ry = tx, ty -- drawTile usa a região nova
	end
	if self.job then
		local job = self.job
		for _ = 1, 8 do
			if job.row >= RH then
				break
			end
			local yy = job.ty + job.row
			for xx = job.tx, job.tx + RW - 1 do
				self:drawTile(yy * W + xx + 1)
			end
			job.row += 1
		end
		if job.row >= RH then
			self.job = nil
			self.label.Position = UDim2.fromScale(job.tx / W, job.ty / H)
			self.img:WritePixelsBuffer(Vector2.zero, Vector2.new(RW * P, RH * P), self.buf)
			table.clear(self.dirty)
		end
		return
	end
	if next(self.dirty) then
		local minY, maxY = math.huge, -1
		for t in self.dirty do
			-- vizinhos também (fronteira)
			for _, c in { t, table.unpack(self.geo:around(t)) } do
				local _, y = self.geo:xy(c)
				if y >= self.ry and y < self.ry + RH then
					self:drawTile(c)
					minY = math.min(minY, y)
					maxY = math.max(maxY, y)
				end
			end
		end
		table.clear(self.dirty)
		if maxY >= minY then
			local PW = RW * P
			local py, ph = (minY - self.ry) * P, (maxY - minY + 1) * P
			local slice = buffer.create(PW * ph * 4)
			buffer.copy(slice, 0, self.buf, py * PW * 4, PW * ph * 4)
			self.img:WritePixelsBuffer(Vector2.new(0, py), Vector2.new(PW, ph), slice)
		end
	end
end

-- força redesenho completo (nova rodada)
function DetailView:reset()
	self.rx, self.ry = -1000, -1000
	self.job = nil
end

return DetailView
