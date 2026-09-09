-- descricao_atividade_e_tarifas.sql
--
-- De onde veio: a planilha "PRODUTIVIDADE ENC MAIKON GTM - ARAUCO", aba
-- APONTAMENTO, que é como o escritório consolida a produção hoje. Ela tem uma
-- coluna DESC. ATIVIDADE que o RDO não tinha, e é essa coluna que determina o
-- código de tarifa e a unidade de medida -- e, por consequência, a fórmula da
-- produção consolidada:
--
--     SE QTD. UND. preenchida  -> QTD. UND.
--     SENÃO SE unidade = 'HT'  -> hora final - hora inicial
--     SENÃO                    -> largura * comprimento
--
-- Sem a unidade, o painel não consegue calcular o número que o escritório usa.
--
-- Por que a descrição é um campo NOVO, e não o tipo_atividade que já existe:
-- são catálogos diferentes. tipo_atividade é o que o operador escolhe para o
-- formulário aparecer (51 itens, sem unidade); a descrição é o item de TARIFA
-- (108 itens, com a unidade no nome, incluindo máquinas como
-- "CAMINHÃO CAÇAMBA - HT"). Comparados um a um, 48 dos 51 tipos não têm
-- correspondente no catálogo de tarifas -- não é diferença de grafia, são
-- listas de coisas diferentes.
--
-- Decisão do Fábio (09/09), depois de ver esse levantamento: a lista aparece
-- INTEIRA para o operador, sem filtrar pelo tipo de atividade. Filtrar exigiria
-- um de-para tipo -> descrições, e como o catálogo de tarifas não cobre
-- drenagens, controle de erosão, obras de arte, captação de água, insumos,
-- pontes nem combate a incêndio, o filtro esconderia opções válidas em metade
-- dos casos. Também resolve a hora-máquina, cuja descrição correta depende da
-- MÁQUINA usada, não do serviço.
--
-- O campo é OPCIONAL por enquanto: apontamento sem descrição sincroniza normal
-- e aparece no painel sem produção consolidada. Travar em campo, com o operador
-- no meio do serviço e sem certeza de qual item escolher, seria pior.
--
-- Tudo aqui é ADITIVO (CLAUDE.md §1.1): uma coluna nova, linhas novas em
-- catálogos, e duas funções por CREATE OR REPLACE. Nada é removido, e o
-- script pode rodar duas vezes sem efeito diferente.

-- ---------------------------------------------------------------------------
-- 1. A coluna
-- ---------------------------------------------------------------------------
ALTER TABLE atividades ADD COLUMN IF NOT EXISTS descricao_atividade text;

COMMENT ON COLUMN atividades.descricao_atividade IS
  'Item do catálogo de tarifas escolhido pelo operador. Determina código de tarifa e unidade de medida (ver regras_negocio, tipo_regra = tarifa_descricao). Opcional: apontamento sem descrição não tem produção consolidada.';

