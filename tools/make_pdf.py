"""Gera docs/Melhorias_Propostas.pdf (proposta de melhorias do Domínio Mundial).
Uso: python tools/make_pdf.py"""
import os
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import PageBreak, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

here = os.path.dirname(os.path.abspath(__file__))
out_dir = os.path.join(here, '..', 'docs')
os.makedirs(out_dir, exist_ok=True)
out = os.path.join(out_dir, 'Melhorias_Propostas.pdf')

NAVY = colors.HexColor('#1A2033')
GOLD = colors.HexColor('#C99A1E')
MUTED = colors.HexColor('#5B6378')
LIGHT = colors.HexColor('#F3F1EA')

ss = getSampleStyleSheet()
H1 = ParagraphStyle('H1', parent=ss['Heading1'], fontName='Helvetica-Bold', fontSize=17, textColor=NAVY, spaceBefore=14, spaceAfter=6)
H2 = ParagraphStyle('H2', parent=ss['Heading2'], fontName='Helvetica-Bold', fontSize=12.5, textColor=NAVY, spaceBefore=10, spaceAfter=4)
BODY = ParagraphStyle('B', parent=ss['BodyText'], fontName='Helvetica', fontSize=10, leading=14.5, textColor=colors.HexColor('#222631'))
SMALL = ParagraphStyle('S', parent=BODY, fontSize=8.8, leading=12, textColor=MUTED)
BUL = ParagraphStyle('BL', parent=BODY, leftIndent=12, bulletIndent=2)
CELL = ParagraphStyle('C', parent=BODY, fontSize=8.8, leading=11.5)
CELLB = ParagraphStyle('CB', parent=CELL, fontName='Helvetica-Bold', textColor=colors.white)


def p(t, st=BODY):
    return Paragraph(t, st)


def bullets(items):
    return [Paragraph(i, BUL, bulletText='•') for i in items]


def table(rows, widths, head=True):
    data = [[Paragraph(str(c), CELLB if (head and r == 0) else CELL) for c in row] for r, row in enumerate(rows)]
    t = Table(data, colWidths=widths, repeatRows=1 if head else 0)
    style = [
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('GRID', (0, 0), (-1, -1), 0.4, colors.HexColor('#CFCBBE')),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, LIGHT]),
        ('LEFTPADDING', (0, 0), (-1, -1), 5),
        ('RIGHTPADDING', (0, 0), (-1, -1), 5),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
    ]
    if head:
        style += [('BACKGROUND', (0, 0), (-1, 0), NAVY), ('TEXTCOLOR', (0, 0), (-1, 0), colors.white)]
    t.setStyle(TableStyle(style))
    return t


def on_page(c, doc):
    c.saveState()
    c.setFillColor(NAVY)
    c.rect(0, A4[1] - 0.9 * cm, A4[0], 0.9 * cm, fill=1, stroke=0)
    c.setFillColor(GOLD)
    c.rect(0, A4[1] - 0.98 * cm, A4[0], 0.08 * cm, fill=1, stroke=0)
    c.setFillColor(colors.white)
    c.setFont('Helvetica-Bold', 9)
    c.drawString(1.8 * cm, A4[1] - 0.6 * cm, 'DOMÍNIO MUNDIAL  ·  Proposta de melhorias')
    c.setFillColor(MUTED)
    c.setFont('Helvetica', 8)
    c.drawRightString(A4[0] - 1.8 * cm, 1.1 * cm, 'Página %d' % doc.page)
    c.restoreState()


story = []
story.append(Spacer(1, 1.2 * cm))
story.append(p('<font size=26 color="#1A2033"><b>Domínio Mundial</b></font>', BODY))
story.append(Spacer(1, 10))
story.append(p('<font size=14 color="#C99A1E"><b>Proposta de melhorias para o jogo</b></font>', BODY))
story.append(Spacer(1, 6))
story.append(p('Jogo de estratégia de conquista mundial para Roblox (Rojo + Luau)  ·  novembro de 2026', SMALL))
story.append(Spacer(1, 18))

story.append(p('Resumo', H1))
story.append(p(
    'O Domínio Mundial já tem um núcleo sólido: mapa-múndi real com 179 países, simulação de guerra por frentes, '
    'barcos e trens, mísseis e antiaéreo, população real, mercado, leis com parlamento, diplomacia, exércitos com '
    'generais e árvores de pesquisa em formato de raízes. Este documento propõe as próximas melhorias, organizadas '
    'por área, com prioridade e esforço estimado, para transformar o protótipo num jogo pronto para publicar e reter jogadores.'))
