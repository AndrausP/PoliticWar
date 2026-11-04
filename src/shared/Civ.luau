--!nocheck
-- Sistemas de civilização sobre a Sim: biomas, população, felicidade/revolução, recursos e mercado,
-- pesquisa (árvores), leis e parlamento, diplomacia (relações, pactos, rotas de comércio),
-- exércitos com generais, antiaéreo e tempo de construção.
-- Uso: Civ.install(Sim) uma vez; depois sim:civInit() logo após setupCountries().
local D = if script then require(script.Parent:WaitForChild("CivData")) else CivData -- CivData: injetado no pacote de testes

local Civ = {}
Civ.Data = D

local RES = D.RESOURCES

---------------------------------------------------------------- biomas (determinístico: servidor e cliente calculam igual)
function Civ.computeBiomes(sim, world)
	local latTop, latBot = world.latTop or 84, world.latBot or -60
	sim.biome = {}
	-- índices de D.BIOMES: 1 planície, 2 floresta, 3 selva, 4 deserto, 5 montanha, 6 tundra
	for _, t in sim.landList do
		local x, y = sim:xy(t)
		local lat = latTop - (y + 0.5) / sim.H * (latTop - latBot)
		local alat = math.abs(lat)
		local ridge = math.noise(x * 0.09, y * 0.09, 3.3)
		local dry = math.noise(x * 0.025, y * 0.025, 7.7) + ((alat >= 14 and alat <= 34) and 0.45 or 0) - (alat > 45 and 0.3 or 0)
		local green = math.noise(x * 0.05, y * 0.05, 11.1)
		local b
		if alat >= 62 then
			b = 6
		elseif ridge > 0.38 then
			b = 5
		elseif dry > 0.42 then
			b = 4
		elseif alat < 16 then
			b = green > -0.15 and 3 or 1
		else
			b = green > 0.05 and 2 or 1
		end
		sim.biome[t] = b
	end
end