-- ---------------------------------------------------------------------------
-- 2. O catálogo que o PWA vai mostrar -- 108 itens
-- ---------------------------------------------------------------------------
INSERT INTO cadastros (categoria, valor, ativo, ordem) VALUES
    ('descricao_atividade', 'ABERTURA DE ESTRADAS SEM DESTOCAMENTO OU DERRUBADA - M²', true, 1),
    ('descricao_atividade', 'AGULHAMENTO - M²', true, 2),
    ('descricao_atividade', 'CAMINHÃO CAÇAMBA - HT', true, 3),
    ('descricao_atividade', 'CAMINHÃO CAÇAMBA - HD', true, 4),
    ('descricao_atividade', 'CAMINHÃO CAÇAMBA - DIÁRIA', true, 5),
    ('descricao_atividade', 'CAMINHÃO PIPA - HT', true, 6),
    ('descricao_atividade', 'CAMINHÃO PIPA - HD', true, 7),
    ('descricao_atividade', 'CAMINHÃO PIPA - DIÁRIA', true, 8),
    ('descricao_atividade', 'CAMINHÃO PLATAFORMA - KM', true, 9),
    ('descricao_atividade', 'CAMINHÃO PLATAFORMA - DIÁRIA', true, 10),
    ('descricao_atividade', 'CARREGAMENTO DE MATERIAIS - M³', true, 11),
    ('descricao_atividade', 'CARRETA PRANCHA - KM', true, 12),
    ('descricao_atividade', 'CARRETA PRANCHA - DIÁRIA', true, 13),
    ('descricao_atividade', 'COMPACTAÇÃO DE BASE - M²', true, 14),
    ('descricao_atividade', 'CONSTRUÇÃO DE ATERRO - M³', true, 15),
    ('descricao_atividade', 'CONSTRUÇÃO DE BACIA DE RETENÇÃO - UN', true, 16),
    ('descricao_atividade', 'CONSTRUÇÃO DE CAIXA DE CONTENÇÃO - UN', true, 17),
    ('descricao_atividade', 'CONSTRUÇÃO DE CAMALHÃO/MURCHÃO - NÍVEL 1 (SECUNDÁRIA) - UN', true, 18),
    ('descricao_atividade', 'CONSTRUÇÃO DE CAMALHÃO/MURCHÃO - NÍVEL 2 (PRIMÁRIA) - UN', true, 19),
    ('descricao_atividade', 'CONSTRUÇÃO DE MINI CURVA - NÍVEL 1 - UN', true, 20),
    ('descricao_atividade', 'CONSTRUÇÃO DE MINI CURVA - NÍVEL 2 - UN', true, 21),
    ('descricao_atividade', 'CONSTRUÇÃO DE MINI CURVA - NÍVEL 3 - UN', true, 22),
    ('descricao_atividade', 'CONSTRUÇÃO DE MINI CURVA - NÍVEL 4 - UN', true, 23),
    ('descricao_atividade', 'CONSTRUÇÃO DE PONTO DE MÓDULO C/ DESTOCA - NÍVEL 1 - UN', true, 24),
    ('descricao_atividade', 'CONSTRUÇÃO DE PONTO DE MÓDULO C/ DESTOCA - NÍVEL 2 - UN', true, 25),
    ('descricao_atividade', 'CONSTRUÇÃO DE SAÍDAS D’ÁGUA - UN', true, 26),
    ('descricao_atividade', 'DERRUBADA DE ARVORE - NIVEL 1 - M²', true, 27),
    ('descricao_atividade', 'DERRUBADA DE ARVORE - NIVEL 2 - M²', true, 28),
    ('descricao_atividade', 'DESTOCA - NÍVEL 1 - M²', true, 29),
    ('descricao_atividade', 'DESTOCA - NÍVEL 2 - M²', true, 30),
    ('descricao_atividade', 'ELEVAÇÃO COM SOLO LOCAL - M³', true, 31),
    ('descricao_atividade', 'ESCAVAÇÃO E CARREGAMENTO - M³', true, 32),
    ('descricao_atividade', 'ESCAVADEIRA HIDRÁULICA - HT', true, 33),
    ('descricao_atividade', 'ESCAVADEIRA HIDRÁULICA - HD', true, 34),
    ('descricao_atividade', 'ESCAVADEIRA HIDRÁULICA - DIÁRIA', true, 35),
    ('descricao_atividade', 'LIMPEZA DE ACEIRO/GRADE - M²', true, 36),
    ('descricao_atividade', 'LIMPEZA DE BACIA DE RETENÇÃO - UN', true, 37),
    ('descricao_atividade', 'LIMPEZA DE CAIXA DE CONTENÇÃO - UN', true, 38),
    ('descricao_atividade', 'LIMPEZA DE CAMADA VEGETAL - M³', true, 39),
    ('descricao_atividade', 'LIMPEZA DE ESTRADA - M²', true, 40),
    ('descricao_atividade', 'LIMPEZA DE MINI CURVA - NÍVEL 1 - UN', true, 41),
    ('descricao_atividade', 'LIMPEZA DE MINI CURVA - NÍVEL 2 - UN', true, 42),
    ('descricao_atividade', 'LIMPEZA DE MINI CURVA - NÍVEL 3 - UN', true, 43),
    ('descricao_atividade', 'LIMPEZA DE MINI CURVA - NÍVEL 4 - UN', true, 44),
    ('descricao_atividade', 'LIMPEZA DE SAÍDAS D’ÁGUA - UN', true, 45),
    ('descricao_atividade', 'MOTONIVELADORA - HT', true, 46),
    ('descricao_atividade', 'MOTONIVELADORA - HD', true, 47),
    ('descricao_atividade', 'MOTONIVELADORA - DIÁRIA', true, 48),
    ('descricao_atividade', 'PÁ CARREGADEIRA - HT', true, 49),
    ('descricao_atividade', 'PÁ CARREGADEIRA - HD', true, 50),
    ('descricao_atividade', 'PÁ CARREGADEIRA - DIÁRIA', true, 51),
    ('descricao_atividade', 'PATROLAMENTO - M²', true, 52),
    ('descricao_atividade', 'PREPARO DE LEITO COM BRITA - M³', true, 53),
    ('descricao_atividade', 'PREPARO DE LEITO COM SOLO NÍVEL 1 (10cm) - M³', true, 54),
    ('descricao_atividade', 'PREPARO DE LEITO COM SOLO NÍVEL 1 (15cm) - M³', true, 55),
    ('descricao_atividade', 'PREPARO DE LEITO COM SOLO NÍVEL 1 (20cm) - M³', true, 56),
    ('descricao_atividade', 'PREPARO DE LEITO COM SOLO NÍVEL 1 (25cm) - M³', true, 57),
    ('descricao_atividade', 'RECUPERAÇÃO DE JAZIDA – NÍVEL 1 - M³', true, 58),
    ('descricao_atividade', 'REGULARIZAÇÃO DE BASE - M³', true, 59),
    ('descricao_atividade', 'RETROESCAVADEIRA - HT', true, 60),
    ('descricao_atividade', 'RETROESCAVADEIRA - HD', true, 61),
    ('descricao_atividade', 'RETROESCAVADEIRA - DIÁRIA', true, 62),
    ('descricao_atividade', 'ROLO COMPACTADOR - HT', true, 63),
    ('descricao_atividade', 'ROLO COMPACTADOR - HD', true, 64),
    ('descricao_atividade', 'ROLO COMPACTADOR - DIÁRIA', true, 65),
    ('descricao_atividade', 'SERVIÇO DE CAMINHÃO PRANCHA - KM', true, 66),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 0 - 2,5 km) - M³', true, 67),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 10 - 12,5 km) - M³', true, 68),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 100 - 125 km) - M³', true, 69),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 12,5 - 15 km) - M³', true, 70),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 125 - 150 km) - M³', true, 71),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 15 - 17,5 km) - M³', true, 72),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 150 - 175 km) - M³', true, 73),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 17,5 - 20 km) - M³', true, 74),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 175 - 200 km) - M³', true, 75),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 2,5 - 5 km) - M³', true, 76),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 20 - 22,5 km) - M³', true, 77),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 22,5 - 25 km) - M³', true, 78),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 25 - 30 km) - M³', true, 79),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 30 - 35 km) - M³', true, 80),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 35 - 40 km) - M³', true, 81),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 45 - 50 km) - M³', true, 82),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 5 - 7,5 km) - M³', true, 83),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 50 - 70 km) - M³', true, 84),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 7,5 - 10 km) - M³', true, 85),
    ('descricao_atividade', 'TRANSPORTE DE BRITA (DMT 70 - 100 km) - M³', true, 86),
    ('descricao_atividade', 'TRANSPORTE DE SOLOS (DMT 0 - 2,5 km) - M³', true, 87),
    ('descricao_atividade', 'TRANSPORTE DE SOLOS (DMT 10 - 12,5 km) - M³', true, 88),
    ('descricao_atividade', 'TRANSPORTE DE SOLOS (DMT 12,5 - 15 km) - M³', true, 89),
    ('descricao_atividade', 'TRANSPORTE DE SOLOS (DMT 15 - 17,5 km) - M³', true, 90),
    ('descricao_atividade', 'TRANSPORTE DE SOLOS (DMT 17,5 - 20 km) - M³', true, 91),
    ('descricao_atividade', 'TRANSPORTE DE SOLOS (DMT 2,5 - 5 km) - M³', true, 92),
    ('descricao_atividade', 'TRANSPORTE DE SOLOS (DMT 20 - 22,5 km) - M³', true, 93),
    ('descricao_atividade', 'TRANSPORTE DE SOLOS (DMT 22,5 - 25 km) - M³', true, 94),
    ('descricao_atividade', 'TRANSPORTE DE SOLOS (DMT 25 - 30 km) - M³', true, 95),
    ('descricao_atividade', 'TRANSPORTE DE SOLOS (DMT 30 - 35 km) - M³', true, 96),
    ('descricao_atividade', 'TRANSPORTE DE SOLOS (DMT 35 - 40 km) - M³', true, 97),
    ('descricao_atividade', 'TRANSPORTE DE SOLOS (DMT 40 - 45 km) - M³', true, 98),
    ('descricao_atividade', 'TRANSPORTE DE SOLOS (DMT 45 - 50 km) - M³', true, 99),
    ('descricao_atividade', 'TRANSPORTE DE SOLOS (DMT 5 - 7,5 km) - M³', true, 100),
    ('descricao_atividade', 'TRANSPORTE DE SOLOS (DMT 7,5 - 10 km) - M³', true, 101),
    ('descricao_atividade', 'TRATOR DE ESTEIRA - HT', true, 102),
    ('descricao_atividade', 'TRATOR DE ESTEIRA - HD', true, 103),
    ('descricao_atividade', 'TRATOR DE ESTEIRA - DIÁRIA', true, 104),
    ('descricao_atividade', 'TRATOR DE GRADE - HT', true, 105),
    ('descricao_atividade', 'TRATOR DE GRADE - HD', true, 106),
    ('descricao_atividade', 'TRATOR DE GRADE - DIÁRIA', true, 107),
    ('descricao_atividade', 'UMECTAÇÃO DE ESTRADAS - HT', true, 108)