story.append(Spacer(1, 8))
story.append(table([
    ['Área', 'Situação atual', 'Maior oportunidade'],
    ['Validação', 'Lógica testada fora do Studio (testes headless)', 'Testar no Studio com 2 a 8 jogadores e ajustar a interface'],
    ['Retenção', 'Rodadas de 30 min, sem progresso entre partidas', 'Perfil persistente, conquistas, temporadas e ranking global'],
    ['Social', 'Diplomacia e propostas entre jogadores', 'Chat diplomático, alianças com objetivo comum, eventos em grupo'],
    ['Profundidade', 'Economia, leis, pesquisa e exércitos', 'Eventos históricos, tecnologia por era, crises e espionagem'],
    ['Apresentação', 'Mapa em pixel, ícones e personagens desenhados', 'Sons, música, tutorial guiado e efeitos de batalha'],
], [3.2 * cm, 6.4 * cm, 7.4 * cm]))

story.append(p('1. Prioridade imediata: estabilidade e validação', H1))
story.append(p('Antes de crescer, o jogo precisa ser jogado de verdade. Hoje toda a lógica passa nos testes automáticos, '
               'mas as janelas novas (Exércitos, Diplomacia, Pesquisa, Mercado, Política) ainda não foram vistas rodando.'))
story += bullets([
    '<b>Sessão de teste no Studio</b> com o modo "Iniciar servidor" e 2 a 4 jogadores locais: conferir carregamento, '
    'janelas, botão direito, envio de exércitos e rotas de trem.',
    '<b>Painel de depuração</b> (só para o dono): acelerar o tempo, dar ouro e pesquisa, forçar revolução e escolher regime, '
    'para testar sistemas em minutos.',
    '<b>Registro de erros</b>: um ScriptContext.Error no servidor e no cliente mandando os erros para um aviso na tela do dono, '
    'evitando casos como o "carregando infinito".',
    '<b>Limites de rede</b>: comprimir o pacote de Civilização (hoje 1 vez por segundo) e mandar só o que mudou.',
])

story.append(p('2. Jogabilidade e equilíbrio', H1))
story.append(p('2.1 Guerra', H2))
story += bullets([
    '<b>Ordens de exército</b>: além de "atacar", ordens de "defender região", "segurar fronteira" e "recuar", com o general '
    'reagindo sozinho a invasões.',
    '<b>Frentes visíveis</b>: setas animadas mostrando para onde cada exército avança e quantas tropas restam.',
    '<b>Terreno na batalha</b>: montanhas e selvas mais caras de conquistar; desertos gastam suprimento.',
    '<b>Suprimento</b>: exércitos longe de cidades ou ferrovias perdem força com o tempo (dá valor real aos trilhos).',
    '<b>Força aérea e marinha</b> como unidades (bombardeiros, caças, frotas) usando as habilidades de aviação e navios.',
])
story.append(p('2.2 Economia e mercado', H2))
story += bullets([
    '<b>Gráfico de preços</b> por recurso no Mercado (últimos 5 minutos) e notícia quando um preço dispara.',
    '<b>Contratos</b> de fornecimento entre países (X de petróleo por minuto durante 5 minutos, com multa se quebrar).',
    '<b>Embargo</b> como ação diplomática, bloqueando ofertas de um país no mercado.',
    '<b>Recursos estratégicos</b>: mísseis gastam aço e petróleo; tanques e aviões exigem petróleo.',
])
story.append(p('2.3 Política e população', H2))
story += bullets([
    '<b>Eleições</b> no capitalismo (a cada 8 minutos as cadeiras mudam conforme a felicidade), <b>expurgos</b> no comunismo '
    'e <b>golpes militares</b> no fascismo se a Junta for ignorada.',
    '<b>Grupos sociais</b> (operários, empresários, militares, religiosos) com satisfação própria afetando a felicidade.',
    '<b>Revolução jogável</b>: em vez de troca instantânea, uma guerra civil curta em que parte do território se rebela.',
])
story.append(p('2.4 Equilíbrio', H2))
story.append(table([
    ['Problema observado nos testes', 'Proposta'],
    ['Países gigantes (Rússia, Canadá, China) dominam a maioria das partidas', 'Custo de manutenção por célula; penalidade de felicidade por território muito grande'],
    ['Rodada termina pelo tempo, quase nunca pela meta de 80%', 'Meta dinâmica (60% + bônus por eliminações) ou vitória por pontos'],
    ['Pequenos países têm pouco a fazer', 'Bônus de "nação pequena": pesquisa mais barata e diplomacia mais forte'],
    ['Trilhos de rotas entre bots cobrem muito o mapa', 'Limitar rotas por bot e mostrar trilhos estrangeiros mais apagados'],
], [8 * cm, 9 * cm]))

