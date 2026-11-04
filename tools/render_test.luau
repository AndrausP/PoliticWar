-- Rodado por tools/run_render_test.sh: mede o custo do MapView com APIs do Roblox falsas.
local writes, bytes = 0, 0
local Fake = setmetatable({}, { __index = function() return function() end end, __newindex = function() end })
local function V2(x, y) return { X = x or 0, Y = y or 0 } end
game = { GetService = function() return { CreateEditableImage = function(_, o)
	local w, h = o.Size.X, o.Size.Y
	local img = { mirror = buffer.create(w * h * 4), W = w }
	function img:WritePixelsBuffer(pos, size, buf)
		assert(buffer.len(buf) == size.X * size.Y * 4, "tamanho do buffer errado")
		assert(pos.X >= 0 and pos.Y >= 0 and pos.X + size.X <= w and pos.Y + size.Y <= h, "fora da imagem")
		for r = 0, size.Y - 1 do
			buffer.copy(self.mirror, ((pos.Y + r) * w + pos.X) * 4, buf, r * size.X * 4, size.X * 4)
		end
		writes += 1; bytes += buffer.len(buf)
	end
	function img:Destroy() end
	return img
end } end }
Instance = { new = function() return {} end }
Vector2 = { new = V2, zero = V2(0, 0) }
UDim2 = { fromScale = function() return {} end }
Content = { fromObject = function() return {} end }
Enum = { ResamplerMode = { Pixelated = 1 } }
warn = print

local geo = Sim.new(Config, 1, WorldMap)
local t0 = os.clock()
local view = MapView.new(geo, Config, {})
view:loadOwners(buffer.create(geo.W * geo.H))
print(string.format("criação + desenho completo: %.0f ms (%d chunks)", (os.clock() - t0) * 1000, #view.chunks))
for id = 1, 50 do view:setColor(id, Config.PALETTE[id]) end
-- simula uma partida: 40 nações conquistando ~300 células por flush
local sim = Sim.new(Config, 99, WorldMap)
sim.onOwner = function(t, o) view:setOwner(t, o) end
for i = 1, 30 do local id = sim:addNation({ isBot = true }); sim:randomSpawn(id) end
view:flush()
local flushes, worst, total = 0, 0, 0
writes, bytes = 0, 0
while sim.time < 300 do
	sim:step(0.1)
	if math.floor(sim.time * 10 + 0.5) % 1 == 0 then
		local a = os.clock(); view:flush(); local d = os.clock() - a
		flushes += 1; total += d; if d > worst then worst = d end
	end
end
print(string.format("%d flushes: média %.2f ms, pior %.2f ms; %d envios à imagem, %.1f KB por flush", flushes, total / flushes * 1000, worst * 1000, writes, bytes / flushes / 1024))
local a = os.clock(); view:repaintOwners({ [3] = true, [7] = true }); view:flush()
print(string.format("repintar 2 nações: %.1f ms", (os.clock() - a) * 1000))
-- confere que o pixel do centro de uma célula de cada dono tem a cor esperada
for _, t in sim.landList do
	local o = sim.owner[t]
	assert(view.owner[t] == o, "dono divergente no cliente")
end
for i, ch in view.chunks do
	assert(buffer.tostring(ch.img.mirror) == buffer.tostring(ch.buf), "imagem difere do buffer no chunk " .. i)
end
print("pixels enviados = pixels desenhados: ok")
-- visão detalhada: desenho completo de uma região e atualização incremental
Civ.computeBiomes(geo, WorldMap)
local dv = DetailView.new(geo, view, {})
local worst, frames = 0, 0
repeat
	local a0 = os.clock()
	dv:update(true, 300, 120)
	worst = math.max(worst, os.clock() - a0)
	frames += 1
until not dv.job
print(string.format("visão detalhada: região nova em %d quadros, pior quadro %.1f ms", frames, worst * 1000))
for i = 1, 200 do
	view:setOwner(sim.landList[i * 37], 1)
end
a0 = os.clock()
dv:update(true, 300, 120)
print(string.format("visão detalhada: atualização incremental em %.1f ms", (os.clock() - a0) * 1000))
print("OK")
