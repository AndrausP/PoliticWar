--!nocheck
-- Dados de conteúdo: árvores de habilidades, leis, partidos, governos, generais e recursos.
-- Efeitos ("fx") são somados em n.mods. Chaves:
--  atk, def, speed (ataque), troopGrowth, maxTroops, gold, research, popGrowth, happy (pontos),
--  trainGold, tradeGold, boatSpeed, boatRange, missileRadius (células), missileRange, aa (interceptação),
--  buildCost (desconto), prod (tudo), prod_food/wood/steel/oil/goods, persuade, bribe, influence, marketSell, generalXp
local D = {}

---------------------------------------------------------------- recursos
D.RESOURCES = { "food", "wood", "steel", "oil", "goods" }
D.RES = {
	food = { name = "Comida", color = Color3 and Color3.fromRGB(150, 200, 90) or nil, base = 1.0, need = 0.05 },
	wood = { name = "Madeira", color = Color3 and Color3.fromRGB(170, 120, 70) or nil, base = 1.5, need = 0.01 },
	steel = { name = "Aço", color = Color3 and Color3.fromRGB(150, 160, 175) or nil, base = 4, need = 0.006 },
	oil = { name = "Petróleo", color = Color3 and Color3.fromRGB(60, 60, 70) or nil, base = 5, need = 0.008 },
	goods = { name = "Bens", color = Color3 and Color3.fromRGB(230, 170, 70) or nil, base = 6, need = 0.02 },
}
-- produção por célula por segundo, por bioma
D.BIOMES = {
	{ key = "plains", name = "Planície", yield = { food = 0.08 } },
	{ key = "forest", name = "Floresta", yield = { wood = 0.08, food = 0.02 } },
	{ key = "jungle", name = "Selva", yield = { wood = 0.06, food = 0.04 } },
	{ key = "desert", name = "Deserto", yield = { oil = 0.05 } },
	{ key = "mountain", name = "Montanha", yield = { steel = 0.06, oil = 0.01 } },
	{ key = "tundra", name = "Tundra", yield = { wood = 0.02, oil = 0.03, steel = 0.02 } },
}

---------------------------------------------------------------- governos
D.GOVS = {
	cap = { name = "Capitalismo", color = { 90, 150, 240 }, threshold = 0.5, persuade = 1.0, bribe = 1.0, scandal = 0.15, desc = "Parlamento com vários partidos. Propina funciona, mas pode virar escândalo." },
	com = { name = "Comunismo", color = { 220, 70, 70 }, threshold = 0.5, persuade = 1.5, bribe = 0.5, scandal = 0.25, desc = "Partido único com facções. Convencer funciona bem; propina é arriscada." },
	fas = { name = "Fascismo", color = { 120, 110, 90 }, threshold = 0.34, persuade = 0.8, bribe = 1.3, scandal = 0.10, desc = "O líder manda: basta 1/3 da câmara. Propina compra facções com facilidade." },
}
D.GOV_ORDER = { "cap", "com", "fas" }
-- países que começam comunistas (nomes como no mapa)
D.START_COM = { ["China"] = true, ["Vietnã"] = true, ["Laos"] = true, ["Cuba"] = true, ["Coreia do Norte"] = true }

D.AMBITIONS = {
	dinheiro = { name = "Dinheiro", bribe = 1.6, persuade = 0.7 },
	poder = { name = "Poder", bribe = 0.9, persuade = 1.5 },
	ideologia = { name = "Ideologia", bribe = 0.4, persuade = 1.0 },
}
D.PARTIES = {
	cap = {
		{ name = "Partido Liberal", ideo = { cap = 1 }, amb = "dinheiro" },
		{ name = "Social-Democracia", ideo = { cap = 0.4, com = 0.6 }, amb = "ideologia" },
		{ name = "Conservadores", ideo = { cap = 0.6, fas = 0.4 }, amb = "poder" },
		{ name = "Partido Verde", ideo = { cap = 0.5, com = 0.3 }, amb = "ideologia" },
	},
	com = {
		{ name = "Linha-Dura", ideo = { com = 1 }, amb = "ideologia" },
		{ name = "Reformistas", ideo = { com = 0.6, cap = 0.4 }, amb = "poder" },
		{ name = "Ala Militar", ideo = { com = 0.5, fas = 0.5 }, amb = "poder" },
		{ name = "Tecnocratas", ideo = { com = 0.7, cap = 0.3 }, amb = "dinheiro" },
	},
	fas = {
		{ name = "Junta Militar", ideo = { fas = 1 }, amb = "poder" },
		{ name = "Industriais", ideo = { fas = 0.5, cap = 0.5 }, amb = "dinheiro" },
		{ name = "Clero", ideo = { fas = 0.6, cap = 0.4 }, amb = "ideologia" },
		{ name = "Nacionalistas Radicais", ideo = { fas = 1 }, amb = "ideologia" },
	},
}

