-- descricao_atividade_novos_itens_17_09.sql
--
-- De onde veio: "tabela tarifas ARAUCO.xlsx", enviada pelo Fábio em 17/09 --
-- 112 linhas (Cod.Tarifa | Atividades | Medidas | R$/Unit.), o catálogo
-- oficial de tarifas, mais completo que a planilha de produção de 09/09 que
-- originou os 108 itens já carregados.
--
-- Comparado um a um com o catálogo atual (108 descrições no banco): as 108
-- batem EXATAMENTE -- mesma descrição, mesmo código, mesma unidade, zero
-- mudança. Só 4 são novas de verdade. Isto aqui carrega só essas 4 --
-- nada do que já existe é tocado.
--
-- Os valores em R$ (coluna R$/Unit.) NÃO entram aqui -- pedido do Fábio:
-- "por hora vamos passo a passo até chegarmos em valores que é um passo
-- mais a frente". Só descrição, código de tarifa e unidade, no mesmo
-- formato do catálogo já existente (regras_negocio, tipo_regra =
-- 'tarifa_descricao', valor = {codigo, unidade}).
--
-- ---------------------------------------------------------------------------
-- Os 4 itens, e por que cada um precisou de uma decisão antes de carregar
-- ---------------------------------------------------------------------------
--
-- 1. TRANSPORTE DE BRITA (DMT 40 - 45 km) - M³   [código 1069]
--    Fecha uma pendência já registrada no ESTADO.md desde 09/09: a faixa de
--    40-45 km de brita não tinha código no catálogo carregado naquele dia,
--    porque a planilha de produção não cobria essa faixa (ela cobria as
--    tarifas SEM medir preço). Na planilha nova, o texto da linha do código
--    1069 repetia "DMT 35 - 40 km" por engano -- o Fábio confirmou por print
--    da própria planilha que o texto certo é "40 - 45 km" (mesmo código,
--    mesmo valor). Carregado com o texto corrigido.
--
-- 2 a 4. As três tarifas "FORA DE BASE" (hospedagem, jantar, km excedente)
--    são genuinamente novas -- não existiam em nenhuma versão anterior do
--    catálogo. "FORA DE BASE - KM EXCEDENTE VEICULOS VÃO RODANDO" foi
--    carregado exatamente com o nome e a grafia da planilha (sem acento em
--    "VEICULOS", que é como está na origem).
--
-- ---------------------------------------------------------------------------
-- Sobre a estrutura da planilha nova, que é diferente da anterior
-- ---------------------------------------------------------------------------
-- A planilha de 09/09 já vinha com a descrição e a unidade no MESMO texto
-- ("CAMINHÃO CAÇAMBA - HT"). A nova separa "Atividades" (texto puro, ex.
-- "CAMINHÃO CAÇAMBA") de "Medidas" (unidade, ex. "HT") em colunas -- e por
-- isso a mesma atividade aparece em várias linhas quando tem mais de uma
-- unidade (as 9 máquinas em HT/HD/DIÁRIA, por exemplo). A descrição final
-- carregada no banco segue o padrão que já existe (texto + " - " + unidade),
-- e é isso que resolveu as 108 sem sobrar duplicata -- só o código 1069
-- (caso 1 acima) precisou de correção manual, confirmada pelo Fábio.
--
-- Tudo aditivo (CLAUDE.md §1.1): dois INSERT ON CONFLICT DO NOTHING. Nenhuma
-- coluna, função ou linha existente é alterada. O script pode rodar duas
-- vezes sem efeito diferente.

-- ---------------------------------------------------------------------------
-- 1. O catálogo que o PWA mostra -- os 4 itens novos
-- ---------------------------------------------------------------------------
INSERT INTO cadastros (categoria, valor, ativo, ordem) VALUES
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 40 - 45 km) - M³',
      true, (SELECT coalesce(max(ordem),0)+1 FROM cadastros WHERE categoria='descricao_atividade')),
    ('descricao_atividade', 'FORA DE BASE - HOSPEDAGEM - UN',
      true, (SELECT coalesce(max(ordem),0)+2 FROM cadastros WHERE categoria='descricao_atividade')),
    ('descricao_atividade', 'FORA DE BASE - JANTAR - UN',
      true, (SELECT coalesce(max(ordem),0)+3 FROM cadastros WHERE categoria='descricao_atividade')),
    ('descricao_atividade', 'FORA DE BASE - KM EXCEDENTE VEICULOS VÃO RODANDO - KM',
      true, (SELECT coalesce(max(ordem),0)+4 FROM cadastros WHERE categoria='descricao_atividade'))
ON CONFLICT (categoria, valor) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. De-para descrição -> código de tarifa + unidade -- os mesmos 4
-- ---------------------------------------------------------------------------
INSERT INTO regras_negocio (tipo_regra, chave, valor, ativo) VALUES
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 40 - 45 km) - M³',
      '{"codigo":"1069","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'FORA DE BASE - HOSPEDAGEM - UN',
      '{"codigo":"1110","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'FORA DE BASE - JANTAR - UN',
      '{"codigo":"1111","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'FORA DE BASE - KM EXCEDENTE VEICULOS VÃO RODANDO - KM',
      '{"codigo":"1112","unidade":"KM"}'::jsonb, true)
ON CONFLICT (tipo_regra, chave) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 3. Formulário por descrição -- mesma régua da semente de 14/09 (unidade
--    HT/HD -> hora_maquina, resto -> padrao). Nenhum dos 4 é HT/HD, então os
--    quatro caem em "padrao". Não é estritamente necessário (o PWA já cai em
--    "padrao" por padrão quando não há regra), mas mantém os 4 consistentes
--    com os outros 108, que TÊM regra explícita desde 14/09 -- sem isto, uma
--    varredura futura em regras_negocio acharia só 108 linhas de
--    formulario_descricao para 112 descrições, e pareceria uma omissão.
-- ---------------------------------------------------------------------------
INSERT INTO regras_negocio (tipo_regra, chave, valor, ativo) VALUES
    ('formulario_descricao', 'TRANSPORTE DE BRITA (DMT 40 - 45 km) - M³', '"padrao"'::jsonb, true),
    ('formulario_descricao', 'FORA DE BASE - HOSPEDAGEM - UN', '"padrao"'::jsonb, true),
    ('formulario_descricao', 'FORA DE BASE - JANTAR - UN', '"padrao"'::jsonb, true),
    ('formulario_descricao', 'FORA DE BASE - KM EXCEDENTE VEICULOS VÃO RODANDO - KM', '"padrao"'::jsonb, true)
ON CONFLICT (tipo_regra, chave) DO NOTHING;