story.append(PageBreak())
story.append(p('3. Retenção e progressão', H1))
story += bullets([
    '<b>Perfil persistente</b> (DataStore): partidas jogadas, vitórias, países usados, maior território.',
    '<b>Conquistas</b>: "Vencer com um país com menos de 1% do mundo", "Interceptar 10 mísseis", "Passar uma lei por propina".',
    '<b>Temporadas</b> mensais com ranking global e cosméticos (cores de bandeira, molduras de retrato, trilhos dourados).',
    '<b>Missões diárias</b> curtas que incentivam explorar sistemas (ex.: "Venda 5.000 de comida no mercado").',
    '<b>Modo cenário</b>: mapas e datas históricas (Guerra Fria, 1914) com regimes e alianças iniciais diferentes.',
])

story.append(p('4. Social e multijogador', H1))
story += bullets([
    '<b>Chat diplomático</b> privado entre jogadores com propostas anexadas (comércio, aliança, pedido de ajuda).',
    '<b>Blocos de aliança</b> com vitória compartilhada e objetivos de bloco.',
    '<b>Espectador</b> melhorado para eliminados: seguir líderes, linha do tempo da partida e votação de "MVP".',
    '<b>Servidores privados</b> com regras configuráveis (duração, número de bots, sem mísseis).',
])

story.append(p('5. Interface e apresentação', H1))
story += bullets([
    '<b>Tutorial guiado</b> nos primeiros 3 minutos: escolher país, formar exército, atacar, construir fábrica, pesquisar.',
    '<b>Som e música</b>: trilha dinâmica (calma na paz, tensa na guerra), sons de trem, explosões e votação.',
    '<b>Animações de batalha</b> na frente de ataque (faíscas, fumaça) e de conquista de cidades.',
    '<b>Personagens</b>: falas curtas dos líderes de partido e generais ("Senhor, a Junta exige o alistamento!").',
    '<b>Modo celular</b>: HUD lateral recolhível, botões maiores e gestos para formar exércitos.',
    '<b>Acessibilidade</b>: paletas para daltonismo e tamanho de texto ajustável.',
])

story.append(p('6. Técnica e desempenho', H1))
story.append(table([
    ['Item', 'Situação', 'Proposta'],
    ['Simulação do servidor', '2,6 a 3,3 ms por tick com todos os sistemas', 'Ataques com candidatos incrementais e IA escalonada em vários ticks'],
    ['Mapa no cliente', '1,6 ms por atualização; detalhe em 10 quadros', 'Mipmap de bordas e cache de texturas da visão detalhada'],
    ['Rede', 'Estado 0,4 s + civilização 1 s por jogador', 'Pacotes em buffer e somente diferenças (delta)'],
    ['Testes', 'Testes headless da simulação e do desenho', 'Teste de interface automatizado e teste de carga com bots'],
    ['EditableImage', 'Precisa liberar as APIs no jogo publicado', 'Checar no início e avisar o dono se estiver desligado'],
], [3.6 * cm, 5.4 * cm, 8 * cm]))

story.append(p('7. Monetização (sem pagar para vencer)', H1))
story += bullets([
    '<b>Cosméticos</b>: cores e padrões de território, molduras de retrato, estilos de trilho e de barco.',
    '<b>Passe de temporada</b> com recompensas cosméticas e de perfil.',
    '<b>Servidores privados</b> pagos com regras personalizadas.',
    'Evitar vender tropas, ouro ou pesquisa dentro da partida, para manter o jogo justo.',
])

story.append(p('8. Roteiro sugerido', H1))
story.append(table([
    ['Fase', 'Duração', 'Entregas'],
    ['1. Estabilizar', '1 a 2 semanas', 'Teste no Studio, painel de depuração, registro de erros, ajustes de interface'],
    ['2. Equilibrar', '1 semana', 'Manutenção de território, meta dinâmica, bônus de nação pequena'],
    ['3. Reter', '2 a 3 semanas', 'Perfil persistente, conquistas, tutorial, som e música'],
    ['4. Aprofundar', '3 a 4 semanas', 'Suprimento, unidades aéreas e navais, eleições e golpes, contratos'],
    ['5. Publicar', '1 semana', 'Ícone, capas, descrição, servidores privados, temporada 1'],
], [3.2 * cm, 2.6 * cm, 11.2 * cm]))
story.append(Spacer(1, 10))
story.append(p('Estimativas para um desenvolvedor com apoio de IA, considerando que o núcleo da simulação já existe e está coberto por testes.', SMALL))

doc = SimpleDocTemplate(out, pagesize=A4, leftMargin=1.8 * cm, rightMargin=1.8 * cm, topMargin=1.7 * cm, bottomMargin=1.7 * cm,
                        title='Domínio Mundial - Proposta de melhorias', author='Domínio Mundial')
doc.build(story, onFirstPage=on_page, onLaterPages=on_page)
print('ok', out)
