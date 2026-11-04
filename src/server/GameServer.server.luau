-- Servidor: roda a Sim e manda aos clientes só o que muda (donos das células em buffer).
-- Nada de Parts por célula: o mapa é desenhado no cliente numa única imagem.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Sim = require(Shared:WaitForChild("Sim"))
local WorldMap = require(Shared:WaitForChild("WorldMap"))
local Civ = require(Shared:WaitForChild("Civ"))
local D = require(Shared:WaitForChild("CivData"))
Civ.install(Sim)

Players.CharacterAutoLoads = false

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function remote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local Action = remote("Action") -- cliente -> servidor
local State = remote("State") -- estado das nações (0,4 s)
local Notify = remote("Notify") -- mensagens
local Effect = remote("Effect") -- efeitos (míssil)
local MapFull = remote("MapFull") -- dono de todas as células (entrada/nova rodada)
local MapDelta = remote("MapDelta") -- células que mudaram
local NationsEv = remote("Nations")
local CivEv = remote("Civ") -- dados de civilização do jogador (1 s)
local RailsEv = remote("Rails") -- trilhos (células), enviados quando surgem -- nome/cor/jogador de cada nação (só quando muda)
remotes.Parent = ReplicatedStorage

local sim
local round = 0
local playerNation: { [Player]: number } = {}
local pending: { [number]: number } = {}
local pendingCount = 0
local anchors = {}
local boatSeq = 0

local function fullBuffer()
	local n = sim.W * sim.H
	local b = buffer.create(n)
	for t = 1, n do
		local o = sim.owner[t]
		if o ~= 0 then
			buffer.writeu8(b, t - 1, o)
		end
	end
	return b
end

