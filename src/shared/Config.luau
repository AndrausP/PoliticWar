-- Todos os números de balanceamento do jogo ficam aqui.
local Config = {}

-- Mapa (o mapa-múndi vem de WorldMap.luau; W/H abaixo só valem para o mapa procedural dos testes)
Config.W = 160
Config.H = 100
Config.LAND_SHARE = 0.52
Config.MIN_ISLAND = 3 -- ilhas menores que isso viram água
Config.PIXELS_PER_TILE = 3 -- resolução da imagem do mapa (fatiada em imagens de até 1024 px)

-- Barcos (rota marítima)
Config.BOAT_SPEED = 18 -- células por segundo
Config.BOAT_RANGE = 360 -- alcance máximo pela água
Config.MAX_BOATS = 3
Config.BOT_NAVAL_RANGE = 90 -- alcance da busca de desembarque dos bots

-- Rodada (segundos)
Config.TICK = 0.1
Config.SELECT_PHASE = 30 -- tempo para escolher a nação antes da partida
Config.PROTECTION = 45 -- preparação: dá para construir, mas ninguém ataca
Config.ROUND_MAX = 30 * 60
Config.END_PHASE = 12
Config.WIN_SHARE = 0.8 -- meta de controle mundial

-- Nações
Config.BOTS = 50
Config.SPAWN_RADIUS = 5
Config.SPAWN_MIN_DIST = 12 -- distância mínima de outra nação ao nascer
Config.START_TROOPS = 2500
Config.START_GOLD = 1500
Config.START_TROOP_SHARE = 0.5 -- países começam com metade do limite de tropas

-- Economia de tropas
Config.MAX_BASE = 3000
Config.MAX_PER_TILE = 90
Config.CITY_MAX_BONUS = 8000
Config.GROWTH_BASE = 15
Config.GROWTH_PER_TILE = 2.2
Config.CITY_GROWTH_BONUS = 40

-- Ouro
Config.GOLD_BASE = 10
Config.GOLD_PER_TILE = 0.6
Config.FACTORY_GOLD = 30 -- renda direta; o grosso vem dos trens
Config.PORT_GOLD = 30

-- Trens (cada fábrica solta um trem que passa pelas cidades e portos)
Config.TRAIN_INTERVAL = 20 -- segundos entre trens de uma fábrica
Config.TRAIN_SPEED = 10 -- células por segundo
Config.TRAIN_STOP_GOLD = 120 -- parada N paga N x isso (progressivo)
Config.PORT_TRAIN_MULT = 1.5 -- portos pagam 1,5x
Config.TRAIN_MAX_STOPS = 8
Config.TRAIN_MAX_LEG = 70 -- distância máxima entre duas paradas (por terra, em linha reta)

-- Mísseis
Config.MISSILE_RANGE = 220 -- células a partir do lançador mais próximo
Config.MISSILE_SPEED = 45 -- células por segundo no ar

-- População, impostos e comércio (sistemas de civilização)
Config.POP_TROOPS = 300 -- limite de tropas por milhão de habitantes
Config.POP_GROWTH_TROOPS = 0.8 -- tropas/s por milhão de habitantes
Config.TAX_PER_POP = 2 -- ouro/s por milhão de habitantes
Config.TRADE_INTERVAL = 30 -- segundos entre comboios de uma rota
Config.TRADE_SPEED = 14 -- células por segundo
Config.TRADE_GOLD = 400 -- base paga a cada comboio (mais a população dos dois)
Config.MAX_AI_ROUTES = 40 -- rotas entre bots no mundo
Config.DETAIL_ZOOM = 16 -- a partir desse zoom o mapa vira a visão detalhada
Config.MAX_ZOOM = 40

-- Combate
Config.ATTACK_PCTS = { 0.10, 0.25, 0.35, 0.50, 0.75 }
Config.DEFAULT_PCT_INDEX = 2
Config.NEUTRAL_COST = 10 -- tropas gastas por célula neutra
Config.ENEMY_BASE_COST = 14
Config.DEFENSE_MULT = 2.5 -- multiplicador de custo perto de uma fortaleza
Config.DEFENSE_RADIUS = 7
Config.NEUTRAL_SPEED = 1.2 -- frentes avançam N células por segundo (proporcional à frente)
Config.ENEMY_SPEED = 0.4
Config.MIN_SPEED = 3 -- células/s mínimas em frentes pequenas

-- Construções (ordem = teclas 1..4)
Config.BUILD_ORDER = { "city", "factory", "port", "defense", "aa", "silo", "missile" }
Config.BUILDINGS = {
	city = { name = "Cidade", icon = "🏙️", cost = 6000, time = 20, growth = 1.6, desc = "+8K de limite de tropas e mais crescimento" },
	factory = { name = "Fábrica", icon = "🏭", cost = 4000, time = 25, growth = 1.5, desc = "Solta trens que passam nas cidades e portos e rendem ouro (cada parada paga mais)" },
	port = { name = "Porto", icon = "⚓", cost = 5000, time = 20, growth = 1.4, desc = "Na costa: parada de trem que paga 1,5x e +30 de ouro/s" },
	aa = { name = "Antiaéreo", icon = "AA", cost = 7000, time = 25, growth = 1.4, desc = "Chance de derrubar mísseis num raio de 14 células" },
	silo = { name = "Lançador", icon = "🚀", cost = 12000, time = 40, growth = 1.5, desc = "Necessário para lançar mísseis (alcance de 220 células)" },
	defense = { name = "Fortaleza", icon = "🏰", cost = 3000, time = 15, growth = 1.3, desc = "Inimigos pagam 2,5x tropas num raio de 7" },
	missile = { name = "Míssil", icon = "🚀", cost = 20000, growth = 1.0, radius = 5, desc = "Sai do lançador mais próximo e devasta uma área (raio 5)" },
}

-- 60 cores distintas (proporção áurea no matiz)
Config.PALETTE = {}
for i = 0, 59 do
	local h = (i * 0.618034) % 1
	local sat = 0.5 + (i % 3) * 0.12
	local v = 0.95 - (i % 4) * 0.08
	local k = function(n)
		local kk = (n + h * 6) % 6
		return v - v * sat * math.max(0, math.min(kk, 4 - kk, 1))
	end
	Config.PALETTE[i + 1] = { math.floor(k(5) * 255), math.floor(k(3) * 255), math.floor(k(1) * 255) }
end

local ANIMALS = { "Lontra", "Corvo", "Lobo", "Tigre", "Falcão", "Urso", "Raposa", "Cegonha", "Serpente", "Leão", "Javali", "Coruja", "Tubarão", "Pantera", "Garça", "Touro" }
local ELEMENTS = { "das Dunas", "de Gelo", "de Brasa", "das Marés", "de Ferro", "da Tempestade", "do Norte", "de Cinzas", "das Neves", "de Jade", "do Deserto", "de Prata", "do Pântano", "de Obsidiana", "das Ilhas", "do Sol" }
Config.botName = function(rand: (number) -> number): string
	return ANIMALS[rand(#ANIMALS)] .. " " .. ELEMENTS[rand(#ELEMENTS)]
end

return Config
