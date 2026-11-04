--!nocheck
-- Simulação pura do jogo (sem APIs do Roblox): mapa, nações, ataques, economia, bots e rodada.
-- O servidor cria uma Sim por rodada e escuta os callbacks para desenhar o mundo.

local Sim = {}
Sim.__index = Sim

-- RNG determinístico (Park-Miller)
local function makeRng(seed)
	local s = (math.floor(seed) % 2147483646) + 1
	return function()
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
end

function Sim.new(cfg, seed, world)
	local self = setmetatable({}, Sim)
	self.cfg = cfg
	self.W, self.H = cfg.W, cfg.H
	if world then
		self.W, self.H = world.W, world.H
	end
	self.random = makeRng(seed or os.time())
	self.nations = {}
	self.nationCount = 0
	self.attacks = {}
	self.boats = {}
	self.flights = {} -- mísseis no ar
	self.trains = {}
	self.seq = 0 -- ids de ataques, trens e mísseis (para o cliente animar)
	self.trainClock = 0
	self.buildings = {} -- [idx] = {kind, owner}
	self.time = 0
	self.phase = "select" -- escolha de nação (países reais) ou de onde nascer (mapa procedural)
	self.phaseLeft = cfg.SELECT_PHASE
	self.protectedUntil = cfg.SELECT_PHASE + cfg.PROTECTION
	self.winner = nil
	-- callbacks (opcionais)
	self.onVisual = nil -- (idx, owner, isBorder)
	self.onOwner = nil -- (idx, owner)
	self.onBuilding = nil -- (idx, building|nil)
	self.onEvent = nil -- (text, kind)
	self.onMissile = nil -- (x, y, radius, launcherId)
	if world then
		self:loadWorld(world)
	else
		self:generate()
	end
	return self
end

function Sim:mod(n, k)
	local m = n.mods
	return m and m[k] or 0
end

-- devolve tropas de um ataque/barco (para o exército, se for de exército)
function Sim:giveBack(A, src, amount)
	if src.army and self.returnTroops then
		self:returnTroops(A, src, amount)
	else
		A.troops += amount
	end
end

function Sim:randInt(n)
	return math.floor(self.random() * n) + 1
end

function Sim:xy(t)
	return (t - 1) % self.W, (t - 1) // self.W
end

-- o mapa dá a volta na horizontal (Alasca <-> Rússia pelo Pacífico)
function Sim:idx(x, y)
	if y < 0 or y >= self.H then
		return nil
	end
	return y * self.W + (x % self.W) + 1
end