---------------------------------------------------------------- instalação
function Civ.install(Sim)
	if Sim.civInstalled then
		return
	end
	Sim.civInstalled = true

	local function mod(n, k)
		local m = n.mods
		return m and m[k] or 0
	end
	Sim.mod = function(_, n, k)
		return mod(n, k)
	end

	------------------------------------------------------------ início
	function Sim:civInit(world)
		Civ.computeBiomes(self, world)
		self.civ = true
		self.rel = {}
		self.pacts = {}
		self.routes = {}
		self.convoys = {}
		self.proposals = {}
		self.rails = {}
		self.railsNew = {}
		self.market = { ref = {}, offers = {}, bought = {}, offered = {} }
		for _, r in RES do
			self.market.ref[r] = D.RES[r].base
			self.market.bought[r] = 0
			self.market.offered[r] = 0
		end
		self.civAcc, self.marketAcc = 0, 0
		for _, n in self.nations do
			local cid = n.country
			n.pop = math.max(0.05, (world.pops and world.pops[cid]) or 1)
			local gdp = (world.gdps and world.gdps[cid]) or 10
			n.gold = self.cfg.START_GOLD + math.min(60000, gdp * 3)
			n.gov = D.START_COM[n.name] and "com" or (self.random() < 0.12 and "fas" or "cap")
			n.happy = 60
			n.happyParts = {}
			n.influence = 20
			n.rp = 0
			n.skills = {}
			n.laws = {}
			n.armies = {}
			n.generals = {}
			n.pending = {}
			n.exported = {}
			n.stock, n.prod, n.need, n.short = {}, {}, {}, {}
			n.bio = { 0, 0, 0, 0, 0, 0 }
			n.capital = n.home
			n.aiLaw = 30 + self.random() * 90
			n.aiDip = 20 + self.random() * 60
			for t in n.tileSet do
				local b = self.biome[t]
				n.bio[b] += 1
			end
			for _, r in RES do
				n.exported[r] = 0
			end
			self:recalcMods(n)
			self:computeEconomy(n)
			for _, r in RES do
				n.stock[r] = n.need[r] * 120 + n.prod[r] * 60
			end
			for _ = 1, 2 do
				self:newGeneral(n)
			end
			-- tropas iniciais com o novo limite (população conta)
			n.troops = math.floor(self:maxTroops(n) * self.cfg.START_TROOP_SHARE)
		end
		for _, n in self.nations do
			local x, y = self:anchor(n)
			n.capital = self:idx(x, y)
		end
	end

	------------------------------------------------------------ modificadores
	function Sim:recalcMods(n)
		local m = {}
		local function add(fx)
			for k, v in fx do
				m[k] = (m[k] or 0) + v
			end
		end
		for id in n.skills do
			add(D.SKILLS[id].fx)
			add(D.SKILLS[id].bad) -- o preço de cada caminho
		end
		for id in n.laws do
			add(D.LAW_BY_ID[id].fx)
		end
		-- estilo de cada regime
		if n.gov == "cap" then
			add({ gold = 0.05, marketSell = 0.05 })
		elseif n.gov == "com" then
			add({ prod = 0.05, persuade = 0.1 })
		elseif n.gov == "fas" then
			add({ atk = 0.05, troopGrowth = 0.05 })
		end
		n.mods = m
		n.freeMarket = n.laws.free_market == true
		n.martial = n.laws.martial == true
	end

	------------------------------------------------------------ população, tropas e ouro
	local baseMax = Sim.maxTroops
	function Sim:maxTroops(n)
		if not self.civ then
			return baseMax(self, n)
		end
		local c = self.cfg
		local v = c.MAX_BASE + n.tiles * c.MAX_PER_TILE * 0.7 + (n.pop or 0) * c.POP_TROOPS + n.counts.city * c.CITY_MAX_BONUS
		return v * math.max(0.3, 1 + mod(n, "maxTroops"))
	end

	function Sim:troopGrowth(n, max)
		local c = self.cfg
		local g = c.GROWTH_BASE + n.tiles * c.GROWTH_PER_TILE * 0.7 + (n.pop or 0) * c.POP_GROWTH_TROOPS + n.counts.city * c.CITY_GROWTH_BONUS
		g *= math.max(0.2, 1 + mod(n, "troopGrowth"))
		return g * math.max(0, 1.1 - n.troops / max)
	end

	function Sim:goldIncome(n)
		local c = self.cfg
		local tax = (n.pop or 0) * c.TAX_PER_POP * math.max(0, 1 + mod(n, "taxMult"))
		local g = c.GOLD_BASE + n.tiles * c.GOLD_PER_TILE * 0.6 + tax + n.counts.factory * c.FACTORY_GOLD + n.counts.port * c.PORT_GOLD
		-- felicidade muito baixa derruba a arrecadação
		local h = n.happy or 60
		g *= math.max(0.2, 1 + mod(n, "gold")) * (h < 30 and (0.5 + h / 60) or 1)
		return g
	end

	-- produção e consumo por segundo
	function Sim:computeEconomy(n)
		local allProd = mod(n, "prod")
		for _, r in RES do
			n.prod[r] = 0
		end
		for bi, cnt in n.bio do
			if cnt > 0 then
				for r, y in D.BIOMES[bi].yield do
					n.prod[r] += y * cnt
				end
			end
		end
		n.prod.goods += (n.pop or 0) * 0.015 + n.counts.factory * 4 + n.counts.city * 1.5
		for _, r in RES do
			n.prod[r] *= math.max(0.1, 1 + allProd + mod(n, "prod_" .. r))
			n.need[r] = (n.pop or 0) * D.RES[r].need * (1 + mod(n, "need_" .. r))
		end
	end

	-- população e biomas acompanham as células conquistadas
	local baseSetOwner = Sim.setOwner
	function Sim:setOwner(t, o)
		local old = self.owner[t]
		if self.civ and old ~= o then
			local b = self.biome[t]
			if old ~= 0 then
				local v = self.nations[old]
				local share = (v.pop or 0) / math.max(1, v.tiles)
				v.pop = math.max(0.01, (v.pop or 0) - share)
				v.bio[b] -= 1
				v.warLoss = (v.warLoss or 0) + 1
				if o ~= 0 then
					local w = self.nations[o]
					w.pop = (w.pop or 0) + share * 0.8
				end
			end
			if o ~= 0 then
				self.nations[o].bio[b] += 1
			end
		end
		baseSetOwner(self, t, o)
	end

	------------------------------------------------------------ construções com tempo
	function Sim:stepConstruction(dt)
		for t, b in self.buildings do
			if not b.done then
				b.left -= dt
				if b.left <= 0 then
					b.done = true
					b.left = 0
					local n = self.nations[b.owner]
					n.pending[b.kind] = math.max(0, (n.pending[b.kind] or 0) - 1)
					n.counts[b.kind] += 1
					if b.kind == "defense" then
						n.defs[t] = true
					end
					if self.onBuilding then
						self.onBuilding(t, b)
					end
				end
			end
		end
	end

	------------------------------------------------------------ antiaéreo
	-- devolve true se o míssil foi derrubado
	function Sim:intercept(x, y, launcher)
		if not self.civ then
			return false
		end
		local t = self:idx(x, y)
		local victim = t and self.owner[t] or 0
		if victim == 0 or victim == launcher then
			return false
		end
		local v = self.nations[victim]
		for bt, b in self.buildings do
			if b.kind == "aa" and b.done and b.owner == victim then
				local bx, by = self:xy(bt)
				if self:dist(bx, by, x, y) <= D.AA_RADIUS then
					local chance = math.min(0.92, D.AA_CHANCE + mod(v, "aa"))
					return self.random() < chance, v
				end
			end
		end
		return false
	end

	------------------------------------------------------------ generais e exércitos
	function Sim:newGeneral(n)
		self.seq += 1
		local trait = D.TRAITS[self:randInt(#D.TRAITS)]
		local g = { id = self.seq, name = "Gen. " .. D.GENERAL_NAMES[self:randInt(#D.GENERAL_NAMES)], trait = trait.key, level = 1, xp = 0 }
		n.generals[#n.generals + 1] = g
		return g
	end

	function Sim:findGeneral(n, gid)
		for _, g in n.generals do
			if g.id == gid then
				return g
			end
		end
	end

	function Sim:findArmy(n, aid)
		for _, a in n.armies do
			if a.id == aid then
				return a
			end
		end
	end

	function Sim:genFx(n, gid)
		local g = gid and self:findGeneral(n, gid)
		if not g then
			return 0, 0, 0
		end
		local tr
		for _, t in D.TRAITS do
			if t.key == g.trait then
				tr = t
			end
		end
		local fx = tr and tr.fx or {}
		return (fx.atk or 0) + (g.level - 1) * D.GENERAL_LEVEL_ATK, fx.speed or 0, fx.boatSpeed or 0
	end

	function Sim:recruitGeneral(id)
		local n = self.nations[id]
		if #n.generals >= 6 then
			return false, "Máximo de 6 generais"
		end
		if n.gold < D.GENERAL_COST then
			return false, "Ouro insuficiente"
		end
		n.gold -= D.GENERAL_COST
		local g = self:newGeneral(n)
		return true, g.name .. " entrou para o seu estado-maior"
	end

	function Sim:createArmy(id, troops, gid)
		local n = self.nations[id]
		troops = math.floor(math.min(troops or 0, n.troops))
		if troops < 100 then
			return false, "Pelo menos 100 tropas para formar um exército"
		end
		if #n.armies >= 6 then
			return false, "Máximo de 6 exércitos"
		end
		if gid then
			if not self:findGeneral(n, gid) then
				return false, "General inválido"
			end
			for _, a in n.armies do
				if a.gen == gid then
					return false, "Esse general já comanda outro exército"
				end
			end
		end
		n.troops -= troops
		self.seq += 1
		local a = { id = self.seq, name = (#n.armies + 1) .. "º Exército", troops = troops, gen = gid, tiles = 0, busy = false }
		n.armies[#n.armies + 1] = a
		return true, a.name .. " formado com " .. troops .. " tropas"
	end

	function Sim:disbandArmy(id, aid)
		local n = self.nations[id]
		local a = self:findArmy(n, aid)
		if not a then
			return false, "Exército não encontrado"
		end
		if a.busy then
			return false, "O exército está em combate"
		end
		n.troops += a.troops
		table.remove(n.armies, table.find(n.armies, a))
		return true
	end

	function Sim:reinforceArmy(id, aid, troops)
		local n = self.nations[id]
		local a = self:findArmy(n, aid)
		if not a then
			return false, "Exército não encontrado"
		end
		troops = math.floor(math.min(troops, n.troops))
		if troops < 1 then
			return false, "Tropas insuficientes"
		end
		n.troops -= troops
		a.troops += troops
		return true
	end

	function Sim:sendArmy(id, aid, x, y)
		local n = self.nations[id]
		local a = self:findArmy(n, aid)
		if not a then
			return false, "Exército não encontrado"
		end
		if a.busy then
			return false, "Esse exército já está em combate"
		end
		if a.troops < 1 then
			return false, "Exército vazio"
		end
		-- usa o ataque normal com as tropas do exército
		local saved = n.troops
		n.troops = a.troops
		self.armyOrder = a
		local ok, info = self:attack(id, x, y, 1)
		self.armyOrder = nil
		local used = a.troops - n.troops
		n.troops = saved
		if ok then
			a.troops -= used
			a.busy = true
		end
		return ok, info
	end

	-- tropas de um ataque terminado voltam para o exército (se for de exército)
	function Sim:returnTroops(A, atk, amount)
		if atk.army then
			local a = self:findArmy(A, atk.army)
			if a then
				a.troops += amount
				a.busy = false
				return
			end
		end
		A.troops += amount
	end

	function Sim:armyConquered(A, atk)
		local a = self:findArmy(A, atk.army)
		if not a then
			return
		end
		a.tiles += 1
		local g = a.gen and self:findGeneral(A, a.gen)
		if g then
			local bonus = 0
			for _, tr in D.TRAITS do
				if tr.key == g.trait then
					bonus = tr.fx.generalXp or 0
				end
			end
			g.xp += 1 + bonus
			if g.xp >= D.GENERAL_LEVEL_XP * g.level then
				g.xp = 0
				g.level += 1
				self:event(g.name .. " subiu para o nível " .. g.level .. "!", "ok", A.id)
			end
		end
	end

	------------------------------------------------------------ diplomacia
	local function key(a, b)
		if a > b then
			a, b = b, a
		end
		return a * 1000 + b
	end
	Civ.pairKey = key

	function Sim:relation(a, b)
		local k = key(a, b)
		local r = self.rel[k]
		if r == nil then
			local na, nb = self.nations[a], self.nations[b]
			r = 0
			if na.gov == nb.gov then
				r += 15
			elseif (na.gov == "cap" and nb.gov == "com") or (na.gov == "com" and nb.gov == "cap") then
				r -= 25
			else
				r -= 12
			end
			self.rel[k] = r
		end
		return r
	end

	function Sim:addRelation(a, b, d)
		local k = key(a, b)
		self.rel[k] = math.clamp(self:relation(a, b) + d, -100, 100)
	end

	function Sim:pact(a, b)
		local k = key(a, b)
		local p = self.pacts[k]
		if not p then
			p = {}
			self.pacts[k] = p
		end
		return p
	end

	function Sim:peaceful(a, b)
		if not self.pacts then
			return false -- sem sistemas de civilização (mapa procedural)
		end
		local p = self.pacts[key(a, b)]
		return p ~= nil and (p.alliance or (p.napUntil or 0) > self.time)
	end

	function Sim:canAttack(a, b)
		if b == 0 or not self.civ then
			return true
		end
		if self:peaceful(a, b) then
			return false, "Vocês têm um pacto. Declare guerra na Diplomacia primeiro."
		end
		return true
	end

	-- caminho por terra (BFS 4 vizinhos: só horizontal e vertical)
	function Sim:landPath(from, to, limit)
		local prev, q, h = { [from] = 0 }, { from }, 1
		while h <= #q and #q < (limit or 120000) do
			local c = q[h]
			h += 1
			if c == to then
				local path, p = {}, c
				while p ~= 0 do
					table.insert(path, 1, p)
					p = prev[p]
				end
				return path
			end
			for _, nb in self.nbr[c] do
				if prev[nb] == nil then
					prev[nb] = c
					q[#q + 1] = nb
				end
			end
		end
		return nil
	end

	-- caminho por mar entre as costas de duas nações
	function Sim:seaPath(a, b)
		local na = self.nations[a]
		local prev, dist, q, h = {}, {}, {}, 1
		for t in na.border do
			if self.coast[t] then
				for _, w in self:around(t) do
					if not self.land[w] and prev[w] == nil then
						prev[w], dist[w] = 0, 1
						q[#q + 1] = w
					end
				end
			end
		end
		while h <= #q and #q < 160000 do
			local c = q[h]
			h += 1
			for _, nb in self:around(c) do
				if self.land[nb] then
					if self.owner[nb] == b then
						local path, p = {}, c
						while p ~= 0 do
							table.insert(path, 1, p)
							p = prev[p]
						end
						return path
					end
				elseif prev[nb] == nil and dist[c] < 900 then
					prev[nb], dist[nb] = c, dist[c] + 1
					q[#q + 1] = nb
				end
			end
		end
		return nil
	end

	function Sim:addRails(path)
		for _, t in path do
			if self.land[t] and not self.rails[t] then
				self.rails[t] = true
				self.railsNew[#self.railsNew + 1] = t
			end
		end
	end

	function Sim:createRoute(a, b)
		local na, nb = self.nations[a], self.nations[b]
		local path, kind
		if na.capital and nb.capital and self.comp[na.capital] == self.comp[nb.capital] then
			path = self:landPath(na.capital, nb.capital)
			kind = "train"
		end
		if not path then
			path = self:seaPath(a, b)
			kind = "boat"
		end
		if not path then
			return nil
		end
		if kind == "train" then
			self:addRails(path)
		end
		self.seq += 1
		local r = { id = self.seq, a = a, b = b, kind = kind, path = path, cd = 3 }
		self.routes[r.id] = r
		self:pact(a, b).trade = r.id
		return r
	end

	function Sim:removeRoute(a, b)
		local p = self.pacts[key(a, b)]
		if p and p.trade then
			self.routes[p.trade] = nil
			p.trade = nil
		end
	end

	-- quem decide é a IA do outro país (ou o jogador, que recebe uma proposta)
	function Sim:aiAccepts(from, to, kind)
		local r = self:relation(from, to)
		local B = self.nations[to]
		if kind == "trade" then
			return r > -20, r
		elseif kind == "nap" then
			return r > 0, r
		elseif kind == "alliance" then
			return r > 35, r
		elseif kind == "aid" then
			return r > 40 and B.gold > 15000, r
		end
		return false, r
	end

	-- executa um acordo já aceito
	function Sim:applyDeal(from, to, kind)
		local A, B = self.nations[from], self.nations[to]
		local p = self:pact(from, to)
		if kind == "trade" then
			if p.trade then
				return false, "Vocês já têm uma rota de comércio"
			end
			local r = self:createRoute(from, to)
			if not r then
				return false, "Não existe caminho por terra nem por mar"
			end
			self:addRelation(from, to, 10)
			return true, (r.kind == "train" and "🚂 Rota de trem criada com " or "⛵ Rota de navio criada com ") .. B.name
		elseif kind == "nap" then
			p.napUntil = self.time + 600
			self:addRelation(from, to, 10)
			return true, "Pacto de não-agressão com " .. B.name .. " (10 min)"
		elseif kind == "alliance" then
			p.alliance = true
			self:addRelation(from, to, 20)
			return true, "Aliança formada com " .. B.name
		elseif kind == "aid" then
			local amount = math.floor(math.min(10000, B.gold * 0.1))
			B.gold -= amount
			A.gold += amount
			self:addRelation(from, to, -15)
			return true, B.name .. " enviou " .. amount .. " de ouro"
		end
		return false, "Ação inválida"
	end

	-- ações diretas (não precisam de aceite)
	function Sim:diplomacy(from, to, kind)
		local A, B = self.nations[from], self.nations[to]
		if not A or not B or not B.alive or from == to then
			return false, "Nação inválida"
		end
		if kind == "gift" then
			local amount = math.floor(math.min(A.gold, 5000))
			if amount < 500 then
				return false, "Ouro insuficiente"
			end
			A.gold -= amount
			B.gold += amount
			self:addRelation(from, to, 12)
			return true, "Você enviou " .. amount .. " de ouro para " .. B.name
		elseif kind == "war" then
			local p = self:pact(from, to)
			p.alliance, p.napUntil = false, 0
			self:removeRoute(from, to)
			self:addRelation(from, to, -40)
			self:event(A.name .. " declarou guerra a " .. B.name .. "!", "war", from, to)
			return true, "Guerra declarada a " .. B.name
		elseif kind == "cancel_trade" then
			self:removeRoute(from, to)
			self:addRelation(from, to, -10)
			return true, "Rota de comércio cancelada"
		end
		if not B.isBot then
			-- outro jogador decide
			self.seq += 1
			self.proposals[#self.proposals + 1] = { id = self.seq, from = from, to = to, kind = kind, t = self.time }
			return true, "Proposta enviada para " .. B.name
		end
		local ok, r = self:aiAccepts(from, to, kind)
		if not ok then
			return false, B.name .. " recusou (relação " .. math.floor(r) .. ")"
		end
		return self:applyDeal(from, to, kind)
	end

	function Sim:answerProposal(id, pid, accept)
		for i, p in self.proposals do
			if p.id == pid and p.to == id then
				table.remove(self.proposals, i)
				if not accept then
					self:addRelation(p.from, p.to, -5)
					return true, "Proposta recusada"
				end
				return self:applyDeal(p.from, p.to, p.kind)
			end
		end
		return false, "Proposta não encontrada"
	end

	function Sim:stepTrade(dt)
		local c = self.cfg
		for id, r in self.routes do
			local A, B = self.nations[r.a], self.nations[r.b]
			if not A.alive or not B.alive then
				self.routes[id] = nil
			else
				r.cd -= dt
				if r.cd <= 0 then
					r.cd = c.TRADE_INTERVAL
					self.seq += 1
					self.convoys[#self.convoys + 1] = { id = self.seq, route = r, pos = 1, kind = r.kind, owner = r.a }
				end
			end
		end
		for i = #self.convoys, 1, -1 do
			local cv = self.convoys[i]
			local r = cv.route
			cv.pos += c.TRADE_SPEED * dt
			if not self.routes[r.id] then
				table.remove(self.convoys, i)
			elseif cv.pos >= #r.path then
				table.remove(self.convoys, i)
				local A, B = self.nations[r.a], self.nations[r.b]
				local base = c.TRADE_GOLD + ((A.pop or 0) + (B.pop or 0)) * 3
				local ga = math.floor(base * (1 + mod(A, "tradeGold")))
				local gb = math.floor(base * (1 + mod(B, "tradeGold")))
				A.gold += ga
				B.gold += gb
				self:addRelation(r.a, r.b, 1)
				if self.onTrainGold then
					local ax, ay = self:xy(r.path[#r.path])
					self.onTrainGold(r.a, ax, ay, ga)
					self.onTrainGold(r.b, ax, ay, gb)
				end
			end
		end
	end

	function Sim:convoyXY(cv)
		local p = cv.route.path
		return self:xy(p[math.clamp(math.floor(cv.pos), 1, #p)])
	end

	------------------------------------------------------------ mercado
	function Sim:postOffer(id, r, amount, price)
		local n = self.nations[id]
		if not D.RES[r] then
			return false, "Recurso inválido"
		end
		amount = math.floor(math.min(amount or 0, n.stock[r]))
		if amount < 1 then
			return false, "Estoque insuficiente"
		end
		price = math.clamp(price or self.market.ref[r], 0.01, 1e6)
		n.stock[r] -= amount -- sai do estoque do país (se vender demais, falta em casa)
		self.seq += 1
		local o = { id = self.seq, seller = id, res = r, amount = amount, price = price, t = self.time }
		self.market.offers[#self.market.offers + 1] = o
		self.market.offered[r] += amount
		return true, "Oferta publicada"
	end

	function Sim:cancelOffer(id, oid)
		for i, o in self.market.offers do
			if o.id == oid and o.seller == id then
				table.remove(self.market.offers, i)
				local n = self.nations[id]
				n.stock[o.res] += o.amount
				return true, "Oferta cancelada"
			end
		end
		return false, "Oferta não encontrada"
	end

	-- compra parte de uma oferta (jogador, IA ou mercado externo quando buyer == 0)
	function Sim:buyOffer(buyer, oid, amount)
		for i, o in self.market.offers do
			if o.id == oid then
				if o.seller == buyer then
					return false, "Essa oferta é sua"
				end
				amount = math.floor(math.min(amount or o.amount, o.amount))
				local B = buyer ~= 0 and self.nations[buyer] or nil
				if B then
					amount = math.floor(math.min(amount, B.gold / o.price))
				end
				if amount < 1 then
					return false, "Ouro insuficiente"
				end
				local total = amount * o.price
				local S = self.nations[o.seller]
				if B then
					B.gold -= total
					B.stock[o.res] += amount
					self:addRelation(buyer, o.seller, 1)
				end
				S.gold += total
				S.exported[o.res] += amount
				o.amount -= amount
				self.market.bought[o.res] += amount
				if o.amount < 1 then
					table.remove(self.market.offers, i)
				end
				if self.onSale then
					self.onSale(o.seller, buyer, o.res, amount, total)
				end
				return true, string.format("Comprou %d de %s por %d de ouro", amount, D.RES[o.res].name, total)
			end
		end
		return false, "Oferta não encontrada"
	end

	function Sim:stepMarket(dt)
		local m = self.market
		-- mercado externo: compra ofertas com preço justo; quanto mais caro, menos chance
		for i = #m.offers, 1, -1 do
			local o = m.offers[i]
			local S = self.nations[o.seller]
			if not S or not S.alive or self.time - o.t > 180 then
				table.remove(m.offers, i)
				if S and S.alive then
					S.stock[o.res] += o.amount
				end
			else
				local ref = m.ref[o.res] * (1 + 0.1 + mod(S, "marketSell"))
				local p = math.clamp(1 - (o.price / ref - 1) * 3, 0, 1) * 0.25
				if self.random() < p then
					self:buyOffer(0, o.id, math.max(1, o.amount * (0.2 + self.random() * 0.3)))
				end
			end
		end
		-- preço de referência segue oferta x procura
		for _, r in RES do
			local off, bo = m.offered[r], m.bought[r]
			local sig = math.clamp((bo - off * 0.5) / math.max(1, off), -1, 1)
			m.ref[r] = math.clamp(m.ref[r] * (1 + 0.04 * sig), D.RES[r].base * 0.4, D.RES[r].base * 3)
			m.offered[r], m.bought[r] = off * 0.5, bo * 0.5
		end
	end

	-- IA e livre mercado: vende sobras, compra faltas
	function Sim:aiTrade(n)
		local m = self.market
		for _, r in RES do
			local need = n.need[r]
			local surplus = n.stock[r] - need * 180 - n.prod[r] * 30
			if n.freeMarket then
				if surplus > 0 then
					local amt = surplus * 0.3
					n.stock[r] -= amt
					n.gold += amt * m.ref[r] * 0.9
					n.exported[r] += amt
				elseif n.stock[r] < need * 60 then
					local amt = math.min(need * 90 - n.stock[r], n.gold * 0.2 / (m.ref[r] * 1.1))
					if amt > 0 then
						n.gold -= amt * m.ref[r] * 1.1
						n.stock[r] += amt
					end
				end
			elseif n.isBot then
				if surplus > 0 then
					local has = false
					for _, o in m.offers do
						if o.seller == n.id and o.res == r then
							has = true
							break
						end
					end
					if not has then
						self:postOffer(n.id, r, surplus * 0.4, m.ref[r] * (0.9 + self.random() * 0.25))
					end
				elseif n.stock[r] < need * 60 then
					-- compra as ofertas mais baratas aceitáveis (de bots ou de jogadores)
					local want = need * 120 - n.stock[r]
					local best
					for _, o in m.offers do
						if o.res == r and o.seller ~= n.id and o.price <= m.ref[r] * 1.25 and (not best or o.price < best.price) then
							best = o
						end
					end
					if best and want > 0 then
						self:buyOffer(n.id, best.id, math.min(want, best.amount))
					end
				end
			end
		end
	end

	------------------------------------------------------------ pesquisa
	function Sim:skillCost(n, sk)
		return math.floor(sk.cost * (sk.tree == n.gov and 1 or 1.5))
	end

	-- um ramo fica bloqueado se a nação já tem qualquer nó de um ramo oposto
	function Sim:branchBlocked(n, tree, bi)
		for id in n.skills do
			local o = D.SKILLS[id]
			if o.tree == tree and (D.opposite(o.branch) == bi or D.opposite(bi) == o.branch) then
				for _, t in D.TREES do
					if t.key == tree then
						return t.branches[o.branch].name
					end
				end
			end
		end
		return nil
	end

	function Sim:canResearch(n, id)
		local sk = D.SKILLS[id]
		if not sk then
			return false, "Habilidade inválida"
		end
		if n.skills[id] then
			return false, "Já pesquisada"
		end
		for _, r in sk.req do
			if not n.skills[r] then
				return false, "Pesquise antes: " .. D.SKILLS[r].name
			end
		end
		local blocked = self:branchBlocked(n, sk.tree, sk.branch)
		if blocked then
			return false, "Caminho bloqueado: você seguiu a raiz " .. blocked
		end
		if n.rp < self:skillCost(n, sk) then
			return false, "Pontos de pesquisa insuficientes"
		end
		return true
	end

	function Sim:research(id, sid)
		local n = self.nations[id]
		local ok, err = self:canResearch(n, sid)
		if not ok then
			return false, err
		end
		n.rp -= self:skillCost(n, D.SKILLS[sid])
		n.skills[sid] = true
		self:recalcMods(n)
		return true, D.SKILLS[sid].name .. " pesquisada!"
	end

	------------------------------------------------------------ leis e parlamento
	function Sim:lawAllowed(n, law)
		return law.govs == nil or law.govs[n.gov] == true
	end

	function Sim:makeParliament(n)
		local list = {}
		local weights, total = {}, 0
		for i = 1, #D.PARTIES[n.gov] do
			weights[i] = 0.5 + self.random()
			total += weights[i]
		end
		local left = 100
		for i, p in D.PARTIES[n.gov] do
			local seats = i == #D.PARTIES[n.gov] and left or math.floor(weights[i] / total * 100 + 0.5)
			left -= seats
			list[i] = { name = p.name, ideo = p.ideo, amb = p.amb, seats = seats, bias = (self.random() - 0.5) * 0.4 }
		end
		n.parliament = list
		n.bill = nil
	end

	function Sim:partySupport(n, i)
		local p = n.parliament[i]
		local bill = n.bill
		local law = D.LAW_BY_ID[bill.law]
		local s = 0
		for k, w in p.ideo do
			s += w * (law.sup[k] or 0)
		end
		if bill.repeal then
			s = -s
		end
		return s + p.bias + (bill.mods[i] or 0)
	end

	function Sim:proposeLaw(id, lawId, repeal)
		local n = self.nations[id]
		local law = D.LAW_BY_ID[lawId]
		if not law then
			return false, "Lei inválida"
		end
		if not repeal and not self:lawAllowed(n, law) then
			return false, "Essa lei não existe no " .. D.GOVS[n.gov].name
		end
		if repeal and not n.laws[lawId] then
			return false, "Essa lei não está em vigor"
		end
		if not repeal and n.laws[lawId] then
			return false, "Essa lei já está em vigor"
		end
		if not n.parliament then
			self:makeParliament(n)
		end
		n.bill = { law = lawId, repeal = repeal == true, mods = {} }
		return true, (repeal and "Revogação" or "Projeto") .. " de " .. law.name .. " enviado à câmara"
	end

	function Sim:lobby(id, partyIdx, how)
		local n = self.nations[id]
		if not n.bill or not n.parliament or not n.parliament[partyIdx] then
			return false, "Não há projeto em votação"
		end
		local p = n.parliament[partyIdx]
		local gov, amb = D.GOVS[n.gov], D.AMBITIONS[p.amb]
		local roll = 0.7 + self.random() * 0.6
		if how == "persuade" then
			if n.influence < 15 then
				return false, "Influência insuficiente (15)"
			end
			n.influence -= 15
			local add = 0.35 * gov.persuade * amb.persuade * (1 + mod(n, "persuade")) * roll
			n.bill.mods[partyIdx] = (n.bill.mods[partyIdx] or 0) + add
			return true, string.format("%s ficou mais favorável (+%d)", p.name, math.floor(add * 100))
		elseif how == "bribe" then
			local cost = math.floor(1500 + n.gold * 0.05)
			if n.gold < cost then
				return false, "Ouro insuficiente (" .. cost .. ")"
			end
			n.gold -= cost
			if self.random() < gov.scandal then
				n.happy = math.max(0, n.happy - 10)
				n.influence = math.max(0, n.influence - 15)
				n.bill.mods[partyIdx] = (n.bill.mods[partyIdx] or 0) - 0.3
				self:event("Escândalo de propina em " .. n.name .. "!", "error", id)
				return false, "Escândalo! A propina vazou: -10 de felicidade e " .. p.name .. " ficou contra"
			end
			local add = 0.45 * gov.bribe * amb.bribe * (1 + mod(n, "bribe")) * roll
			n.bill.mods[partyIdx] = (n.bill.mods[partyIdx] or 0) + add
			return true, string.format("Propina aceita por %s (+%d) — custou %d", p.name, math.floor(add * 100), cost)
		end
		return false, "Ação inválida"
	end

	function Sim:enactLaw(n, lawId, repeal)
		if repeal then
			n.laws[lawId] = nil
		else
			n.laws[lawId] = true
		end
		self:recalcMods(n)
	end

	function Sim:vote(id)
		local n = self.nations[id]
		if not n.bill then
			return false, "Não há projeto em votação"
		end
		local yes = 0
		for i, p in n.parliament do
			if self:partySupport(n, i) > 0 then
				yes += p.seats
			end
		end
		local bill = n.bill
		n.bill = nil
		local law = D.LAW_BY_ID[bill.law]
		local need = D.GOVS[n.gov].threshold * 100
		if yes <= need then
			return false, string.format("A câmara rejeitou %s (%d de %d votos necessários)", law.name, yes, math.floor(need) + 1)
		end
		if not bill.repeal then
			if n.gold < law.cost then
				return false, "Aprovada, mas falta ouro para implementar (" .. law.cost .. ")"
			end
			n.gold -= law.cost
		end
		self:enactLaw(n, bill.law, bill.repeal)
		return true, string.format("%s %s! (%d votos)", law.name, bill.repeal and "revogada" or "aprovada", yes)
	end

	function Sim:changeRegime(n, gov, forced)
		n.gov = gov
		for id in n.laws do
			if not self:lawAllowed(n, D.LAW_BY_ID[id]) then
				n.laws[id] = nil
			end
		end
		if forced then
			n.laws = {}
		end
		self:recalcMods(n)
		self:makeParliament(n)
		-- relações mudam com o regime
		for k in self.rel do
			local a, b = k // 1000, k % 1000
			if a == n.id or b == n.id then
				self.rel[k] = nil
			end
		end
	end

	function Sim:requestRegime(id, gov)
		local n = self.nations[id]
		if not D.GOVS[gov] or gov == n.gov then
			return false, "Regime inválido"
		end
		if n.influence < 120 then
			return false, "Influência insuficiente (120)"
		end
		n.influence -= 120
		n.happy = math.max(0, n.happy - 20)
		self:changeRegime(n, gov, false)
		self:event(n.name .. " mudou para o " .. D.GOVS[gov].name .. "!", "war", id)
		return true, "Novo regime: " .. D.GOVS[gov].name
	end

	function Sim:revolution(n)
		local opts = {}
		for _, g in D.GOV_ORDER do
			if g ~= n.gov then
				opts[#opts + 1] = g
			end
		end
		local gov = opts[self:randInt(#opts)]
		n.troops *= 0.7
		n.gold *= 0.6
		n.happy = 55
		n.unrest = 0
		self:changeRegime(n, gov, true)
		self:event("REVOLUÇÃO em " .. n.name .. "! O povo instaurou o " .. D.GOVS[gov].name, "kill", n.id)
	end

	------------------------------------------------------------ felicidade e passo de 1 s
	function Sim:civTick(n, dt)
		self:computeEconomy(n)
		local parts = {}
		local short = 0
		for _, r in RES do
			n.stock[r] = math.max(0, n.stock[r] + (n.prod[r] - n.need[r]) * dt)
			local s = n.stock[r] < n.need[r] * 20 and n.need[r] > 0.01
			n.short[r] = s
			if s then
				local pen = (r == "food" and 18) or (r == "goods" and 8) or 3
				short += pen
				parts[#parts + 1] = { "Falta de " .. D.RES[r].name, -pen }
			end
			n.exported[r] *= 0.985
		end
		-- vender demais o que falta em casa revolta o povo
		for _, r in { "food", "goods" } do
			if n.short[r] and n.exported[r] > n.need[r] * 30 then
				parts[#parts + 1] = { "Exportou " .. D.RES[r].name .. " que faltava", -10 }
				short += 10
			end
		end
		-- população
		local g = n.short.food and -0.0005 or 0.00025 * (1 + mod(n, "popGrowth"))
		n.pop = math.max(0.01, n.pop * (1 + g * dt))
		-- felicidade
		n.warLoss = (n.warLoss or 0) * 0.99
		local war = math.min(20, n.warLoss * 0.04)
		local h = 55 + mod(n, "happy") - short - war + math.min(8, n.gold / 25000)
		table.insert(parts, 1, { "Base", 55 })
		if mod(n, "happy") ~= 0 then
			parts[#parts + 1] = { "Leis e habilidades", mod(n, "happy") }
		end
		if war > 0.5 then
			parts[#parts + 1] = { "Território perdido na guerra", -war }
		end
		if n.gold > 2500 then
			parts[#parts + 1] = { "Prosperidade", math.min(8, n.gold / 25000) }
		end
		n.happyTarget = math.clamp(h, 0, 100)
		n.happyParts = parts
		n.happy += (n.happyTarget - n.happy) * math.min(1, 0.05 * dt)
		-- revolução
		if n.happy < 20 and not n.martial then
			n.unrest = (n.unrest or 0) + dt
			if self.random() < (20 - n.happy) / 20 * 0.006 * dt then
				self:revolution(n)
			end
		else
			n.unrest = 0
		end
		n.influence = math.min(300, n.influence + (0.2 + n.happy / 500) * (1 + mod(n, "influence")) * dt)
		n.rp += (0.5 + n.pop * 0.004 + n.counts.city * 0.3) * math.max(0.1, 1 + mod(n, "research")) * dt
	end

	-- IA: pesquisa, leis e diplomacia entre bots
	function Sim:aiCiv(n, dt)
		-- pesquisa: prefere a árvore do próprio regime
		local options = {}
		for id, sk in D.SKILLS do
			if not n.skills[id] and (sk.tree == n.gov or self.random() < 0.05) then
				local ok = self:canResearch(n, id)
				if ok then
					options[#options + 1] = id
				end
			end
		end
		if #options > 0 then
			self:research(n.id, options[self:randInt(#options)])
		end
		n.aiLaw -= dt
		if n.aiLaw <= 0 then
			n.aiLaw = 60 + self.random() * 120
			local law = D.LAWS[self:randInt(#D.LAWS)]
			local s = law.sup[n.gov] or 0
			if not n.laws[law.id] and s > 0.3 and self:lawAllowed(n, law) and n.gold > law.cost * 2 then
				n.gold -= law.cost
				self:enactLaw(n, law.id, false)
			elseif n.laws[law.id] and s < 0 then
				self:enactLaw(n, law.id, true)
			end
			-- bots infelizes aprovam leis que acalmam o povo
			if n.happy < 30 and not n.laws.welfare and self:lawAllowed(n, D.LAW_BY_ID.welfare) then
				self:enactLaw(n, "welfare", false)
			end
		end
		n.aiDip -= dt
		if n.aiDip <= 0 then
			n.aiDip = 60 + self.random() * 120
			local nb = self:neighborsOf(n.id)
			for o in nb do
				local v = o ~= 0 and self.nations[o]
				if v and v.alive and v.isBot and self.random() < 0.3 then
					local p = self:pact(n.id, o)
					if not p.trade and self:aiAccepts(n.id, o, "trade") and self:routeCount() < self.cfg.MAX_AI_ROUTES then
						self:applyDeal(n.id, o, "trade")
					elseif self:relation(n.id, o) > 30 and not p.napUntil then
						self:applyDeal(n.id, o, "nap")
					end
					break
				elseif v and v.alive and not v.isBot and self.random() < 0.15 then
					-- bots também propõem coisas aos jogadores
					local kind = self:relation(n.id, o) > 35 and "alliance" or "trade"
					if not self:pact(n.id, o).trade or kind == "alliance" then
						self.seq += 1
						self.proposals[#self.proposals + 1] = { id = self.seq, from = n.id, to = o, kind = kind, t = self.time }
					end
					break
				end
			end
		end
	end

	function Sim:routeCount()
		local c = 0
		for _ in self.routes do
			c += 1
		end
		return c
	end

	function Sim:civStep(dt)
		self:stepConstruction(dt)
		self:stepTrade(dt)
		self.civAcc += dt
		if self.civAcc >= 1 then
			local step = self.civAcc
			self.civAcc = 0
			for _, n in self.nations do
				if n.alive and n.tiles > 0 then
					self:civTick(n, step)
					if n.isBot then
						self:aiCiv(n, step)
					end
				end
			end
			-- propostas vencem em 60 s
			for i = #self.proposals, 1, -1 do
				local p = self.proposals[i]
				if self.time - p.t > 60 or not self.nations[p.from].alive then
					table.remove(self.proposals, i)
				end
			end
		end
		self.marketAcc += dt
		if self.marketAcc >= 5 then
			self.marketAcc = 0
			for _, n in self.nations do
				if n.alive and n.tiles > 0 and (n.isBot or n.freeMarket) then
					self:aiTrade(n)
				end
			end
			self:stepMarket(5)
		end
	end
end

return Civ
