-- Rodado por tools/run_tests.sh (Config, WorldMap e Sim são injetados antes deste trecho)
local cfg = table.clone(Config)

-- 1) mapa procedural com nascimento livre (modo antigo, sanidade)
do
	local g = Sim.new(cfg, 777)
	assert(g.landCount > 1000)
	local id = g:addNation({ name = "Teste" })
	assert(g:randomSpawn(id), "não nasceu no mapa procedural")
	g:validate()
end

-- 2) países reais
local tw = os.clock()
local sim = Sim.new(cfg, 12345, WorldMap)
sim:setupCountries()
sim:civInit(WorldMap)
print(string.format("mapa-múndi + %d países em %.0f ms", sim.nationCount, (os.clock() - tw) * 1000))
sim:validate()
assert(sim.nationCount > 150 and sim.nationCount <= 255, "quantidade de países fora do esperado")

local unowned = 0
for _, t in sim.landList do
	if sim.owner[t] == 0 then
		unowned += 1
	end
end
assert(unowned == 0, "terra sem dono no início: " .. unowned)

local clashes = 0
for id, n in sim.nations do
	for o in sim:neighborsOf(id) do
		if o ~= 0 and sim.nations[o].colorIndex == n.colorIndex then
			clashes += 1
		end
	end
end
print("pares de vizinhos com a mesma cor:", clashes // 2)
assert(clashes == 0, "vizinhos com a mesma cor")

local player
for id, n in sim.nations do
	if n.name == "Brasil" then
		player = id
	end
end
assert(player, "Brasil não encontrado")
sim.nations[player].isBot = false
print("Brasil:", sim.nations[player].tiles, "células,", math.floor(sim.nations[player].troops), "tropas")

local events, kills = 0, 0
sim.onEvent = function(_, kind)
	events += 1
	if kind == "kill" then
		kills += 1
	end
end

while sim.phase == "select" do
	sim:step(cfg.TICK)
end
assert(sim:isProtected())
do
	local nb = next(sim:neighborsOf(player))
	local t
	for c in sim.nations[nb].tileSet do
		t = c
		break
	end
	local x, y = sim:xy(t)
	local ok = sim:attack(player, x, y, 0.25)
	assert(not ok, "ataque deveria ser bloqueado na proteção")
end

-- construções, civilização, mercado, leis, diplomacia, exércitos e antiaéreo (no Brasil, após a proteção)
while sim:isProtected() do
	sim:step(cfg.TICK)
end
local function runFor(sec)
	for _ = 1, math.floor(sec / cfg.TICK) do
		sim:step(cfg.TICK)
	end
end
do
	local br = sim.nations[player]
	br.gold = 1e7
	print(string.format("Brasil: pop %.0f mi, felicidade %.0f, regime %s, comida +%.1f/s (consumo %.1f/s)", br.pop, br.happy, br.gov, br.prod.food, br.need.food))
	local trainGold, trainStops = 0, 0
	sim.onTrainGold = function(owner, _, _, g)
		if owner == player then
			trainGold += g
			trainStops += 1
		end
	end
	-- míssil sem lançador falha
	local anyEnemy
	for o in sim:neighborsOf(player) do
		if o ~= 0 then
			anyEnemy = o
			break
		end
	end
	local et = next(sim.nations[anyEnemy].front)
	local ex, ey = sim:xy(et)
	local ok, err = sim:build(player, "missile", ex, ey)
	assert(not ok and string.find(err, "Lançador"), "míssil sem lançador deveria falhar")
	-- porto só na costa
	local inland, coastal
	for t in br.tileSet do
		if not sim.coast[t] and not sim.buildings[t] and not inland and not br.front[t] then
			inland = t
		end
		if sim.coast[t] and not br.front[t] and not sim.buildings[t] then
			coastal = t
		end
	end
	local ix, iy = sim:xy(inland)
	assert(not sim:build(player, "port", ix, iy), "porto no interior deveria falhar")
	local cx, cy = sim:xy(coastal)
	assert(sim:build(player, "port", cx, cy), "porto na costa falhou")
	assert(sim:build(player, "factory", ix, iy), "fábrica falhou")
	-- construção leva tempo: ainda não conta
	assert(br.counts.factory == 0 and br.pending.factory == 1, "fábrica deveria estar em obra")
	local built = 0
	for t in br.tileSet do
		local x, y = sim:xy(t)
		if built < 3 and not sim.buildings[t] and not br.front[t] and sim:dist(x, y, ix, iy) > 4 and sim:dist(x, y, ix, iy) < 25 and sim:railPath(ix, iy, x, y) then
			if sim:build(player, "city", x, y) then
				built += 1
			end
		end
	end
	assert(built == 3, "cidades não construídas: " .. built)
	assert(sim:build(player, "silo", ix + 1, iy) or sim:build(player, "silo", ix, iy + 1) or sim:build(player, "silo", ix - 1, iy), "lançador falhou")
	br.troops = 5e7 -- defesa altíssima: nenhum vizinho toma as obras durante o teste
	runFor(41)
	assert(br.counts.factory == 1 and br.counts.city == 3 and br.counts.silo == 1, "construções não terminaram")
	print("construções prontas após o tempo de obra: fábrica, 3 cidades, porto e lançador")
	sim.buildings[inland].cd = 0.5
	-- míssil
	ok, err = sim:build(player, "missile", ex, ey)
	assert(ok, "míssil com lançador falhou: " .. tostring(err))
	local impact = 0
	sim.onMissile = function(x, y, r, id, down)
		if id == player and not down then
			for dy = -r, r do
				for dx = -r, r do
					local t = sim:idx(x + dx, y + dy)
					if t and sim.land[t] and sim.owner[t] == 0 then
						impact += 1
					end
				end
			end
		end
	end
	local steps = 0
	while #sim.flights > 0 and steps < 100 do
		sim:step(cfg.TICK)
		steps += 1
	end
	assert(impact > 0, "o míssil não destruiu nada")
	print(string.format("míssil voou %.1fs e arrasou %d células", steps * cfg.TICK, impact))
	-- antiaéreo do inimigo derruba mísseis (chance forçada a 100% pelo mod)
	local E = sim.nations[anyEnemy]
	local et2 = next(E.front)
	local e2x, e2y = sim:xy(et2)
	local aaTile
	for t in E.tileSet do
		local x, y = sim:xy(t)
		if not sim.buildings[t] and sim:dist(x, y, e2x, e2y) < 8 then
			aaTile = t
			break
		end
	end
	E.gold = 1e6
	local ax, ay = sim:xy(aaTile)
	assert(sim:build(anyEnemy, "aa", ax, ay), "antiaéreo falhou")
	runFor(26)
	E.mods.aa = 1
	local downs = 0
	sim.onMissile = function(_, _, _, id, down)
		if id == player and down then
			downs += 1
		end
	end
	assert(sim:build(player, "missile", e2x, e2y))
	steps = 0
	while #sim.flights > 0 and steps < 100 do
		sim:step(cfg.TICK)
		steps += 1
	end
	assert(downs == 1, "o antiaéreo não derrubou o míssil")
	print("antiaéreo derrubou o míssil")
	sim.onMissile = nil
	-- trens com trilhos retos
	runFor(30)
	print(string.format("trens: %d paradas pagas, %d de ouro, %d células de trilho", trainStops, trainGold, (function()
		local c = 0
		for _ in sim.rails do
			c += 1
		end
		return c
	end)()))
	assert(trainStops >= 2 and trainGold > cfg.TRAIN_STOP_GOLD * trainStops, "trem não pagou de forma progressiva")
	for _, tr in sim.trains do
		for i = 2, #tr.path do
			local x1, y1 = sim:xy(tr.path[i - 1])
			local x2, y2 = sim:xy(tr.path[i])
			local d = math.abs(x1 - x2) + math.abs(y1 - y2)
			assert(d == 1 or d == sim.W - 1, "trilho na diagonal!")
		end
	end
	-- pesquisa
	br.rp = 1000
	local first = br.gov .. "_1_1"
	assert(not sim:research(player, br.gov .. "_1_2"), "não pode pular o nível 1")
	assert(sim:research(player, first), "pesquisa falhou")
	assert(br.mods and next(br.mods), "habilidade não aplicou efeito")
	-- raízes: seguir o ramo 1 bloqueia o ramo oposto (3) e traz um custo
	local okB, errB = sim:research(player, br.gov .. "_3_1")
	assert(not okB and string.find(errB, "bloqueado"), "o ramo oposto deveria ficar bloqueado")
	local neg = false
	for _, v in br.mods do
		if v < 0 then
			neg = true
		end
	end
	assert(neg, "o caminho deveria trazer um efeito negativo")
	print("raízes: ramo oposto bloqueado (" .. errB .. ")")
	-- leis e parlamento
	local law = "industry"
	assert(sim:proposeLaw(player, law))
	for i = 1, #br.parliament do
		br.influence = 999
		sim:lobby(player, i, "persuade")
		sim:lobby(player, i, "persuade")
	end
	local passed, msg = sim:vote(player)
	print("votação:", msg)
	assert(passed and br.laws[law], "lei deveria passar após convencer todos")
	-- mercado: oferta barata é comprada (pela IA ou pelo mercado externo)
	local res = br.prod.food > br.need.food and "food" or "wood"
	br.stock[res] += 5000
	local sold = 0
	sim.onSale = function(seller, _, _, amt)
		if seller == player then
			sold += amt
		end
	end
	assert(sim:postOffer(player, res, 3000, sim.market.ref[res] * 0.7))
	runFor(60)
	print(string.format("mercado: vendeu %d de %s", sold, res))
	assert(sold > 0, "ninguém comprou a oferta barata")
	-- diplomacia: rota de comércio com um vizinho (por terra = trem com trilhos)
	local partner
	for o in sim:neighborsOf(player) do
		if o ~= 0 and sim.nations[o].alive then
			partner = o
			sim.rel[Civ.pairKey(player, o)] = 50
			break
		end
	end
	local okT, msgT = sim:diplomacy(player, partner, "trade")
	print("diplomacia:", msgT)
	assert(okT, "rota de comércio falhou")
	local okA, msgA = sim:diplomacy(player, partner, "alliance")
	assert(okA, msgA)
	local pt = next(sim.nations[partner].front)
	local px, py = sim:xy(pt)
	assert(not sim:attack(player, px, py, 0.1), "aliado não pode ser atacado")
	-- exército com general
	local g = br.generals[1]
	local okE, msgE = sim:createArmy(player, 20000, g.id)
	assert(okE, msgE)
	local army = br.armies[1]
	local target
	for o in sim:neighborsOf(player) do
		if o ~= 0 and o ~= partner and not sim:peaceful(player, o) then
			target = o
			break
		end
	end
	local tt = next(sim.nations[target].front)
	local tx, ty = sim:xy(tt)
	-- célula do alvo que encosta no Brasil
	for t in br.front do
		for _, c in sim.nbr[t] do
			if sim.owner[c] == target then
				tx, ty = sim:xy(c)
			end
		end
	end
	local okS, msgS = sim:sendArmy(player, army.id, tx, ty)
	assert(okS, "exército não atacou: " .. tostring(msgS))
	runFor(20)
	print(string.format("%s com %s (%s): %d células tomadas, general nível %d (xp %d)", army.name, g.name, g.trait, army.tiles, g.level, g.xp))
	assert(army.tiles > 0, "o exército não conquistou nada")
	sim:validate()
end

local boatTested, maxBoats = false, 0
local function tryBoat()
	local myComp = sim.comp[sim.nations[player].home]
	for i = 1, #sim.landList, 13 do
		local t = sim.landList[i]
		local o = sim.owner[t]
		if sim.comp[t] ~= myComp and o ~= player and o ~= 0 then
			local x, y = sim:xy(t)
			local ok, info = sim:attack(player, x, y, 0.3)
			if ok and info == "boat" then
				return true
			end
		end
	end
	return false
end

local t0 = os.clock()
local steps, lastPrint = 0, 0
while sim.phase ~= "end" and sim.time < 2000 do
	sim:step(cfg.TICK)
	steps += 1
	local me = sim.nations[player]
	if not boatTested and not sim:isProtected() and me.alive then
		boatTested = true
		local ok = tryBoat()
		print("barco do Brasil lançado:", ok)
		assert(ok, "nenhuma rota marítima encontrada")
	end
	if me.alive and steps % 20 == 0 and not sim:isProtected() then
		local best, bd = nil, math.huge
		for o in sim:neighborsOf(player) do
			local v = o ~= 0 and sim.nations[o]
			if v and v.alive then
				local d = v.troops / math.max(1, v.tiles)
				if d < bd then
					best, bd = o, d
				end
			end
		end
		if best then
			for t in me.front do
				local done = false
				for _, c in sim.nbr[t] do
					if sim.owner[c] == best then
						local x, y = sim:xy(c)
						sim:attack(player, x, y, 0.35)
						done = true
						break
					end
				end
				if done then
					break
				end
			end
		end
	end
	if #sim.boats > maxBoats then
		maxBoats = #sim.boats
	end
	if steps % 100 == 0 then
		sim:validate()
	end
	if sim.time - lastPrint >= 180 then
		lastPrint = sim.time
		local alive, top, topT = 0, "", 0
		for _, n in sim.nations do
			if n.alive then
				alive += 1
			end
			if n.tiles > topT then
				top, topT = n.name, n.tiles
			end
		end
		print(string.format("t=%4ds vivos=%3d líder=%s %.1f%% ataques=%d | Brasil %.1f%%", sim.time, alive, top, topT / sim.landCount * 100, #sim.attacks, me.tiles / sim.landCount * 100))
	end
end
sim:validate()
local w = sim.winner and sim.nations[sim.winner]
print("fim:", sim.phase, math.floor(sim.time) .. "s", "vencedor", w and w.name, w and string.format("%.1f%%", w.tiles / sim.landCount * 100))
print(string.format("%d passos em %.2fs (%.2f ms/passo)", steps, os.clock() - t0, (os.clock() - t0) / steps * 1000))
print("eventos:", events, "eliminações:", kills, "máx. barcos:", maxBoats)
assert(sim.phase == "end", "rodada não terminou")
print("OK")