function Sim:around(t)
	local x, y = self:xy(t)
	local r = {}
	for _, c in { self:idx(x + 1, y), self:idx(x - 1, y), self:idx(x, y + 1), self:idx(x, y - 1) } do
		r[#r + 1] = c
	end
	return r
end

function Sim:loadWorld(world)
	local country, t = {}, 0
	for id, cnt in string.gmatch(world.rle, "(%d+)x(%d+)") do
		id, cnt = tonumber(id), tonumber(cnt)
		for _ = 1, cnt do
			t += 1
			country[t] = id
		end
	end
	assert(t == self.W * self.H, "WorldMap com tamanho errado")
	local land = {}
	for i = 1, t do
		land[i] = country[i] > 0
	end
	self.country = country
	self.names = world.names
	self:finalize(land, false)
end

---------------------------------------------------------------- mapa
function Sim:generate()
	local W, H = self.W, self.H
	local ox, oy, oz = self.random() * 500, self.random() * 500, self.random() * 10
	local values, list = {}, {}
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local nx, ny = x / W, y / H
			local e, amp, freq = 0, 1, 2.2
			for _ = 1, 5 do
				e += math.noise(nx * freq * (W / H) + ox, ny * freq + oy, oz) * amp
				amp *= 0.5
				freq *= 2
			end
			local dx, dy = (nx - 0.5) * 2, (ny - 0.5) * 2
			local d = math.sqrt(dx * dx * 0.85 + dy * dy)
			local v = e - d * 0.75
			local t = y * W + x + 1
			values[t] = v
			list[#list + 1] = v
		end
	end
	table.sort(list)
	local threshold = list[math.floor(#list * (1 - self.cfg.LAND_SHARE)) + 1]

	local land = {}
	for t = 1, W * H do
		land[t] = values[t] >= threshold
	end

	self:finalize(land, true)
end

-- separa massas de terra, remove ilhotas e monta vizinhanças
function Sim:finalize(land, onlyLargest)
	local W, H = self.W, self.H
	local comp, sizes, cid = {}, {}, 0
	for t = 1, W * H do
		if land[t] and not comp[t] then
			cid += 1
			local stack, size = { t }, 0
			comp[t] = cid
			while #stack > 0 do
				local c = table.remove(stack)
				size += 1
				for _, n in self:around(c) do
					if land[n] and not comp[n] then
						comp[n] = cid
						stack[#stack + 1] = n
					end
				end
			end
			sizes[cid] = size
		end
	end
	local best = 1
	for i, sz in sizes do
		if sz > (sizes[best] or 0) then
			best = i
		end
	end
	self.land, self.owner, self.nbr, self.coast, self.comp = {}, {}, {}, {}, {}
	self.landCount = 0
	self.landList = {}
	for t = 1, W * H do
		local c = comp[t]
		local isLand = land[t] and (if onlyLargest then c == best else sizes[c] >= (self.cfg.MIN_ISLAND or 3))
		self.land[t] = isLand or false
		self.owner[t] = 0
		if isLand then
			self.comp[t] = c
			self.landCount += 1
			self.landList[#self.landList + 1] = t
		end
	end
	for _, t in self.landList do
		local n, coast = {}, false
		for _, c in self:around(t) do
			if self.land[c] then
				n[#n + 1] = c
			else
				coast = true
			end
		end
		local _, y = self:xy(t)
		if y == 0 or y == H - 1 then
			coast = true
		end
		self.nbr[t] = n
		self.coast[t] = coast
	end
end

---------------------------------------------------------------- nações
function Sim:addNation(opts)
	self.nationCount += 1
	local id = self.nationCount
	local pal = self.cfg.PALETTE
	local n = {
		id = id,
		name = opts.name or ("Nação " .. id),
		color = opts.color or pal[(id - 1) % #pal + 1],
		isBot = opts.isBot or false,
		userId = opts.userId or 0,
		troops = 0,
		gold = self.cfg.START_GOLD,
		tiles = 0,
		tileSet = {},
		border = {}, -- células na borda (inclui costa)
		front = {}, -- células com vizinho em terra de outro dono (frente de ataque)
		defs = {}, -- [célula] = true para cada fortaleza
		navalCd = 0,
		sx = 0,
		sy = 0,
		alive = true,
		spawned = false,
		counts = { city = 0, factory = 0, port = 0, defense = 0, aa = 0, silo = 0, missile = 0 },
		pending = {},
		rate = 0,
		goldRate = 0,
		think = 1 + self.random() * 2,
		aggr = 0.35 + self.random() * 0.3,
	}
	self.nations[id] = n
	return id
end

function Sim:refreshBorder(t)
	local o = self.owner[t]
	local b = false
	if o ~= 0 then
		local f = false
		for _, c in self.nbr[t] do
			if self.owner[c] ~= o then
				f = true
				break
			end
		end
		b = f or self.coast[t]
		local n = self.nations[o]
		n.border[t] = b or nil
		n.front[t] = f or nil
	end
	if self.onVisual then
		self.onVisual(t, o, b)
	end
end

function Sim:setOwner(t, o)
	local old = self.owner[t]
	if old == o then
		return
	end
	local x, y = self:xy(t)
	self.owner[t] = o
	if self.onOwner then
		self.onOwner(t, o)
	end
	if old ~= 0 then
		local n = self.nations[old]
		n.tiles -= 1
		n.tileSet[t] = nil
		n.border[t] = nil
		n.front[t] = nil
		n.sx -= x
		n.sy -= y
	end
	if o ~= 0 then
		local n = self.nations[o]
		n.tiles += 1
		n.tileSet[t] = true
		n.sx += x
		n.sy += y
	end
	local b = self.buildings[t]
	if b then
		if old ~= 0 then
			local on = self.nations[old]
			if b.done == false then
				on.pending[b.kind] = math.max(0, (on.pending[b.kind] or 0) - 1)
			else
				on.counts[b.kind] -= 1
			end
			on.defs[t] = nil
		end
		if o == 0 then
			self.buildings[t] = nil
			if self.onBuilding then
				self.onBuilding(t, nil)
			end
		else
			b.owner = o
			local nn = self.nations[o]
			if b.done == false then
				nn.pending = nn.pending or {}
				nn.pending[b.kind] = (nn.pending[b.kind] or 0) + 1
			else
				nn.counts[b.kind] += 1
				if b.kind == "defense" then
					nn.defs[t] = true
				end
			end
			if self.onBuilding then
				self.onBuilding(t, b)
			end
		end
	end
	self:refreshBorder(t)
	for _, c in self.nbr[t] do
		self:refreshBorder(c)
	end
end

function Sim:maxTroops(n)
	local c = self.cfg
	return c.MAX_BASE + n.tiles * c.MAX_PER_TILE + n.counts.city * c.CITY_MAX_BONUS
end

-- a, b: ids das nações envolvidas (o servidor usa para filtrar mensagens entre bots)
function Sim:event(text, kind, a, b)
	if self.onEvent then
		self.onEvent(text, kind or "info", a, b)
	end
end

---------------------------------------------------------------- países reais
-- cada país do mapa vira uma nação dona do seu território real
function Sim:setupCountries()
	assert(self.country, "setupCountries precisa do mapa-múndi")
	local counts = {}
	for _, t in self.landList do
		local cid = self.country[t]
		counts[cid] = (counts[cid] or 0) + 1
	end
	local byCountry = {}
	for cid = 1, #self.names do
		if (counts[cid] or 0) > 0 then
			local id = self:addNation({ name = self.names[cid], isBot = true })
			self.nations[id].country = cid
			byCountry[cid] = id
		end
	end
	assert(self.nationCount <= 255, "nações demais para o buffer u8")
	for _, t in self.landList do
		local id = byCountry[self.country[t]]
		local n = self.nations[id]
		local x, y = self:xy(t)
		self.owner[t] = id
		n.tiles += 1
		n.tileSet[t] = true
		n.sx += x
		n.sy += y
		n.home = n.home or t
	end
	for _, t in self.landList do
		self:refreshBorder(t)
	end
	self:assignColors()
	for _, n in self.nations do
		n.spawned = true
		n.troops = math.floor(self:maxTroops(n) * self.cfg.START_TROOP_SHARE)
	end
	self.byCountry = byCountry
end

-- cores: cada país pega a cor da paleta mais diferente das dos vizinhos
function Sim:assignColors()
	local pal = self.cfg.PALETTE
	local order = {}
	for _, n in self.nations do
		order[#order + 1] = n
	end
	table.sort(order, function(a, b)
		return a.tiles > b.tiles
	end)
	local used = {}
	for _, n in order do
		local nbColors = {}
		for o in self:neighborsOf(n.id) do
			local v = o ~= 0 and self.nations[o]
			if v and v.colorIndex then
				nbColors[#nbColors + 1] = pal[v.colorIndex]
			end
		end
		local best, bestScore = 1, -math.huge
		for i, c in pal do
			local minD = 1e9
			for _, k in nbColors do
				local d = (c[1] - k[1]) ^ 2 + (c[2] - k[2]) ^ 2 + (c[3] - k[3]) ^ 2
				if d < minD then
					minD = d
				end
			end
			local score = math.min(minD, 30000) - (used[i] or 0) * 2500
			if score > bestScore then
				best, bestScore = i, score
			end
		end
		used[best] = (used[best] or 0) + 1
		n.colorIndex = best
		n.color = pal[best]
	end
end

function Sim:canSpawnAt(id, t)
	if not t or not self.land[t] then
		return false, "Escolha um lugar em terra firme"
	end
	local o = self.owner[t]
	if o ~= 0 and o ~= id then
		return false, "Esse lugar já tem dono"
	end
	local x, y = self:xy(t)
	local d = self.cfg.SPAWN_MIN_DIST
	for dy = -d, d do
		for dx = -d, d do
			local c = self:idx(x + dx, y + dy)
			if c and self.land[c] and self.owner[c] ~= 0 and self.owner[c] ~= id then
				return false, "Muito perto de outra nação"
			end
		end
	end
	return true
end

function Sim:spawn(id, x, y)
	local n = self.nations[id]
	if not n or not n.alive then
		return false, "Você foi eliminado nesta rodada"
	end
	if n.spawned and self.phase ~= "select" then
		return false, "Você já nasceu"
	end
	local t = self:idx(x, y)
	local ok, err = self:canSpawnAt(id, t)
	if not ok then
		return false, err
	end
	if n.spawned then -- trocar de lugar durante a fase de escolha
		local mine = {}
		for c in n.tileSet do
			mine[#mine + 1] = c
		end
		for _, c in mine do
			self:setOwner(c, 0)
		end
	end
	local r = self.cfg.SPAWN_RADIUS
	for dy = -r, r do
		for dx = -r, r do
			if dx * dx + dy * dy <= r * r + 1 then
				local c = self:idx(x + dx, y + dy)
				if c and self.land[c] and self.owner[c] == 0 then
					self:setOwner(c, id)
				end
			end
		end
	end
	n.spawned = true
	n.home = t
	n.troops = self.cfg.START_TROOPS
	return true
end

function Sim:randomSpawn(id)
	for _ = 1, 600 do
		local t = self.landList[self:randInt(#self.landList)]
		if self:canSpawnAt(id, t) then
			local x, y = self:xy(t)
			return self:spawn(id, x, y)
		end
	end
	return false, "Sem espaço livre no mapa"
end

function Sim:neighborsOf(id)
	local n = self.nations[id]
	local set = {}
	if not n then
		return set
	end
	for t in n.front do
		for _, c in self.nbr[t] do
			local o = self.owner[c]
			if o ~= id then
				set[o] = true
			end
		end
	end
	return set
end

function Sim:borders(id, target)
	local n = self.nations[id]
	for t in n.front do
		for _, c in self.nbr[t] do
			if self.owner[c] == target then
				return true
			end
		end
	end
	return false
end

function Sim:isProtected()
	return self.time < self.protectedUntil
end

---------------------------------------------------------------- ataques
function Sim:attack(id, x, y, pct)
	if self.phase ~= "play" then
		return false, "A guerra ainda não começou"
	end
	local n = self.nations[id]
	if not n or not n.alive or not n.spawned then
		return false, "Você não tem território"
	end
	local t = self:idx(x, y)
	if not t or not self.land[t] then
		return false, "Isso é água (sem rotas marítimas)"
	end
	local target = self.owner[t]
	if target == id then
		return false, "Esse território já é seu"
	end
	if target ~= 0 and self.canAttack then
		local okA, errA = self:canAttack(id, target)
		if not okA then
			return false, errA
		end
	end
	if target ~= 0 and self:isProtected() then
		return false, "Proteção ativa: conquiste só terra neutra por enquanto"
	end
	pct = math.clamp(pct or 0.25, 0.01, 1)
	local troops = math.floor(n.troops * pct)
	if troops < 1 then
		return false, "Tropas insuficientes"
	end
	if not self:bordersOnMass(id, target, self.comp[t]) then
		-- sem fronteira por terra nessa massa de terra: tenta mandar um barco
		local mine = 0
		for _, b in self.boats do
			if b.from == id then
				mine += 1
			end
		end
		if mine >= self.cfg.MAX_BOATS then
			return false, "Barcos demais no mar (máx. " .. self.cfg.MAX_BOATS .. ")"
		end
		local path, landing = self:findSeaRoute(id, t)
		if not path then
			return false, "Sem fronteira ou rota marítima"
		end
		n.troops -= troops
		local army = self.armyOrder
		local gb = 0
		if army and self.genFx then
			local _, _, b3 = self:genFx(n, army.gen)
			gb = b3
		end
		self.boats[#self.boats + 1] = {
			from = id, to = target, troops = troops, path = path, landing = landing, pos = 1,
			army = army and army.id, gen = army and army.gen,
			speed = 1 + self:mod(n, "boatSpeed") + gb,
		}
		return true, "boat"
	end
	n.troops -= troops

	-- contra-ataque: tropas se anulam contra o ataque inimigo vindo na direção oposta
	for i, a in self.attacks do
		if a.from == target and a.to == id then
			local m = math.min(a.troops, troops)
			a.troops -= m
			troops -= m
			if a.troops < 1 then
				table.remove(self.attacks, i)
			end
			break
		end
	end
	if troops < 1 then
		return true
	end
	local army = self.armyOrder
	if not army then
		for _, a in self.attacks do
			if a.from == id and a.to == target and not a.army then
				a.troops += troops
				return true
			end
		end
	end
	self.attacks[#self.attacks + 1] = { from = id, to = target, troops = troops, acc = 0, army = army and army.id, gen = army and army.gen }
	return true
end

function Sim:bordersOnMass(id, target, comp)
	local n = self.nations[id]
	for t in n.front do
		if self.comp[t] == comp then
			for _, c in self.nbr[t] do
				if self.owner[c] == target then
					return true
				end
			end
		end
	end
	return false
end

function Sim:hasCoast(id)
	for t in self.nations[id].border do
		if self.coast[t] then
			return true
		end
	end
	return false
end

-- rota de barco: desembarque no alvo mais perto do clique + caminho pela água até a costa do atacante
function Sim:findSeaRoute(id, t)
	if not self:hasCoast(id) then
		return nil
	end
	local target = self.owner[t]
	local landing
	do
		local seen, q, h = { [t] = true }, { t }, 1
		while h <= #q and h < 4000 do
			local c = q[h]
			h += 1
			if self.coast[c] then
				landing = c
				break
			end
			for _, nb in self.nbr[c] do
				if not seen[nb] and self.owner[nb] == target then
					seen[nb] = true
					q[#q + 1] = nb
				end
			end
		end
	end
	if not landing then
		return nil
	end
	local prev, dist, q, h = {}, {}, {}, 1
	for _, w in self:around(landing) do
		if not self.land[w] then
			prev[w], dist[w] = 0, 1
			q[#q + 1] = w
		end
	end
	local goal
	local range = self.cfg.BOAT_RANGE * (1 + self:mod(self.nations[id], "boatRange"))
	while h <= #q do
		local c = q[h]
		h += 1
		local adj = self:around(c)
		for _, nb in adj do
			if self.land[nb] and self.owner[nb] == id then
				goal = c
				break
			end
		end
		if goal then
			break
		end
		if dist[c] < range then
			for _, nb in adj do
				if not self.land[nb] and prev[nb] == nil then
					prev[nb], dist[nb] = c, dist[c] + 1
					q[#q + 1] = nb
				end
			end
		end
	end
	if not goal then
		return nil
	end
	local path, c = {}, goal
	while c ~= 0 do
		path[#path + 1] = c
		c = prev[c]
	end
	return path, landing
end

function Sim:landBoat(b)
	local A = self.nations[b.from]
	if not A.alive then
		return
	end
	local o = self.owner[b.landing]
	local T = o ~= 0 and self.nations[o] or nil
	if o == b.from or (T and (self:isProtected() or not T.alive)) or (T and self.peaceful and self:peaceful(b.from, o)) then
		self:giveBack(A, b, b.troops)
		return
	end
	local c = self.cfg
	local cost = c.NEUTRAL_COST
	if T then
		cost = (c.ENEMY_BASE_COST + T.troops / math.max(1, T.tiles)) * self:defenseMult(b.landing, o) * (1 + self:mod(T, "def"))
	end
	cost /= 1 + self:mod(A, "atk")
	if b.troops < cost then
		self:event("Um barco de " .. A.name .. " afundou no desembarque", "info", A.id)
		return
	end
	b.troops -= cost
	if T then
		T.troops = math.max(0, T.troops - T.troops / math.max(1, T.tiles) * 0.7)
	end
	self:setOwner(b.landing, b.from)
	if T and T.tiles == 0 then
		self:eliminate(T, A)
		self:giveBack(A, b, b.troops)
		return
	end
	if not b.army then
		for _, a in self.attacks do
			if a.from == b.from and a.to == o and not a.army then
				a.troops += b.troops
				return
			end
		end
	end
	self.attacks[#self.attacks + 1] = { from = b.from, to = o, troops = b.troops, acc = 0, army = b.army, gen = b.gen }
end

function Sim:stepBoats(dt)
	local speed = self.cfg.BOAT_SPEED
	for i = #self.boats, 1, -1 do
		local b = self.boats[i]
		b.pos += speed * (b.speed or 1) * dt
		if b.pos >= #b.path then
			table.remove(self.boats, i)
			self:landBoat(b)
		end
	end
end

function Sim:boatXY(b)
	local i = math.clamp(math.floor(b.pos), 1, #b.path)
	return self:xy(b.path[i])
end

function Sim:defenseMult(t, owner)
	local c = self.cfg
	local x, y = self:xy(t)
	local r2 = c.DEFENSE_RADIUS * c.DEFENSE_RADIUS
	local n = self.nations[owner]
	if not n then
		return 1
	end
	for bt in n.defs do
		local bx, by = self:xy(bt)
		local dx = math.abs(bx - x)
		dx = math.min(dx, self.W - dx)
		if dx * dx + (by - y) ^ 2 <= r2 then
			return c.DEFENSE_MULT
		end
	end
	return 1
end

function Sim:eliminate(victim, killer)
	if not victim.alive then
		return
	end
	victim.alive = false
	victim.troops = 0
	if killer then
		killer.gold += math.floor(victim.gold * 0.5)
		self:event(killer.name .. " eliminou " .. victim.name .. "!", "kill", killer.id, victim.id)
	else
		self:event(victim.name .. " foi eliminado!", "kill", victim.id)
	end
	victim.gold = 0
	for i = #self.boats, 1, -1 do
		if self.boats[i].from == victim.id then
			table.remove(self.boats, i)
		end
	end
	for i = #self.attacks, 1, -1 do
		local a = self.attacks[i]
		if a.from == victim.id or a.to == victim.id then
			if a.from ~= victim.id then
				self:giveBack(self.nations[a.from], a, a.troops)
			end
			table.remove(self.attacks, i)
		end
	end
end

function Sim:stepAttacks(dt)
	local c = self.cfg
	for _, a in table.clone(self.attacks) do
		if not table.find(self.attacks, a) then
			continue -- removido por uma eliminação neste mesmo passo
		end
		local A = self.nations[a.from]
		local T = a.to ~= 0 and self.nations[a.to] or nil
		local done = false
		if not A.alive or A.tiles == 0 or (T and not T.alive) then
			done = true
		else
			local cand, score = {}, {}
			for t in A.front do
				for _, nb in self.nbr[t] do
					if self.owner[nb] == a.to then
						if score[nb] then
							score[nb] += 1
						else
							score[nb] = 1
							cand[#cand + 1] = nb
						end
					end
				end
			end
			if #cand == 0 then
				done = true
			else
				local genAtk, genSpeed = 0, 0
				if a.army and self.genFx then
					genAtk, genSpeed = self:genFx(A, a.gen)
				end
				local atkB = 1 + self:mod(A, "atk") + genAtk
				local speed = (T and c.ENEMY_SPEED or c.NEUTRAL_SPEED) * math.max(0.2, 1 + self:mod(A, "speed") + genSpeed)
				a.acc += (#cand * speed + c.MIN_SPEED) * dt
				local k = math.floor(a.acc)
				if k > 0 then
					a.acc -= k
					for _, t in cand do
						score[t] += self.random() * 1.5
					end
					table.sort(cand, function(p, q)
						return score[p] > score[q]
					end)
					local fx, fy, fn = 0, 0, 0
					for j = 1, math.min(k, #cand) do
						local t = cand[j]
						local cx, cy = self:xy(t)
						fx += cx
						fy += cy
						fn += 1
						local cost = c.NEUTRAL_COST
						if T then
							local dens = T.troops / math.max(1, T.tiles)
							cost = (c.ENEMY_BASE_COST + dens) * self:defenseMult(t, T.id) * (1 + self:mod(T, "def"))
						end
						cost /= atkB
						if a.troops < cost then
							done = true
							break
						end
						a.troops -= cost
						if T then
							local dens = T.troops / math.max(1, T.tiles)
							T.troops = math.max(0, T.troops - dens * 0.7)
						end
						self:setOwner(t, a.from)
						if a.army and self.armyConquered then
							self:armyConquered(A, a)
						end
						if T and T.tiles == 0 then
							self:eliminate(T, A) -- já remove este ataque e devolve as tropas
							break
						end
					end
					if fn > 0 then
						a.fx, a.fy = fx / fn, fy / fn
					end
				end
				if not a.fx then
					local cx, cy = self:xy(cand[1])
					a.fx, a.fy = cx, cy
				end
			end
		end
		if a.troops < 1 then
			done = true
		end
		if done then
			local pos = table.find(self.attacks, a)
			if pos then
				table.remove(self.attacks, pos)
				if A.alive then
					self:giveBack(A, a, a.troops)
				end
			end
		end
	end
end

---------------------------------------------------------------- construções
function Sim:buildCost(id, kind)
	local n = self.nations[id]
	local def = self.cfg.BUILDINGS[kind]
	if not n or not def then
		return math.huge
	end
	local pend = n.pending and n.pending[kind] or 0
	return math.floor(def.cost * def.growth ^ (n.counts[kind] + pend) * math.max(0.3, 1 - self:mod(n, "buildCost")))
end

function Sim:build(id, kind, x, y)
	if self.phase ~= "play" then
		return false, "Espere a guerra começar"
	end
	local n = self.nations[id]
	local def = self.cfg.BUILDINGS[kind]
	if not n or not n.alive or not def then
		return false, "Ação inválida"
	end
	local cost = self:buildCost(id, kind)
	if n.gold < cost then
		return false, "Ouro insuficiente"
	end
	local t = self:idx(x, y)
	if not t or not self.land[t] then
		return false, "Escolha um lugar em terra"
	end
	if kind == "missile" then
		if self:isProtected() then
			return false, "Mísseis só depois da proteção"
		end
		local silo, sd = self:nearestBuilding(id, "silo", x, y)
		if not silo then
			return false, "Construa um Lançador primeiro"
		end
		if sd > self.cfg.MISSILE_RANGE * (1 + self:mod(n, "missileRange")) then
			return false, "Fora do alcance do lançador mais próximo"
		end
		n.gold -= cost
		n.counts.missile += 1
		local sx, sy = self:xy(silo)
		self.seq += 1
		self.flights[#self.flights + 1] = {
			id = self.seq,
			from = id,
			sx = sx,
			sy = sy,
			tx = x % self.W,
			ty = y,
			t = 0,
			dur = math.clamp(sd / self.cfg.MISSILE_SPEED, 1.5, 6),
			r = def.radius + self:mod(n, "missileRadius"),
		}
		self:event(n.name .. " lançou um míssil!", "missile", id)
		return true
	end
	if kind == "port" and not self.coast[t] then
		return false, "O porto precisa ficar na costa"
	end
	if self.owner[t] ~= id then
		return false, "Construa dentro do seu território"
	end
	if self.buildings[t] then
		return false, "Já existe uma construção aqui"
	end
	n.gold -= cost
	-- com Civ, cada construção leva um tempo para ficar pronta
	local time = self.civ and (def.time or 0) or 0
	local b = { kind = kind, owner = id, done = time <= 0, left = time, total = time }
	self.buildings[t] = b
	if b.done then
		n.counts[kind] += 1
		if kind == "defense" then
			n.defs[t] = true
		end
	else
		n.pending[kind] = (n.pending[kind] or 0) + 1
	end
	if self.onBuilding then
		self.onBuilding(t, b)
	end
	return true
end

function Sim:missile(id, x, y, r)
	local launcher = self.nations[id]
	if self.intercept then
		local down, v = self:intercept(x, y, id)
		if down then
			self:event("O antiaéreo de " .. v.name .. " derrubou um míssil de " .. launcher.name .. "!", "missile", id, v.id)
			if self.onMissile then
				self.onMissile(x, y, r, id, true)
			end
			return
		end
	end
	local hit = {}
	for dy = -r, r do
		for dx = -r, r do
			if dx * dx + dy * dy <= r * r then
				local t = self:idx(x + dx, y + dy)
				if t and self.land[t] then
					local o = self.owner[t]
					if o ~= 0 and o ~= id then
						local v = self.nations[o]
						local dens = v.troops / math.max(1, v.tiles)
						v.troops = math.max(0, v.troops - dens)
						hit[o] = true
						self:setOwner(t, 0)
					end
				end
			end
		end
	end
	if self.onMissile then
		self.onMissile(x, y, r, id)
	end
	for o in hit do
		local v = self.nations[o]
		if v.tiles == 0 then
			self:eliminate(v, launcher)
		end
	end
end

-- distância horizontal considerando a volta do mapa
function Sim:dist(x1, y1, x2, y2)
	local dx = math.abs(x1 - x2)
	dx = math.min(dx, self.W - dx)
	return math.sqrt(dx * dx + (y1 - y2) ^ 2)
end

function Sim:nearestBuilding(id, kind, x, y)
	local best, bd = nil, math.huge
	for t, b in self.buildings do
		if b.owner == id and b.kind == kind and b.done ~= false then
			local bx, by = self:xy(t)
			local d = self:dist(bx, by, x, y)
			if d < bd then
				best, bd = t, d
			end
		end
	end
	return best, bd
end

function Sim:stepFlights(dt)
	for i = #self.flights, 1, -1 do
		local f = self.flights[i]
		f.t += dt
		if f.t >= f.dur then
			table.remove(self.flights, i)
			self:missile(f.from, f.tx, f.ty, f.r)
		end
	end
end

function Sim:flightXY(f)
	local k = math.clamp(f.t / f.dur, 0, 1)
	local dx = f.tx - f.sx
	if math.abs(dx) > self.W / 2 then
		dx -= math.sign(dx) * self.W
	end
	return (f.sx + dx * k) % self.W, f.sy + (f.ty - f.sy) * k
end

---------------------------------------------------------------- trens
-- linha reta entre duas células só passando por terra? (mapa dá a volta)
function Sim:landLine(x1, y1, x2, y2)
	local dx = x2 - x1
	if math.abs(dx) > self.W / 2 then
		dx -= math.sign(dx) * self.W
	end
	local dy = y2 - y1
	local steps = math.max(math.abs(dx), math.abs(dy))
	for i = 1, steps - 1 do
		local t = self:idx(math.floor(x1 + dx * i / steps + 0.5), math.floor(y1 + dy * i / steps + 0.5))
		if not t or not self.land[t] then
			return false
		end
	end
	return true
end

-- trilho em L entre duas células: só horizontal e vertical, sempre por terra
function Sim:railPath(x1, y1, x2, y2)
	local dx = x2 - x1
	if math.abs(dx) > self.W / 2 then
		dx -= math.sign(dx) * self.W
	end
	local dy = y2 - y1
	local sx, sy = math.sign(dx), math.sign(dy)
	local function build(horizontalFirst)
		local path = {}
		local x, y = x1, y1
		local function push()
			local t = self:idx(x, y)
			if not t or not self.land[t] then
				return false
			end
			path[#path + 1] = t
			return true
		end
		if not push() then
			return nil
		end
		local legs = horizontalFirst and { { "x", math.abs(dx), sx }, { "y", math.abs(dy), sy } } or { { "y", math.abs(dy), sy }, { "x", math.abs(dx), sx } }
		for _, leg in legs do
			for _ = 1, leg[2] do
				if leg[1] == "x" then
					x += leg[3]
				else
					y += leg[3]
				end
				if not push() then
					return nil
				end
			end
		end
		return path
	end
	return build(true) or build(false)
end

-- cada fábrica solta um trem que visita cidades e portos da nação (vizinho mais perto primeiro),
-- assentando trilhos retos (horizontal/vertical) por onde passa
function Sim:spawnTrain(ft, owner)
	local c = self.cfg
	local stops = {}
	for t, b in self.buildings do
		if b.owner == owner and b.done ~= false and (b.kind == "city" or b.kind == "port") then
			stops[#stops + 1] = t
		end
	end
	if #stops == 0 then
		return
	end
	local cx, cy = self:xy(ft)
	local path = { ft }
	local stopAt = {}
	local used = {}
	local count = 0
	while count < c.TRAIN_MAX_STOPS do
		local best, bd, bp = nil, math.huge, nil
		for _, t in stops do
			if not used[t] then
				local x, y = self:xy(t)
				local d = self:dist(cx, cy, x, y)
				if d < bd and d <= c.TRAIN_MAX_LEG then
					local rp = self:railPath(cx, cy, x, y)
					if rp then
						best, bd, bp = t, d, rp
					end
				end
			end
		end
		if not best then
			break
		end
		used[best] = true
		count += 1
		for i = 2, #bp do
			path[#path + 1] = bp[i]
		end
		stopAt[#path] = best
		cx, cy = self:xy(best)
	end
	if count == 0 then
		return
	end
	if self.addRails and self.rails then
		self:addRails(path)
	end
	self.seq += 1
	self.trains[#self.trains + 1] = { id = self.seq, owner = owner, path = path, stopAt = stopAt, pos = 1, stop = 0 }
end

function Sim:stepTrains(dt)
	local c = self.cfg
	self.trainClock += dt
	if self.trainClock >= 1 then
		self.trainClock -= 1
		for t, b in self.buildings do
			if b.kind == "factory" and b.done ~= false then
				b.cd = (b.cd or self.random() * c.TRAIN_INTERVAL) - 1
				if b.cd <= 0 then
					b.cd = c.TRAIN_INTERVAL
					self:spawnTrain(t, b.owner)
				end
			end
		end
	end
	for i = #self.trains, 1, -1 do
		local tr = self.trains[i]
		local n = self.nations[tr.owner]
		local remove = not n.alive
		if not remove then
			local before = math.floor(tr.pos)
			tr.pos = math.min(#tr.path, tr.pos + c.TRAIN_SPEED * dt)
			for k = before + 1, math.floor(tr.pos) do
				local st = tr.stopAt[k]
				local bld = st and self.buildings[st]
				if bld and bld.owner == tr.owner then
					-- paga de forma progressiva: 1x, 2x, 3x...
					tr.stop += 1
					local gold = c.TRAIN_STOP_GOLD * tr.stop * (bld.kind == "port" and c.PORT_TRAIN_MULT or 1) * (1 + self:mod(n, "trainGold"))
					n.gold += gold
					if self.onTrainGold then
						local sx, sy = self:xy(st)
						self.onTrainGold(tr.owner, sx, sy, gold)
					end
				end
			end
			remove = tr.pos >= #tr.path
		end
		if remove then
			table.remove(self.trains, i)
		end
	end
end

function Sim:trainXY(tr)
	local i = math.clamp(math.floor(tr.pos), 1, #tr.path)
	local j = math.min(i + 1, #tr.path)
	local k = tr.pos - i
	local ax, ay = self:xy(tr.path[i])
	local bx, by = self:xy(tr.path[j])
	if math.abs(bx - ax) > 1 then
		bx = ax -- volta do mapa: não interpola
	end
	return ax + (bx - ax) * k, ay + (by - ay) * k
end

---------------------------------------------------------------- bots
-- terra estrangeira mais próxima pela água, a partir da costa da nação (busca limitada)
function Sim:nearestOverseas(id)
	local n = self.nations[id]
	local range = self.cfg.BOT_NAVAL_RANGE or 80
	local maxNodes = 25000
	local dist, q, h = {}, {}, 1
	for t in n.border do
		if self.coast[t] then
			for _, w in self:around(t) do
				if not self.land[w] and not dist[w] then
					dist[w] = 1
					q[#q + 1] = w
				end
			end
		end
	end
	local prot = self:isProtected()
	local landReach = {} -- [dono .. ":" .. massa] = já alcança por terra?
	while h <= #q and #q < maxNodes do
		local c = q[h]
		h += 1
		for _, nb in self:around(c) do
			if self.land[nb] then
				local o = self.owner[nb]
				if o ~= id and (o == 0 or not prot) then
					local key = o .. ":" .. self.comp[nb]
					local r = landReach[key]
					if r == nil then
						r = self:bordersOnMass(id, o, self.comp[nb])
						landReach[key] = r
					end
					if not r then
						return nb
					end
				end
			elseif not dist[nb] and dist[c] < range then
				dist[nb] = dist[c] + 1
				q[#q + 1] = nb
			end
		end
	end
	return nil
end

function Sim:botThink(n)
	local c = self.cfg
	-- construir
	if self.phase == "play" then
		local order = { "city", "factory", "port", "defense", "city", "factory", "silo" }
		local kind = order[self:randInt(#order)]
		-- míssil contra o vizinho mais forte, se tiver lançador e ouro sobrando
		if n.counts.silo > 0 and not self:isProtected() and self.random() < 0.15 and n.gold >= self:buildCost(n.id, "missile") * 1.5 then
			local nb = self:neighborsOf(n.id)
			local best, bt = nil, -1
			for o in nb do
				local v = o ~= 0 and self.nations[o]
				if v and v.tiles > bt then
					best, bt = o, v.tiles
				end
			end
			if best then
				for t in self.nations[best].front do
					local x, y = self:xy(t)
					self:build(n.id, "missile", x, y)
					break
				end
			end
		end
		if n.tiles > 60 and n.gold >= self:buildCost(n.id, kind) and self.random() < 0.5 then
			local pool = {}
			local src = if kind == "port" then n.border else n.tileSet
			for t in src do
				if not self.buildings[t] and (kind ~= "port" or self.coast[t]) then
					pool[#pool + 1] = t
					if #pool > 60 then
						break
					end
				end
			end
			if #pool > 0 then
				local bx, by = self:xy(pool[self:randInt(#pool)])
				self:build(n.id, kind, bx, by)
			end
		end
	end
	-- atacar
	local busy = 0
	for _, a in self.attacks do
		if a.from == n.id then
			busy += 1
		end
	end
	if busy >= 2 then
		return
	end
	local max = self:maxTroops(n)
	if n.troops < max * n.aggr then
		return
	end
	local nb = self:neighborsOf(n.id)
	local target, pct = nil, 0.25
	if nb[0] then
		target, pct = 0, 0.2 + self.random() * 0.15
	elseif not self:isProtected() then
		local best, bestScore = nil, math.huge
		for o in nb do
			local v = self.nations[o]
			if v and v.alive and not (self.peaceful and self:peaceful(n.id, o)) then
				local s = v.troops / math.max(1, v.tiles) + self.random() * 20
				if s < bestScore then
					best, bestScore = o, s
				end
			end
		end
		if best then
			local v = self.nations[best]
			if n.troops * 0.5 > v.troops * 0.35 or self.random() < 0.15 then
				target, pct = best, 0.35 + self.random() * 0.25
			end
		end
	end
	if target == nil then
		-- sem alvo por terra: tenta um desembarque em outra terra
		if self.time >= n.navalCd then
			n.navalCd = self.time + 12 + self.random() * 12
			local t = self:nearestOverseas(n.id)
			if t then
				local x, y = self:xy(t)
				self:attack(n.id, x, y, 0.3)
			end
		end
		return
	end
	-- pega uma célula do alvo na fronteira
	for t in n.front do
		for _, cc in self.nbr[t] do
			if self.owner[cc] == target then
				local x, y = self:xy(cc)
				self:attack(n.id, x, y, pct)
				return
			end
		end
	end
end

---------------------------------------------------------------- loop
function Sim:step(dt)
	local c = self.cfg
	self.time += dt
	self.phaseLeft -= dt

	if self.phase == "select" then
		if self.phaseLeft <= 0 then
			for _, n in self.nations do
				if n.alive and not n.spawned then
					self:randomSpawn(n.id)
				end
			end
			self.phase = "play"
			self.phaseLeft = c.ROUND_MAX
			if self.country and self.byCountry then
				self:event("A partida começou! Prepare-se: a guerra começa quando a proteção acabar.", "start")
			else
				self:event("A expansão começou! Conquiste terras neutras.", "start")
			end
		end
		return
	end
	if self.phase == "end" then
		return
	end

	-- economia
	for _, n in self.nations do
		if n.alive and n.spawned then
			local max = self:maxTroops(n)
			local g = if self.civ
				then self:troopGrowth(n, max)
				else (c.GROWTH_BASE + n.tiles * c.GROWTH_PER_TILE + n.counts.city * c.CITY_GROWTH_BONUS) * math.max(0, 1.1 - n.troops / max)
			n.rate = g
			if n.troops < max then
				n.troops = math.min(max, n.troops + g * dt)
			end
			n.goldRate = if self.civ
				then self:goldIncome(n)
				else c.GOLD_BASE + n.tiles * c.GOLD_PER_TILE + n.counts.factory * c.FACTORY_GOLD + n.counts.port * c.PORT_GOLD
			n.gold += n.goldRate * dt
			if n.isBot then
				n.think -= dt
				if n.think <= 0 then
					n.think = 0.8 + self.random() * 1.5
					self:botThink(n)
				end
			end
		end
	end

	local wasProtected = self.time - dt < self.protectedUntil
	if wasProtected and not self:isProtected() then
		self:event("A proteção acabou! Agora vale atacar outras nações.", "war")
	end

	self:stepAttacks(dt)
	self:stepBoats(dt)
	self:stepFlights(dt)
	self:stepTrains(dt)
	if self.civ then
		self:civStep(dt)
	end

	-- vitória
	local best, bestTiles, aliveCount = nil, -1, 0
	for _, n in self.nations do
		if n.alive and n.spawned then
			aliveCount += 1
			if n.tiles > bestTiles then
				best, bestTiles = n, n.tiles
			end
		end
	end
	if best and (bestTiles >= self.landCount * c.WIN_SHARE or self.phaseLeft <= 0 or aliveCount <= 1) then
		self.phase = "end"
		self.phaseLeft = c.END_PHASE
		self.winner = best.id
		self:event(best.name .. " dominou o mundo!", "win", best.id)
	end
end

-- âncora do rótulo: célula da nação mais perto do centroide
function Sim:anchor(n)
	if n.tiles == 0 then
		return nil
	end
	local cx, cy = math.floor(n.sx / n.tiles + 0.5), math.floor(n.sy / n.tiles + 0.5)
	local t = self:idx(cx, cy)
	if t and self.owner[t] == n.id then
		return cx, cy
	end
	local best, bd = nil, math.huge
	for c in n.tileSet do
		local x, y = self:xy(c)
		local d = (x - cx) ^ 2 + (y - cy) ^ 2
		if d < bd then
			best, bd = c, d
		end
	end
	return self:xy(best)
end

-- conferência de consistência (usada nos testes)
function Sim:validate()
	local counts = {}
	for _, t in self.landList do
		local o = self.owner[t]
		if o ~= 0 then
			counts[o] = (counts[o] or 0) + 1
			assert(self.nations[o].tileSet[t], "tileSet faltando")
		end
	end
	for id, n in self.nations do
		assert((counts[id] or 0) == n.tiles, "contagem de células errada para " .. n.name)
		assert(n.troops >= 0 and n.troops == n.troops, "tropas inválidas")
		for t in n.border do
			assert(self.owner[t] == id, "borda de outra nação")
		end
		for t in n.front do
			assert(self.owner[t] == id and n.border[t], "frente inválida")
		end
	end
	return true
end

return Sim
