# Domínio Mundial (PoliticWar)

Jogo de estratégia de conquista mundial para Roblox, feito com **Rojo + Luau**.

- Mapa-múndi real (Natural Earth) com 179 países, população e PIB reais
- Guerra por frentes com exércitos e generais, barcos, trens com trilhos, mísseis e antiaéreo
- Economia com 5 recursos e mercado mundial, leis votadas pelo parlamento, diplomacia e rotas de comércio
- Três árvores de pesquisa em forma de raízes (Capitalismo, Comunismo, Fascismo)
- Proposta de próximas melhorias: [docs/Melhorias_Propostas.pdf](docs/Melhorias_Propostas.pdf)

## Rodar

```sh
rojo build default.project.json -o DominioMundial.rbxlx   # gera o place
rojo serve default.project.json                          # sincroniza com o Studio (plugin Rojo)
```

No jogo publicado, libere as APIs de Mesh/Image (EditableImage) nas configurações de segurança.

## Estrutura

| Pasta | Conteúdo |
|---|---|
| `src/shared` | `Sim` (simulação pura), `Civ` (civilização), `CivData` (conteúdo), `Config`, `WorldMap` (gerado) |
| `src/server` | `GameServer`: rodadas, rede e ações |
| `src/client` | mapa (`MapView`, `DetailView`), HUD, janelas (`Panels`), menu de nações, ícones e personagens |
| `src/first` | tela de carregamento |
| `tools` | testes headless, gerador do mapa e do PDF |

## Testes (fora do Studio)

```sh
sh tools/run_tests.sh          # simulação completa com países, mercado, leis, diplomacia, exércitos
sh tools/run_render_test.sh    # desenho do mapa e da visão detalhada (pixel a pixel)
python tools/make_worldmap.py  # regenera src/shared/WorldMap.luau
python tools/make_pdf.py       # regenera docs/Melhorias_Propostas.pdf
```