ON CONFLICT (categoria, valor) DO UPDATE SET ativo = true;

-- ---------------------------------------------------------------------------
-- 3. De-para descrição -> código de tarifa + unidade
-- ---------------------------------------------------------------------------
-- Mora em regras_negocio porque a tabela já é (tipo_regra, chave, valor jsonb),
-- que é exatamente a forma de um de-para -- o mesmo padrão de
-- 'formulario_atividade'. Não precisou de tabela nova.
--
-- Conferido na origem: as 108 descrições são distintas, todas têm código e
-- unidade, e nenhum código é usado por duas descrições diferentes.
INSERT INTO regras_negocio (tipo_regra, chave, valor, ativo) VALUES
    ('tarifa_descricao', 'ABERTURA DE ESTRADAS SEM DESTOCAMENTO OU DERRUBADA - M²', '{"codigo":"1017","unidade":"M²"}'::jsonb, true),
    ('tarifa_descricao', 'AGULHAMENTO - M²', '{"codigo":"1022","unidade":"M²"}'::jsonb, true),
    ('tarifa_descricao', 'CAMINHÃO CAÇAMBA - HT', '{"codigo":"1083","unidade":"HT"}'::jsonb, true),
    ('tarifa_descricao', 'CAMINHÃO CAÇAMBA - HD', '{"codigo":"1094","unidade":"HD"}'::jsonb, true),
    ('tarifa_descricao', 'CAMINHÃO CAÇAMBA - DIÁRIA', '{"codigo":"1103","unidade":"DIÁRIA"}'::jsonb, true),
    ('tarifa_descricao', 'CAMINHÃO PIPA - HT', '{"codigo":"1084","unidade":"HT"}'::jsonb, true),
    ('tarifa_descricao', 'CAMINHÃO PIPA - HD', '{"codigo":"1095","unidade":"HD"}'::jsonb, true),
    ('tarifa_descricao', 'CAMINHÃO PIPA - DIÁRIA', '{"codigo":"1104","unidade":"DIÁRIA"}'::jsonb, true),
    ('tarifa_descricao', 'CAMINHÃO PLATAFORMA - KM', '{"codigo":"1089","unidade":"KM"}'::jsonb, true),
    ('tarifa_descricao', 'CAMINHÃO PLATAFORMA - DIÁRIA', '{"codigo":"1109","unidade":"DIÁRIA"}'::jsonb, true),
    ('tarifa_descricao', 'CARREGAMENTO DE MATERIAIS - M³', '{"codigo":"1029","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'CARRETA PRANCHA - KM', '{"codigo":"1088","unidade":"KM"}'::jsonb, true),
    ('tarifa_descricao', 'CARRETA PRANCHA - DIÁRIA', '{"codigo":"1108","unidade":"DIÁRIA"}'::jsonb, true),
    ('tarifa_descricao', 'COMPACTAÇÃO DE BASE - M²', '{"codigo":"1023","unidade":"M²"}'::jsonb, true),
    ('tarifa_descricao', 'CONSTRUÇÃO DE ATERRO - M³', '{"codigo":"1077","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'CONSTRUÇÃO DE BACIA DE RETENÇÃO - UN', '{"codigo":"1005","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'CONSTRUÇÃO DE CAIXA DE CONTENÇÃO - UN', '{"codigo":"1001","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'CONSTRUÇÃO DE CAMALHÃO/MURCHÃO - NÍVEL 1 (SECUNDÁRIA) - UN', '{"codigo":"1015","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'CONSTRUÇÃO DE CAMALHÃO/MURCHÃO - NÍVEL 2 (PRIMÁRIA) - UN', '{"codigo":"1016","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'CONSTRUÇÃO DE MINI CURVA - NÍVEL 1 - UN', '{"codigo":"1007","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'CONSTRUÇÃO DE MINI CURVA - NÍVEL 2 - UN', '{"codigo":"1008","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'CONSTRUÇÃO DE MINI CURVA - NÍVEL 3 - UN', '{"codigo":"1009","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'CONSTRUÇÃO DE MINI CURVA - NÍVEL 4 - UN', '{"codigo":"1010","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'CONSTRUÇÃO DE PONTO DE MÓDULO C/ DESTOCA - NÍVEL 1 - UN', '{"codigo":"1025","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'CONSTRUÇÃO DE PONTO DE MÓDULO C/ DESTOCA - NÍVEL 2 - UN', '{"codigo":"1026","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'CONSTRUÇÃO DE SAÍDAS D’ÁGUA - UN', '{"codigo":"1003","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'DERRUBADA DE ARVORE - NIVEL 1 - M²', '{"codigo":"1018","unidade":"M²"}'::jsonb, true),
    ('tarifa_descricao', 'DERRUBADA DE ARVORE - NIVEL 2 - M²', '{"codigo":"1019","unidade":"M²"}'::jsonb, true),
    ('tarifa_descricao', 'DESTOCA - NÍVEL 1 - M²', '{"codigo":"1020","unidade":"M²"}'::jsonb, true),
    ('tarifa_descricao', 'DESTOCA - NÍVEL 2 - M²', '{"codigo":"1021","unidade":"M²"}'::jsonb, true),
    ('tarifa_descricao', 'ELEVAÇÃO COM SOLO LOCAL - M³', '{"codigo":"1037","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'ESCAVAÇÃO E CARREGAMENTO - M³', '{"codigo":"1031","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'ESCAVADEIRA HIDRÁULICA - HT', '{"codigo":"1080","unidade":"HT"}'::jsonb, true),
    ('tarifa_descricao', 'ESCAVADEIRA HIDRÁULICA - HD', '{"codigo":"1091","unidade":"HD"}'::jsonb, true),
    ('tarifa_descricao', 'ESCAVADEIRA HIDRÁULICA - DIÁRIA', '{"codigo":"1100","unidade":"DIÁRIA"}'::jsonb, true),
    ('tarifa_descricao', 'LIMPEZA DE ACEIRO/GRADE - M²', '{"codigo":"1024","unidade":"M²"}'::jsonb, true),
    ('tarifa_descricao', 'LIMPEZA DE BACIA DE RETENÇÃO - UN', '{"codigo":"1006","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'LIMPEZA DE CAIXA DE CONTENÇÃO - UN', '{"codigo":"1002","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'LIMPEZA DE CAMADA VEGETAL - M³', '{"codigo":"1030","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'LIMPEZA DE ESTRADA - M²', '{"codigo":"1028","unidade":"M²"}'::jsonb, true),
    ('tarifa_descricao', 'LIMPEZA DE MINI CURVA - NÍVEL 1 - UN', '{"codigo":"1011","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'LIMPEZA DE MINI CURVA - NÍVEL 2 - UN', '{"codigo":"1012","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'LIMPEZA DE MINI CURVA - NÍVEL 3 - UN', '{"codigo":"1013","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'LIMPEZA DE MINI CURVA - NÍVEL 4 - UN', '{"codigo":"1014","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'LIMPEZA DE SAÍDAS D’ÁGUA - UN', '{"codigo":"1004","unidade":"UN"}'::jsonb, true),
    ('tarifa_descricao', 'MOTONIVELADORA - HT', '{"codigo":"1079","unidade":"HT"}'::jsonb, true),
    ('tarifa_descricao', 'MOTONIVELADORA - HD', '{"codigo":"1090","unidade":"HD"}'::jsonb, true),
    ('tarifa_descricao', 'MOTONIVELADORA - DIÁRIA', '{"codigo":"1099","unidade":"DIÁRIA"}'::jsonb, true),
    ('tarifa_descricao', 'PÁ CARREGADEIRA - HT', '{"codigo":"1085","unidade":"HT"}'::jsonb, true),
    ('tarifa_descricao', 'PÁ CARREGADEIRA - HD', '{"codigo":"1096","unidade":"HD"}'::jsonb, true),
    ('tarifa_descricao', 'PÁ CARREGADEIRA - DIÁRIA', '{"codigo":"1105","unidade":"DIÁRIA"}'::jsonb, true),
    ('tarifa_descricao', 'PATROLAMENTO - M²', '{"codigo":"1027","unidade":"M²"}'::jsonb, true),
    ('tarifa_descricao', 'PREPARO DE LEITO COM BRITA - M³', '{"codigo":"1036","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'PREPARO DE LEITO COM SOLO NÍVEL 1 (10cm) - M³', '{"codigo":"1032","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'PREPARO DE LEITO COM SOLO NÍVEL 1 (15cm) - M³', '{"codigo":"1033","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'PREPARO DE LEITO COM SOLO NÍVEL 1 (20cm) - M³', '{"codigo":"1034","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'PREPARO DE LEITO COM SOLO NÍVEL 1 (25cm) - M³', '{"codigo":"1035","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'RECUPERAÇÃO DE JAZIDA – NÍVEL 1 - M³', '{"codigo":"1078","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'REGULARIZAÇÃO DE BASE - M³', '{"codigo":"1038","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'RETROESCAVADEIRA - HT', '{"codigo":"1081","unidade":"HT"}'::jsonb, true),
    ('tarifa_descricao', 'RETROESCAVADEIRA - HD', '{"codigo":"1092","unidade":"HD"}'::jsonb, true),
    ('tarifa_descricao', 'RETROESCAVADEIRA - DIÁRIA', '{"codigo":"1101","unidade":"DIÁRIA"}'::jsonb, true),
    ('tarifa_descricao', 'ROLO COMPACTADOR - HT', '{"codigo":"1082","unidade":"HT"}'::jsonb, true),
    ('tarifa_descricao', 'ROLO COMPACTADOR - HD', '{"codigo":"1093","unidade":"HD"}'::jsonb, true),
    ('tarifa_descricao', 'ROLO COMPACTADOR - DIÁRIA', '{"codigo":"1102","unidade":"DIÁRIA"}'::jsonb, true),
    ('tarifa_descricao', 'SERVIÇO DE CAMINHÃO PRANCHA - KM', '{"codigo":"1040","unidade":"KM"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 0 - 2,5 km) - M³', '{"codigo":"1056","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 10 - 12,5 km) - M³', '{"codigo":"1060","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 100 - 125 km) - M³', '{"codigo":"1073","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 12,5 - 15 km) - M³', '{"codigo":"1061","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 125 - 150 km) - M³', '{"codigo":"1074","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 15 - 17,5 km) - M³', '{"codigo":"1062","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 150 - 175 km) - M³', '{"codigo":"1075","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 17,5 - 20 km) - M³', '{"codigo":"1063","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 175 - 200 km) - M³', '{"codigo":"1076","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 2,5 - 5 km) - M³', '{"codigo":"1057","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 20 - 22,5 km) - M³', '{"codigo":"1064","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 22,5 - 25 km) - M³', '{"codigo":"1065","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 25 - 30 km) - M³', '{"codigo":"1066","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 30 - 35 km) - M³', '{"codigo":"1067","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 35 - 40 km) - M³', '{"codigo":"1068","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 45 - 50 km) - M³', '{"codigo":"1070","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 5 - 7,5 km) - M³', '{"codigo":"1058","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 50 - 70 km) - M³', '{"codigo":"1071","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 7,5 - 10 km) - M³', '{"codigo":"1059","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE BRITA (DMT 70 - 100 km) - M³', '{"codigo":"1072","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE SOLOS (DMT 0 - 2,5 km) - M³', '{"codigo":"1041","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE SOLOS (DMT 10 - 12,5 km) - M³', '{"codigo":"1045","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE SOLOS (DMT 12,5 - 15 km) - M³', '{"codigo":"1046","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE SOLOS (DMT 15 - 17,5 km) - M³', '{"codigo":"1047","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE SOLOS (DMT 17,5 - 20 km) - M³', '{"codigo":"1048","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE SOLOS (DMT 2,5 - 5 km) - M³', '{"codigo":"1042","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE SOLOS (DMT 20 - 22,5 km) - M³', '{"codigo":"1049","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE SOLOS (DMT 22,5 - 25 km) - M³', '{"codigo":"1050","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE SOLOS (DMT 25 - 30 km) - M³', '{"codigo":"1051","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE SOLOS (DMT 30 - 35 km) - M³', '{"codigo":"1052","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE SOLOS (DMT 35 - 40 km) - M³', '{"codigo":"1053","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE SOLOS (DMT 40 - 45 km) - M³', '{"codigo":"1054","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE SOLOS (DMT 45 - 50 km) - M³', '{"codigo":"1055","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE SOLOS (DMT 5 - 7,5 km) - M³', '{"codigo":"1043","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRANSPORTE DE SOLOS (DMT 7,5 - 10 km) - M³', '{"codigo":"1044","unidade":"M³"}'::jsonb, true),
    ('tarifa_descricao', 'TRATOR DE ESTEIRA - HT', '{"codigo":"1086","unidade":"HT"}'::jsonb, true),
    ('tarifa_descricao', 'TRATOR DE ESTEIRA - HD', '{"codigo":"1097","unidade":"HD"}'::jsonb, true),
    ('tarifa_descricao', 'TRATOR DE ESTEIRA - DIÁRIA', '{"codigo":"1106","unidade":"DIÁRIA"}'::jsonb, true),
    ('tarifa_descricao', 'TRATOR DE GRADE - HT', '{"codigo":"1087","unidade":"HT"}'::jsonb, true),
    ('tarifa_descricao', 'TRATOR DE GRADE - HD', '{"codigo":"1098","unidade":"HD"}'::jsonb, true),
    ('tarifa_descricao', 'TRATOR DE GRADE - DIÁRIA', '{"codigo":"1107","unidade":"DIÁRIA"}'::jsonb, true),
    ('tarifa_descricao', 'UMECTAÇÃO DE ESTRADAS - HT', '{"codigo":"1039","unidade":"HT"}'::jsonb, true)
ON CONFLICT (tipo_regra, chave) DO UPDATE SET valor = EXCLUDED.valor, ativo = true;

-- ---------------------------------------------------------------------------
-- 4. sincronizar_relatorio_rdo passa a gravar a descrição
-- ---------------------------------------------------------------------------
-- Só duas linhas mudam de verdade (o campo no INSERT e no UPDATE), mas a função
-- vai inteira porque CREATE OR REPLACE substitui o corpo todo -- não existe
-- "aplicar só a parte que mudou" aqui.
--
-- O UPDATE roda apenas no ramo status_revisao = 'devolvido': é a trava de
-- edição pós-envio (trava_edicao_pos_envio.sql), e a descrição obedece a ela
-- como qualquer outro campo. Trocar a descrição troca a tarifa, então deixá-la
-- editável fora da devolução reabriria o furo do "validado que muda sozinho".
CREATE OR REPLACE FUNCTION public.sincronizar_relatorio_rdo(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uuid_dispositivo uuid := (p_payload->>'uuid_dispositivo')::uuid;
  v_relatorio_id     uuid;
  v_ativ             jsonb;
  v_ativ_id          uuid;
  v_uuid_ativ_disp   uuid;
  v_status_atual     text;
  v_numero_atual     bigint;
  v_eq               jsonb;
  v_maq              jsonb;
  v_foto             jsonb;
  v_ordem            int := 0;
  v_ids_recebidos    uuid[] := '{}';
  v_congeladas       int := 0;
  v_remocoes_negadas int := 0;
  v_numeros          jsonb := '{}'::jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'É preciso estar logado para sincronizar.';
  END IF;
  IF v_uuid_dispositivo IS NULL THEN
    RAISE EXCEPTION 'uuid_dispositivo é obrigatório.';
  END IF;
  IF p_payload->>'cliente' IS NULL OR p_payload->>'data' IS NULL THEN
    RAISE EXCEPTION 'Relatório incompleto: cliente e data são obrigatórios.';
  END IF;

  INSERT INTO relatorios (
    uuid_dispositivo, criado_por, empresa, cliente, contrato, faena, tipo_estrada,
    equipe_frente, fazenda, data_relatorio, encarregado, supervisor,
    tecnico_arauco, supervisor_arauco, gps_lat, gps_lng, gps_precisao,
    gps_capturado_em, criado_em, concluido_em
  ) VALUES (
    v_uuid_dispositivo, auth.uid(),
    coalesce(p_payload->>'empresa', 'GTM'),
    p_payload->>'cliente', p_payload->>'contrato', p_payload->>'faena',
    p_payload->>'tipo_estrada', p_payload->>'equipe_frente', p_payload->>'fazenda',
    (p_payload->>'data')::date,
    p_payload->>'encarregado', p_payload->>'supervisor',
    p_payload->>'tecnico_arauco', p_payload->>'supervisor_arauco',
    (p_payload->'gps'->>'lat')::double precision,
    (p_payload->'gps'->>'lng')::double precision,
    (p_payload->'gps'->>'precisao')::numeric,
    (p_payload->'gps'->>'capturadoEm')::timestamptz,
    coalesce((p_payload->>'criadoEm')::timestamptz, now()),
    (p_payload->>'concluidoEm')::timestamptz
  )
  ON CONFLICT (uuid_dispositivo) DO UPDATE SET
    cliente            = EXCLUDED.cliente,
    contrato           = EXCLUDED.contrato,
    faena              = EXCLUDED.faena,
    tipo_estrada       = EXCLUDED.tipo_estrada,
    equipe_frente      = EXCLUDED.equipe_frente,
    fazenda            = EXCLUDED.fazenda,
    data_relatorio     = EXCLUDED.data_relatorio,
    encarregado        = EXCLUDED.encarregado,
    supervisor         = EXCLUDED.supervisor,
    tecnico_arauco     = EXCLUDED.tecnico_arauco,
    supervisor_arauco  = EXCLUDED.supervisor_arauco,
    gps_lat            = EXCLUDED.gps_lat,
    gps_lng            = EXCLUDED.gps_lng,
    gps_precisao       = EXCLUDED.gps_precisao,
    gps_capturado_em   = EXCLUDED.gps_capturado_em,
    concluido_em       = EXCLUDED.concluido_em,
    sincronizado_em    = now()
  RETURNING id INTO v_relatorio_id;

  FOR v_ativ IN SELECT * FROM jsonb_array_elements(coalesce(p_payload->'atividades', '[]'::jsonb))
  LOOP
    v_uuid_ativ_disp := nullif(v_ativ->>'id', '')::uuid;
    IF v_uuid_ativ_disp IS NULL THEN
      v_uuid_ativ_disp := gen_random_uuid();
    END IF;
    v_ids_recebidos := array_append(v_ids_recebidos, v_uuid_ativ_disp);

    SELECT id, status_revisao, numero INTO v_ativ_id, v_status_atual, v_numero_atual
      FROM atividades
     WHERE relatorio_id = v_relatorio_id
       AND uuid_atividade_dispositivo = v_uuid_ativ_disp
     FOR UPDATE;

    IF v_ativ_id IS NULL THEN
      INSERT INTO atividades (
        relatorio_id, ordem, uuid_atividade_dispositivo, tipo_atividade,
        descricao_atividade, up,
        comprimento_m, largura_m, profundidade_cm, dmt_km_inicial, dmt_km_final,
        trecho, tipo, observacao, data_execucao, status_revisao
      ) VALUES (
        v_relatorio_id, v_ordem, v_uuid_ativ_disp, v_ativ->>'tipo_atividade',
        nullif(v_ativ->>'descricao_atividade', ''), v_ativ->>'up',
        (v_ativ->>'comprimento_m')::numeric, (v_ativ->>'largura_m')::numeric,
        (v_ativ->>'profundidade_cm')::numeric, (v_ativ->>'dmt_km_inicial')::numeric,
        (v_ativ->>'dmt_km_final')::numeric, v_ativ->>'trecho', v_ativ->>'tipo',
        v_ativ->>'observacao', (v_ativ->>'data_execucao')::date,
        'pendente'
      ) RETURNING id, numero INTO v_ativ_id, v_numero_atual;

    ELSIF v_status_atual = 'devolvido' THEN
      UPDATE atividades SET
        ordem               = v_ordem,
        tipo_atividade      = v_ativ->>'tipo_atividade',
        descricao_atividade = nullif(v_ativ->>'descricao_atividade', ''),
        up                  = v_ativ->>'up',
        comprimento_m       = (v_ativ->>'comprimento_m')::numeric,
        largura_m           = (v_ativ->>'largura_m')::numeric,
        profundidade_cm     = (v_ativ->>'profundidade_cm')::numeric,
        dmt_km_inicial      = (v_ativ->>'dmt_km_inicial')::numeric,
        dmt_km_final        = (v_ativ->>'dmt_km_final')::numeric,
        trecho              = v_ativ->>'trecho',
        tipo                = v_ativ->>'tipo',
        observacao          = v_ativ->>'observacao',
        data_execucao       = (v_ativ->>'data_execucao')::date,
        status_revisao      = 'pendente',
        motivo_devolucao    = NULL,
        excluido_em         = NULL,
        excluido_por        = NULL
      WHERE id = v_ativ_id;

    ELSE
      -- Congelada: nada muda, mas o número vai na resposta do mesmo jeito --
      -- o operador precisa vê-lo justamente para citar o apontamento.
      v_congeladas := v_congeladas + 1;
      v_numeros := jsonb_set(v_numeros, ARRAY[v_uuid_ativ_disp::text], to_jsonb(v_numero_atual));
      v_ordem := v_ordem + 1;
      CONTINUE;
    END IF;

    v_numeros := jsonb_set(v_numeros, ARRAY[v_uuid_ativ_disp::text], to_jsonb(v_numero_atual));

    DELETE FROM atividade_equipamentos WHERE atividade_id = v_ativ_id;
    DELETE FROM atividade_maquinas     WHERE atividade_id = v_ativ_id;
    DELETE FROM evidencias_fotos       WHERE atividade_id = v_ativ_id;

    FOR v_eq IN SELECT * FROM jsonb_array_elements(coalesce(v_ativ->'equipamentos', '[]'::jsonb))
    LOOP
      INSERT INTO atividade_equipamentos (atividade_id, equipamento, operador)
      VALUES (v_ativ_id, v_eq->>'equipamento', v_eq->>'operador');
    END LOOP;

    FOR v_maq IN SELECT * FROM jsonb_array_elements(coalesce(v_ativ->'maquinas', '[]'::jsonb))
    LOOP
      INSERT INTO atividade_maquinas (atividade_id, equipamento, operador, dados)
      VALUES (v_ativ_id, v_maq->>'equipamento', v_maq->>'operador',
              coalesce(v_maq->'dados', '{}'::jsonb));
    END LOOP;

    FOR v_foto IN SELECT * FROM jsonb_array_elements(coalesce(v_ativ->'fotos', '[]'::jsonb))
    LOOP
      INSERT INTO evidencias_fotos (atividade_id, storage_path)
      VALUES (v_ativ_id, v_foto->>'storage_path');
    END LOOP;

    v_ordem := v_ordem + 1;
  END LOOP;

  UPDATE atividades
     SET excluido_em  = now(),
         excluido_por = auth.uid()
   WHERE relatorio_id = v_relatorio_id
     AND NOT (uuid_atividade_dispositivo = ANY(v_ids_recebidos))
     AND excluido_em IS NULL
     AND status_revisao = 'devolvido';

  SELECT count(*) INTO v_remocoes_negadas
    FROM atividades
   WHERE relatorio_id = v_relatorio_id
     AND NOT (uuid_atividade_dispositivo = ANY(v_ids_recebidos))
     AND excluido_em IS NULL
     AND status_revisao <> 'devolvido';

  RETURN jsonb_build_object(
    'id', v_relatorio_id,
    'uuid_dispositivo', v_uuid_dispositivo,
    'sincronizado_em', now(),
    'congeladas', v_congeladas,
    'remocoes_negadas', v_remocoes_negadas,
    'numeros', v_numeros
  );
END;
$function$;

-- As duas linhas de sempre (BOAS_PRATICAS.md §2). O anon continua alcançando
-- esta função de propósito: é a única que o PWA chama, e revogar derrubaria o
-- app que está em campo.
REVOKE ALL ON FUNCTION public.sincronizar_relatorio_rdo(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sincronizar_relatorio_rdo(jsonb) TO anon, authenticated;


-- ---------------------------------------------------------------------------
-- 5. listar_relatorios_painel devolve a descrição, o código e a unidade
-- ---------------------------------------------------------------------------
-- O código e a unidade vêm resolvidos daqui, e não do painel, por dois motivos:
-- o painel teria de baixar o catálogo inteiro para fazer o de-para no navegador,
-- e -- o que pesa mais -- unidade é o que decide a fórmula da produção, ou seja,
-- número que vira faturamento. Isso se calcula no servidor (BOAS_PRATICAS §2).
--
-- Guardar o código na atividade seria mais rápido de ler, mas erraria: a tarifa
-- muda com o tempo, e um código congelado no apontamento passaria a mentir
-- sobre o que aquele item vale hoje. Aqui ele é sempre o vigente.
CREATE OR REPLACE FUNCTION public.listar_relatorios_painel(
  p_data_inicio date DEFAULT NULL::date,
  p_data_fim date DEFAULT NULL::date,
  p_cliente text DEFAULT NULL::text,
  p_fazenda text DEFAULT NULL::text,
  p_limite integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_resultado jsonb;
BEGIN
  PERFORM exige_mfa();

  SELECT coalesce(jsonb_agg(r), '[]'::jsonb) INTO v_resultado
  FROM (
    SELECT jsonb_build_object(
      'id', rel.id,
      'cliente', rel.cliente,
      'contrato', rel.contrato,
      'faena', rel.faena,
      'tipo_estrada', rel.tipo_estrada,
      'equipe_frente', rel.equipe_frente,
      'fazenda', rel.fazenda,
      'data_relatorio', rel.data_relatorio,
      'encarregado', rel.encarregado,
      'supervisor', rel.supervisor,
      'tecnico_arauco', rel.tecnico_arauco,
      'supervisor_arauco', rel.supervisor_arauco,
      'gps_lat', rel.gps_lat,
      'gps_lng', rel.gps_lng,
      'sincronizado_em', rel.sincronizado_em,
      'atividades', (
        SELECT coalesce(jsonb_agg(jsonb_build_object(
          'id', a.id,
          'numero', a.numero,
          'tipo_atividade', a.tipo_atividade,
          'descricao_atividade', a.descricao_atividade,
          'codigo_tarifa', tar.valor->>'codigo',
          'unidade_tarifa', tar.valor->>'unidade',
          'up', a.up,
          'comprimento_m', a.comprimento_m,
          'largura_m', a.largura_m,
          'profundidade_cm', a.profundidade_cm,
          'dmt_km_inicial', a.dmt_km_inicial,
          'dmt_km_final', a.dmt_km_final,
          'trecho', a.trecho,
          'tipo', a.tipo,
          'observacao', a.observacao,
          'data_execucao', a.data_execucao,
          'status_revisao', a.status_revisao,
          'motivo_devolucao', a.motivo_devolucao,
          'revisado_em', a.revisado_em,
          'excluido_em', a.excluido_em,
          'status_anterior_exclusao',
            CASE WHEN a.excluido_em IS NOT NULL THEN a.status_revisao ELSE NULL END,
          'equipamentos', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('equipamento', e.equipamento, 'operador', e.operador)), '[]'::jsonb)
            FROM atividade_equipamentos e WHERE e.atividade_id = a.id
          ),
          'maquinas', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('equipamento', m.equipamento, 'operador', m.operador, 'dados', m.dados)), '[]'::jsonb)
            FROM atividade_maquinas m WHERE m.atividade_id = a.id
          ),
          'fotos', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('storage_path', f.storage_path)), '[]'::jsonb)
            FROM evidencias_fotos f WHERE f.atividade_id = a.id
          )
        ) ORDER BY (a.excluido_em IS NOT NULL), a.ordem), '[]'::jsonb)
        FROM atividades a
        -- LEFT: apontamento sem descrição (o campo é opcional) continua
        -- aparecendo, só que sem código nem unidade. Um JOIN comum sumiria com
        -- ele da tela do revisor, que é justamente quem precisa cobrar.
        LEFT JOIN regras_negocio tar
               ON tar.tipo_regra = 'tarifa_descricao'
              AND tar.chave = a.descricao_atividade
              AND tar.ativo
        WHERE a.relatorio_id = rel.id
      )
    ) AS r
    FROM relatorios rel
    WHERE (p_data_inicio IS NULL OR rel.data_relatorio >= p_data_inicio)
      AND (p_data_fim    IS NULL OR rel.data_relatorio <= p_data_fim)
      AND (p_cliente     IS NULL OR rel.cliente = p_cliente)
      AND (p_fazenda     IS NULL OR rel.fazenda = p_fazenda)
    ORDER BY rel.data_relatorio DESC
    LIMIT p_limite
  ) sub;

  RETURN v_resultado;
END;
$function$;

REVOKE ALL ON FUNCTION public.listar_relatorios_painel(date,date,text,text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.listar_relatorios_painel(date,date,text,text,integer) TO authenticated;