---------------------------------------------------------------- leis
-- sup: apoio de cada ideologia (-1 a 1); govs: regimes onde a lei existe (nil = todos)
D.LAWS = {
	{ id = "tax_high", name = "Impostos Altos", desc = "+50% de ouro dos impostos, -10 de felicidade", cost = 3000, sup = { cap = -0.6, com = 0.7, fas = 0.3 }, fx = { taxMult = 0.5, happy = -10 } },
	{ id = "tax_low", name = "Isenção Fiscal", desc = "-40% de impostos, +8 de felicidade", cost = 2000, sup = { cap = 0.8, com = -0.6, fas = 0.1 }, fx = { taxMult = -0.4, happy = 8 } },
	{ id = "conscription", name = "Alistamento Obrigatório", desc = "+30% de crescimento de tropas, -8 de felicidade", cost = 4000, sup = { cap = -0.4, com = 0.4, fas = 0.9 }, fx = { troopGrowth = 0.3, happy = -8 } },
	{ id = "free_market", name = "Livre Mercado", desc = "Vende sobras e compra faltas no mercado externo sozinho; +10% de ouro", cost = 5000, govs = { cap = true, fas = true }, sup = { cap = 1, com = -1, fas = 0.1 }, fx = { gold = 0.1 }, flag = "freeMarket" },
	{ id = "planned", name = "Economia Planejada", desc = "+15% em toda a produção, -10% no preço de venda", cost = 5000, govs = { com = true, fas = true }, sup = { cap = -1, com = 1, fas = 0.3 }, fx = { prod = 0.15, marketSell = -0.1 } },
	{ id = "welfare", name = "Estado de Bem-Estar", desc = "+12 de felicidade, -15% de ouro", cost = 6000, sup = { cap = 0.1, com = 0.8, fas = -0.5 }, fx = { happy = 12, gold = -0.15 } },
	{ id = "censorship", name = "Censura", desc = "+5 de felicidade aparente, -10% de pesquisa", cost = 2500, sup = { cap = -0.8, com = 0.5, fas = 0.8 }, fx = { happy = 5, research = -0.1 } },
	{ id = "propaganda", name = "Propaganda Estatal", desc = "+6 de felicidade, +20% de influência, -5% de ouro", cost = 3000, sup = { cap = -0.3, com = 0.7, fas = 0.8 }, fx = { happy = 6, influence = 0.2, gold = -0.05 } },
	{ id = "martial", name = "Lei Marcial", desc = "Impede revoluções e +20% de defesa, mas -15 de felicidade", cost = 8000, sup = { cap = -0.8, com = 0.2, fas = 0.9 }, fx = { def = 0.2, happy = -15 }, flag = "martial" },
	{ id = "agrarian", name = "Reforma Agrária", desc = "+25% de comida", cost = 4000, sup = { cap = -0.4, com = 0.9, fas = -0.2 }, fx = { prod_food = 0.25 } },
	{ id = "industry", name = "Incentivo Industrial", desc = "+30% de bens, +15% de aço, -10% no custo das construções", cost = 6000, sup = { cap = 0.6, com = 0.5, fas = 0.6 }, fx = { prod_goods = 0.3, prod_steel = 0.15, buildCost = 0.1 } },
	{ id = "science", name = "Pesquisa Pública", desc = "+30% de pesquisa, -10% de ouro", cost = 5000, sup = { cap = 0.3, com = 0.7, fas = 0.1 }, fx = { research = 0.3, gold = -0.1 } },
	{ id = "open_trade", name = "Abertura Comercial", desc = "+25% de ouro das rotas de comércio e +10% no preço de venda", cost = 4000, sup = { cap = 0.9, com = -0.5, fas = -0.6 }, fx = { tradeGold = 0.25, marketSell = 0.1 } },
	{ id = "pro_army", name = "Exército Profissional", desc = "+10% de ataque, -10% de limite de tropas", cost = 5000, sup = { cap = 0.6, com = -0.2, fas = 0.5 }, fx = { atk = 0.1, maxTroops = -0.1 } },
	{ id = "natality", name = "Incentivo à Natalidade", desc = "+50% de crescimento da população, +10% de consumo de comida", cost = 3000, sup = { cap = 0.1, com = 0.4, fas = 0.7 }, fx = { popGrowth = 0.5, need_food = 0.1 } },
	{ id = "air_defense", name = "Defesa Aérea Nacional", desc = "+15% de chance de interceptar mísseis", cost = 6000, sup = { cap = 0.4, com = 0.6, fas = 0.7 }, fx = { aa = 0.15 } },
}
D.LAW_BY_ID = {}
for _, l in D.LAWS do
	D.LAW_BY_ID[l.id] = l