local function railsBuffer(list)
	local b = buffer.create(#list * 4)
	for i, t in list do
		buffer.writeu32(b, (i - 1) * 4, t - 1)
	end
	return b
end

local function sendFull(plr)
	MapFull:FireClient(plr, round, fullBuffer())
	local all = {}
	for t in sim.rails do
		all[#all + 1] = t
	end
	RailsEv:FireClient(plr, round, railsBuffer(all), true)
end

local function flushDelta()
	if sim and #sim.railsNew > 0 then
		RailsEv:FireAllClients(round, railsBuffer(sim.railsNew), false)
		table.clear(sim.railsNew)
	end
	if pendingCount == 0 then
		return
	end
	-- 5 bytes por célula: índice (u32) + dono (u8)
	local b = buffer.create(pendingCount * 5)
	local i = 0
	for t, o in pending do
		buffer.writeu32(b, i, t - 1)
		buffer.writeu8(b, i + 4, o)
		i += 5
	end
	table.clear(pending)
	pendingCount = 0
	MapDelta:FireAllClients(round, b)
end

-- dados fixos das nações (nome, cor, quem joga): mandados só quando mudam
local function nationsMeta()
	local list = {}
	for _, n in sim.nations do
		if n.alive then
			list[#list + 1] = {
				i = n.id,
				n = n.name,
				c = Color3.fromRGB(n.color[1], n.color[2], n.color[3]),
				u = if n.isBot then 0 else n.userId,
				pl = if n.isBot then nil else n.pl,
			}
		end
	end
	return list
end

local function sendMeta(plr)
	if plr then
		NationsEv:FireClient(plr, round, nationsMeta())
	else
		NationsEv:FireAllClients(round, nationsMeta())
	end
end

local function releaseNation(plr)
	local id = playerNation[plr]
	playerNation[plr] = nil
	local n = id and sim and sim.nations[id]
	if n then
		n.isBot = true -- volta para a IA
		n.userId = 0
		n.pl = nil
	end
end

local function newRound()
	round += 1
	sim = Sim.new(Config, os.time() + round * 7919, WorldMap)
	sim:setupCountries()
	sim:civInit(WorldMap)
	table.clear(pending)
	pendingCount = 0
	table.clear(anchors)
	table.clear(playerNation)
	sim.onOwner = function(t, o)
		if pending[t] == nil then
			pendingCount += 1
		end
		pending[t] = o
	end
	-- ouro dos trens: só o dono vê o "+ouro" subindo da parada
	sim.onTrainGold = function(owner, x, y, gold)
		local n = sim.nations[owner]
		if n and not n.isBot then
			for plr, id in playerNation do
				if id == owner then
					Effect:FireClient(plr, "gold", x, y, math.floor(gold))
				end
			end
		end
	end
	sim.onSale = function(seller, buyer, res, amount, total)
		for plr, id in playerNation do
			if id == seller then
				local who = buyer == 0 and "o mercado externo" or sim.nations[buyer].name
				Notify:FireClient(plr, string.format("Vendeu %d de %s para %s por %d", amount, D.RES[res].name, who, total), "ok")
			end
		end
	end
	sim.onMissile = function(x, y, r, _, down)
		Effect:FireAllClients(down and "intercept" or "missile", x, y, r)
	end
	sim.onEvent = function(text, kind, a, b)
		-- com ~180 países, só avisa o que envolve jogadores (ou o fim da rodada)
		if kind == "kill" or kind == "missile" or kind == "info" then
			local na, nb = a and sim.nations[a], b and sim.nations[b]
			if not ((na and not na.isBot) or (nb and not nb.isBot)) then
				return
			end
		end
		Notify:FireAllClients(text, kind)
	end
	for id, n in sim.nations do
		local x, y = sim:anchor(n)
		anchors[id] = { x, y }
	end
	ReplicatedStorage:SetAttribute("Round", round)
	for _, plr in Players:GetPlayers() do
		sendMeta(plr)
		sendFull(plr)
	end
	Notify:FireAllClients("Nova rodada! Escolha a sua nação.", "start")
end

Players.PlayerAdded:Connect(function(plr)
	if not sim then
		return
	end
	flushDelta()
	sendMeta(plr)
	sendFull(plr)
end)

Players.PlayerRemoving:Connect(function(plr)
	if playerNation[plr] then
		releaseNation(plr)
		sendMeta()
	end
end)

-- escolher (ou trocar de) nação
local function chooseNation(plr, id)
	local n = sim.nations[id]
	if not n or not n.alive or n.tiles == 0 then
		return false, "Essa nação não existe mais"
	end
	if not n.isBot then
		return false, "Essa nação já tem um jogador"
	end
	local cur = playerNation[plr]
	local curN = cur and sim.nations[cur]
	if curN and curN.alive and sim.phase ~= "select" then
		return false, "Você já comanda " .. curN.name .. " nesta rodada"
	end
	releaseNation(plr)
	n.isBot = false
	n.userId = plr.UserId
	n.pl = plr.DisplayName
	playerNation[plr] = id
	-- quem assume um país já recebe o 1º Exército (só se ataca com exércitos)
	if #n.armies == 0 then
		local gen = n.generals[1]
		sim:createArmy(id, math.floor(n.troops * 0.3), gen and gen.id or nil)
	end
	sendMeta()
	Notify:FireAllClients(plr.DisplayName .. " assumiu " .. n.name .. "!", "ok")
	return true
end

-- o cliente pede o mapa completo quando termina de carregar
local lastAction: { [Player]: number } = {}
Action.OnServerEvent:Connect(function(plr, kind, x, y, extra)
	if kind == "sync" then
		if sim then
			flushDelta()
			sendMeta(plr)
			sendFull(plr)
		end
		return
	end
	if typeof(kind) ~= "string" or typeof(x) ~= "number" or typeof(y) ~= "number" then
		return
	end
	if x ~= x or y ~= y then
		return
	end
	local now = os.clock()
	if (lastAction[plr] or 0) > now - 0.08 then
		return
	end
	lastAction[plr] = now
	if not sim then
		return
	end
	x, y = math.floor(x), math.floor(y)
	local ok, err
	if kind == "choose" then
		ok, err = chooseNation(plr, x)
		if not ok then
			Notify:FireClient(plr, err, "error")
		end
		return
	end
	local id = playerNation[plr]
	if not id then
		Notify:FireClient(plr, "Escolha uma nação primeiro", "error")
		return
	end
	if kind == "attack" then
		Notify:FireClient(plr, "Ataques são feitos com exércitos: escolha um no cartão Exércitos", "error")
		return
	elseif kind == "attack_legacy" then
		local pct = typeof(extra) == "number" and extra or 0.25
		ok, err = sim:attack(id, x, y, math.clamp(pct, 0.01, 1))
		if ok and err == "boat" then
			Notify:FireClient(plr, "⛵ Barco a caminho!", "ok")
		end
		err = not ok and err or nil
	elseif kind == "build" then
		if typeof(extra) ~= "string" or not Config.BUILDINGS[extra] then
			return
		end
		ok, err = sim:build(id, extra, x, y)
		if ok and extra ~= "missile" then
			Notify:FireClient(plr, Config.BUILDINGS[extra].name .. " em construção (" .. (Config.BUILDINGS[extra].time or 0) .. " s)", "ok")
		end
	elseif kind == "civ" then
		if typeof(extra) ~= "table" or typeof(extra.op) ~= "string" then
			return
		end
		local e = extra
		local function num(v)
			return typeof(v) == "number" and v == v and v or 0
		end
		local function str(v)
			return typeof(v) == "string" and v or ""
		end
		local op = e.op
		local msg
		if op == "research" then
			ok, msg = sim:research(id, str(e.id))
		elseif op == "law" then
			ok, msg = sim:proposeLaw(id, str(e.law), e.repeal == true)
		elseif op == "lobby" then
			ok, msg = sim:lobby(id, num(e.party), str(e.how))
		elseif op == "vote" then
			ok, msg = sim:vote(id)
		elseif op == "regime" then
			ok, msg = sim:requestRegime(id, str(e.gov))
		elseif op == "offer" then
			ok, msg = sim:postOffer(id, str(e.res), num(e.amount), num(e.price))
		elseif op == "cancel_offer" then
			ok, msg = sim:cancelOffer(id, num(e.id))
		elseif op == "buy" then
			ok, msg = sim:buyOffer(id, num(e.id), num(e.amount))
		elseif op == "dip" then
			local okk = ({ trade = true, nap = true, alliance = true, aid = true, gift = true, war = true, cancel_trade = true })[str(e.kind)]
			if not okk then
				return
			end
			ok, msg = sim:diplomacy(id, num(e.target), str(e.kind))
		elseif op == "answer" then
			ok, msg = sim:answerProposal(id, num(e.id), e.accept == true)
		elseif op == "army_create" then
			ok, msg = sim:createArmy(id, num(e.troops), typeof(e.gen) == "number" and e.gen or nil)
		elseif op == "army_send" then
			ok, msg = sim:sendArmy(id, num(e.army), math.floor(num(e.x)), math.floor(num(e.y)))
			if ok and msg == "boat" then
				msg = "⛵ Exército embarcado!"
			elseif ok then
				msg = "Exército a caminho!"
			end
		elseif op == "army_disband" then
			ok, msg = sim:disbandArmy(id, num(e.army))
			msg = msg or "Exército desfeito"
		elseif op == "army_reinforce" then
			ok, msg = sim:reinforceArmy(id, num(e.army), num(e.troops))
			msg = msg or "Exército reforçado"
		elseif op == "recruit_general" then
			ok, msg = sim:recruitGeneral(id)
		else
			return
		end
		if msg then
			Notify:FireClient(plr, msg, ok and "ok" or "error")
		end
		return
	else
		return
	end
	if not ok and err then
		Notify:FireClient(plr, err, "error")
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	lastAction[plr] = nil
end)

---------------------------------------------------------------- estado
local function publicState()
	local list = {}
	for _, n in sim.nations do
		if n.alive and n.tiles > 0 then
			local a = anchors[n.id]
			-- { id, células, tropas, âncora x, âncora y }
			list[#list + 1] = { n.id, n.tiles, math.floor(n.troops), a and a[1] or -1, a and a[2] or -1 }
		end
	end
	local blds = {}
	for t, b in sim.buildings do
		blds[#blds + 1] = { t, b.kind, b.owner, if b.done == false then math.floor((1 - b.left / math.max(1, b.total or 1)) * 100) / 100 else 1 }
	end
	local boats = {}
	for _, b in sim.boats do
		if not b.id then
			boatSeq += 1
			b.id = boatSeq
		end
		local x, y = sim:boatXY(b)
		boats[#boats + 1] = { x, y, b.from, math.floor(b.troops), b.id }
	end
	-- ataques: rótulo com as tropas na linha de frente
	local atks = {}
	for _, a in sim.attacks do
		if a.fx then
			if not a.id then
				sim.seq += 1
				a.id = sim.seq
			end
			atks[#atks + 1] = { a.id, math.floor(a.fx * 10) / 10, math.floor(a.fy * 10) / 10, math.floor(a.troops), a.from }
		end
	end
	local flights = {}
	for _, f in sim.flights do
		flights[#flights + 1] = { f.id, f.sx, f.sy, f.tx, f.ty, f.t, f.dur, f.from }
	end
	local trains = {}
	for _, tr in sim.trains do
		local x, y = sim:trainXY(tr)
		trains[#trains + 1] = { tr.id, math.floor(x * 10) / 10, math.floor(y * 10) / 10, tr.owner, 1 }
	end
	for _, cv in sim.convoys do
		local x, y = sim:convoyXY(cv)
		trains[#trains + 1] = { cv.id, x, y, cv.owner, cv.kind == "boat" and 2 or 1 }
	end
	return list, blds, boats, atks, flights, trains
end

local function privateState(id)
	local n = sim.nations[id]
	if not n then
		return nil
	end
	local costs = {}
	for _, k in Config.BUILD_ORDER do
		costs[k] = sim:buildCost(id, k)
	end
	local atk = {}
	for _, a in sim.attacks do
		if a.from == id then
			atk[#atk + 1] = { to = a.to, tr = math.floor(a.troops) }
		end
	end
	local nb = {}
	for o in sim:neighborsOf(id) do
		nb[#nb + 1] = o
	end
	return {
		id = id,
		alive = n.alive,
		spawned = n.spawned,
		troops = math.floor(n.troops),
		max = math.floor(sim:maxTroops(n)),
		rate = math.floor(n.rate),
		gold = math.floor(n.gold),
		goldRate = math.floor(n.goldRate),
		tiles = n.tiles,
		costs = costs,
		attacks = atk,
		nb = nb,
		coast = sim:hasCoast(id),
		silo = n.counts.silo > 0,
	}
end

local function broadcast()
	local pub, blds, boats, atks, flights, trains = publicState()
	for _, plr in Players:GetPlayers() do
		local id = playerNation[plr]
		State:FireClient(plr, {
			round = round,
			phase = sim.phase,
			left = math.max(0, math.ceil(sim.phaseLeft)),
			prot = math.max(0, math.ceil(sim.protectedUntil - sim.time)),
			land = sim.landCount,
			winner = sim.winner,
			nations = pub,
			buildings = blds,
			boats = boats,
			attacks = atks,
			flights = flights,
			trains = trains,
			me = id and privateState(id) or nil,
		})
	end
end

-- cantos de um caminho só horizontal/vertical (para desenhar a rota)
local function corners(path)
	local out = {}
	local pdx, pdy
	for i, t in path do
		local x, y = sim:xy(t)
		if i == 1 or i == #path then
			out[#out + 1] = { x, y }
		else
			local nx, ny = sim:xy(path[i + 1])
			local dx, dy = nx - x, ny - y
			if dx ~= pdx or dy ~= pdy then
				out[#out + 1] = { x, y }
			end
			pdx, pdy = dx, dy
		end
	end
	return out
end

local function civState(id)
	local n = sim.nations[id]
	if not n or not n.alive then
		return nil
	end
	local m = sim.market
	local skills, laws = {}, {}
	for k in n.skills do
		skills[#skills + 1] = k
	end
	for k in n.laws do
		laws[#laws + 1] = k
	end
	local parl
	if n.parliament then
		parl = {}
		for i, p in n.parliament do
			parl[i] = { name = p.name, seats = p.seats, amb = p.amb, sup = n.bill and sim:partySupport(n, i) or nil }
		end
	end
	local armies = {}
	for _, a in n.armies do
		armies[#armies + 1] = { id = a.id, name = a.name, troops = math.floor(a.troops), gen = a.gen, tiles = a.tiles, busy = a.busy }
	end
	local gens = {}
	for _, g in n.generals do
		gens[#gens + 1] = { id = g.id, name = g.name, trait = g.trait, level = g.level, xp = math.floor(g.xp) }
	end
	-- relações e pactos com todas as nações vivas
	local rel, pacts = {}, {}
	for oid, o in sim.nations do
		if oid ~= id and o.alive and o.tiles > 0 then
			rel[tostring(oid)] = math.floor(sim:relation(id, oid)) -- chaves em texto: o Roblox não manda bem tabelas numéricas esparsas
			local p = sim.pacts[Civ.pairKey(id, oid)]
			if p and (p.alliance or (p.napUntil or 0) > sim.time or p.trade) then
				pacts[tostring(oid)] = { alliance = p.alliance or nil, nap = (p.napUntil or 0) > sim.time and math.floor(p.napUntil - sim.time) or nil, trade = p.trade ~= nil or nil }
			end
		end
	end
	local props = {}
	for _, p in sim.proposals do
		if p.to == id then
			props[#props + 1] = { id = p.id, from = p.from, kind = p.kind, left = math.floor(60 - (sim.time - p.t)) }
		end
	end
	local routes = {}
	for _, r in sim.routes do
		if r.a == id or r.b == id then
			r.corners = r.corners or corners(r.path)
			routes[#routes + 1] = { id = r.id, other = r.a == id and r.b or r.a, kind = r.kind, pts = r.kind == "train" and r.corners or nil }
		end
	end
	-- mercado: as 8 ofertas mais baratas de cada recurso + as minhas
	local offers, mine = {}, {}
	for _, r in D.RESOURCES do
		local list = {}
		for _, o in m.offers do
			if o.res == r and o.seller ~= id then
				list[#list + 1] = o
			end
		end
		table.sort(list, function(a, b)
			return a.price < b.price
		end)
		for i = 1, math.min(8, #list) do
			local o = list[i]
			offers[#offers + 1] = { id = o.id, seller = o.seller, res = o.res, amount = math.floor(o.amount), price = math.floor(o.price * 100) / 100 }
		end
	end
	for _, o in m.offers do
		if o.seller == id then
			mine[#mine + 1] = { id = o.id, res = o.res, amount = math.floor(o.amount), price = math.floor(o.price * 100) / 100 }
		end
	end
	local ref = {}
	for k, v in m.ref do
		ref[k] = math.floor(v * 100) / 100
	end
	return {
		pop = n.pop,
		happy = n.happy,
		happyTarget = n.happyTarget or n.happy,
		happyParts = n.happyParts,
		stock = n.stock,
		prod = n.prod,
		need = n.need,
		short = n.short,
		rp = math.floor(n.rp),
		skills = skills,
		gov = n.gov,
		laws = laws,
		influence = math.floor(n.influence),
		parliament = parl,
		bill = n.bill and { law = n.bill.law, repeal = n.bill.repeal } or nil,
		armies = armies,
		generals = gens,
		rel = rel,
		pacts = pacts,
		proposals = props,
		routes = routes,
		market = { ref = ref, offers = offers, mine = mine },
		unrest = n.unrest or 0,
	}
end

newRound()

local acc, sendAcc, deltaAcc, anchorAcc, civAcc = 0, 0, 0, 1, 0
RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 0.25)
	acc += dt
	while acc >= Config.TICK do
		acc -= Config.TICK
		sim:step(Config.TICK)
	end
	if sim.phase == "end" and sim.phaseLeft <= 0 then
		newRound()
		return
	end
	deltaAcc += dt
	if deltaAcc >= 0.1 then
		deltaAcc = 0
		flushDelta()
	end
	anchorAcc += dt
	if anchorAcc >= 1 then
		anchorAcc = 0
		for id, n in sim.nations do
			if n.alive and n.tiles > 0 then
				local x, y = sim:anchor(n)
				anchors[id] = { x, y }
			end
		end
	end
	sendAcc += dt
	if sendAcc >= 0.4 then
		sendAcc = 0
		broadcast()
	end
	civAcc += dt
	if civAcc >= 1 then
		civAcc = 0
		for plr, id in playerNation do
			local cs = civState(id)
			if cs then
				CivEv:FireClient(plr, round, cs)
			end
		end
	end
end)