end

---------------------------------------------------------------- habilidades
-- cada árvore: 5 ramos x 5 níveis. Nível N exige o N-1 do mesmo ramo; o nível 4 também exige o nível 2 do ramo vizinho.
local COSTS = { 40, 80, 140, 220, 320 }
local TREES = {
	{
		key = "cap",
		name = "Capitalismo",
		branches = {
			{ "Mercado", {
				{ "Bolsa de Valores", { gold = 0.1 } },
				{ "Bancos Centrais", { gold = 0.1 } },
				{ "Comércio Global", { tradeGold = 0.25 } },
				{ "Marketing", { marketSell = 0.15 } },
				{ "Multinacionais", { gold = 0.15, tradeGold = 0.25 } },
			} },
			{ "Indústria", {
				{ "Linha de Montagem", { prod_goods = 0.2 } },
				{ "Siderurgia Moderna", { prod_steel = 0.25 } },
				{ "Refinarias", { prod_oil = 0.25 } },
				{ "Automação", { prod_goods = 0.3, buildCost = 0.1 } },
				{ "Alta Tecnologia", { research = 0.25 } },
			} },
			{ "Exército Profissional", {
				{ "Capacete de Kevlar", { def = 0.08 } },
				{ "Fuzis de Assalto", { atk = 0.08 } },
				{ "Blindados", { atk = 0.1, speed = 0.1 } },
				{ "Logística Privada", { troopGrowth = 0.15 } },
				{ "Forças Especiais", { atk = 0.12 } },
			} },
			{ "Marinha e Ar", {
				{ "Estaleiros", { boatSpeed = 0.2 } },
				{ "Navios de Guerra", { boatRange = 0.2, atk = 0.05 } },
				{ "Aviação Civil", { tradeGold = 0.15 } },
				{ "Caças a Jato", { atk = 0.08, aa = 0.1 } },
				{ "Porta-Aviões", { boatSpeed = 0.3, boatRange = 0.3 } },
			} },
			{ "Sociedade", {
				{ "Lobby", { bribe = 0.3 } },
				{ "Mídia Livre", { happy = 5 } },
				{ "Consumo de Massa", { happy = 6, prod_goods = 0.1 } },
				{ "Imigração", { popGrowth = 0.3 } },
				{ "Prosperidade", { happy = 8, gold = 0.1 } },
			} },
		},
	},
	{
		key = "com",
		name = "Comunismo",
		branches = {
			{ "Planejamento", {
				{ "Plano Quinquenal", { prod = 0.1 } },
				{ "Coletivização", { prod_food = 0.25 } },
				{ "Indústria Pesada", { prod_steel = 0.3 } },
				{ "Eletrificação", { prod_goods = 0.2, research = 0.1 } },
				{ "Programa Espacial", { research = 0.3, missileRange = 0.25 } },
			} },
			{ "Exército Vermelho", {
				{ "Capacete de Aço", { def = 0.08 } },
				{ "Ondas Humanas", { troopGrowth = 0.25 } },
				{ "Artilharia em Massa", { atk = 0.1 } },
				{ "Tanques Pesados", { atk = 0.12, def = 0.05 } },
				{ "Exército Gigante", { maxTroops = 0.2 } },
			} },
			{ "Partido", {
				{ "Comissários Políticos", { persuade = 0.3 } },
				{ "Propaganda", { happy = 6 } },
				{ "Polícia Secreta", { happy = 4, influence = 0.3 } },
				{ "Culto à Personalidade", { persuade = 0.3, happy = 5 } },
				{ "Partido Único", { influence = 0.5 } },
			} },
			{ "Defesa Aérea", {
				{ "Radares", { aa = 0.15 } },
				{ "Baterias Antiaéreas", { aa = 0.2 } },
				{ "Mísseis Balísticos", { missileRadius = 1 } },
				{ "Caças Interceptadores", { atk = 0.06, aa = 0.1 } },
				{ "Arsenal Nuclear", { missileRadius = 2, missileRange = 0.3 } },
			} },
			{ "Povo", {
				{ "Educação Universal", { research = 0.15 } },
				{ "Saúde Pública", { popGrowth = 0.3 } },
				{ "Habitação Coletiva", { happy = 5 } },
				{ "Ferrovias Estatais", { trainGold = 0.3 } },
				{ "Internacionalismo", { tradeGold = 0.2, influence = 0.2 } },
			} },
		},
	},
	{
		key = "fas",
		name = "Fascismo",
		branches = {
			{ "Militarismo", {
				{ "Capacete de Combate", { def = 0.1 } },
				{ "Infantaria de Elite", { atk = 0.1 } },
				{ "Blitzkrieg", { speed = 0.25 } },
				{ "Divisões Blindadas", { atk = 0.12, speed = 0.1 } },
				{ "Guerra Total", { atk = 0.15, troopGrowth = 0.15 } },
			} },
			{ "Aviação", {
				{ "Aviação Militar", { atk = 0.05 } },
				{ "Bombardeiros", { atk = 0.08 } },
				{ "Caças de Defesa", { aa = 0.15 } },
				{ "Paraquedistas", { speed = 0.15 } },
				{ "Supremacia Aérea", { atk = 0.1, aa = 0.2 } },
			} },
			{ "Marinha", {
				{ "Submarinos", { boatSpeed = 0.2 } },
				{ "Encouraçados", { atk = 0.06, boatRange = 0.2 } },
				{ "Desembarque Anfíbio", { boatSpeed = 0.2 } },
				{ "Bloqueio Naval", { tradeGold = 0.15 } },
				{ "Frota Imperial", { boatRange = 0.4 } },
			} },
			{ "Autarquia", {
				{ "Autossuficiência", { prod_food = 0.2 } },
				{ "Indústria de Guerra", { prod_steel = 0.25, buildCost = 0.1 } },
				{ "Petróleo Sintético", { prod_oil = 0.3 } },
				{ "Trabalho Forçado", { prod_goods = 0.25, happy = -4 } },
				{ "Economia de Guerra", { gold = 0.15, maxTroops = 0.1 } },
			} },
			{ "Estado", {
				{ "Propaganda Nacional", { happy = 6 } },
				{ "Juventude Nacional", { troopGrowth = 0.15 } },
				{ "Polícia do Estado", { influence = 0.3 } },
				{ "Corporativismo", { bribe = 0.4 } },
				{ "Nacionalismo", { happy = 6, def = 0.08 } },
			} },
		},
	},
}

local FX_NAMES = {
	atk = "ataque", def = "defesa", speed = "velocidade de avanço", troopGrowth = "crescimento de tropas", maxTroops = "limite de tropas",
	gold = "ouro", research = "pesquisa", popGrowth = "crescimento da população", trainGold = "ouro dos trens", tradeGold = "ouro do comércio",
	boatSpeed = "velocidade dos barcos", boatRange = "alcance dos barcos", missileRange = "alcance dos mísseis", aa = "interceptação antiaérea",
	buildCost = "desconto nas construções", prod = "produção", prod_food = "comida", prod_wood = "madeira", prod_steel = "aço", prod_oil = "petróleo",
	prod_goods = "bens", persuade = "persuasão", bribe = "propina", influence = "influência", marketSell = "preço de venda",
}
function D.describeFx(fx)
	local parts = {}
	for k, v in fx do
		if k == "happy" then
			parts[#parts + 1] = string.format("%+d de felicidade", v)
		elseif k == "missileRadius" then
			parts[#parts + 1] = string.format("+%d de raio do míssil", v)
		elseif FX_NAMES[k] then
			parts[#parts + 1] = string.format("%+d%% de %s", math.floor(v * 100 + 0.5), FX_NAMES[k])
		end
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

-- custo de cada raiz: todo nó do ramo traz este efeito negativo (cresce com o nível)
local DOWNSIDE = {
	cap = { { def = -0.02 }, { happy = -1 }, { gold = -0.03 }, { troopGrowth = -0.03 }, { atk = -0.02 } },
	com = { { gold = -0.03 }, { happy = -1 }, { research = -0.03 }, { prod_goods = -0.04 }, { def = -0.02 } },
	fas = { { happy = -1 }, { gold = -0.03 }, { tradeGold = -0.05 }, { research = -0.03 }, { marketSell = -0.03 } },
}
D.TRUNK = { cap = "Doutrina Liberal", com = "Doutrina Marxista", fas = "Doutrina Nacionalista" }

-- raiz oposta: seguir um ramo bloqueia o ramo que fica "do outro lado" (dois ramos para a frente)
function D.opposite(bi)
	return (bi + 1) % 5 + 1
end

D.TREES = {}
D.SKILLS = {}
for _, tree in TREES do
	local t = { key = tree.key, name = tree.name, branches = {} }
	for bi, br in tree.branches do
		local ids = {}
		for lvl, node in br[2] do
			local id = tree.key .. "_" .. bi .. "_" .. lvl
			local req = {}
			if lvl > 1 then
				req[#req + 1] = tree.key .. "_" .. bi .. "_" .. (lvl - 1)
			end
			if lvl == 4 then
				req[#req + 1] = tree.key .. "_" .. (bi % 5 + 1) .. "_2" -- ramo vizinho
			end
			local bad = {}
			for k, v in DOWNSIDE[tree.key][bi] do
				bad[k] = v * lvl
			end
			local sk = { id = id, tree = tree.key, branch = bi, level = lvl, name = node[1], fx = node[2], bad = bad, cost = COSTS[lvl], req = req }
			sk.desc = D.describeFx(sk.fx)
			sk.badDesc = D.describeFx(bad)
			D.SKILLS[id] = sk
			ids[#ids + 1] = id
		end
		t.branches[bi] = { name = br[1], skills = ids }
	end
	D.TREES[#D.TREES + 1] = t
end

---------------------------------------------------------------- generais
D.GENERAL_NAMES = {
	"Almeida", "Barbosa", "Costa", "Duarte", "Esteves", "Falcão", "Garrido", "Holanda", "Ibáñez", "Jansen", "Kovac", "Lacerda",
	"Moreau", "Novak", "Oliveira", "Petrov", "Quintana", "Rocha", "Sato", "Torres", "Ulrich", "Valença", "Wagner", "Yamada", "Zanetti",
}
D.TRAITS = {
	{ key = "ofensivo", name = "Ofensivo", desc = "+15% de ataque", fx = { atk = 0.15 } },
	{ key = "relampago", name = "Relâmpago", desc = "+35% de velocidade de avanço", fx = { speed = 0.35 } },
	{ key = "cauteloso", name = "Cauteloso", desc = "-20% de perdas (custo por célula)", fx = { atk = 0.2, speed = -0.1 } },
	{ key = "naval", name = "Almirante", desc = "+50% de velocidade dos barcos do exército", fx = { boatSpeed = 0.5 } },
	{ key = "veterano", name = "Veterano", desc = "+10% de ataque e ganha experiência 50% mais rápido", fx = { atk = 0.1, generalXp = 0.5 } },
	{ key = "implacavel", name = "Implacável", desc = "+8% de ataque e +15% de velocidade", fx = { atk = 0.08, speed = 0.15 } },
}
D.GENERAL_LEVEL_XP = 60 -- células conquistadas por nível (cresce a cada nível)
D.GENERAL_LEVEL_ATK = 0.03 -- +3% de ataque por nível
D.GENERAL_COST = 2500 -- ouro para recrutar um general novo

---------------------------------------------------------------- construções extras
D.AA_RADIUS = 14 -- células protegidas por um antiaéreo
D.AA_CHANCE = 0.55 -- chance base de interceptar (soma com mods.aa, máx. 92%)

return D
