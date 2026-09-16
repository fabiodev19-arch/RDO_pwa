-- valor_unitario_tarifas_17_09.sql
--
-- De onde veio: mesma "tabela tarifas ARAUCO.xlsx" de 17/09, coluna
-- R$/Unit., que tinha ficado de fora da primeira carga (descricao_
-- atividade_novos_itens_17_09.sql) a pedido do Fabio -- "por hora vamos
-- passo a passo". Ele voltou atras na mesma sessao: o valor vai ser usado
-- para compor um relatorio de faturamento no painel, mais para frente --
-- entao precisa estar no catalogo desde ja.
--
-- Onde entra: dentro do MESMO jsonb que ja guarda codigo/unidade
-- (regras_negocio, tipo_regra='tarifa_descricao'). Chave nova:
-- valor_unitario (numero, R$ por unidade de medida). Nenhuma tabela ou
-- coluna nova -- o jsonb ja existia, so ganhou mais uma chave.
--
-- Cobre as 112 descricoes (as 108 de 09-10/09 + as 4 novas desta sessao).
-- Os valores da planilha vinham com artefato de ponto flutuante binario
-- (138.61000000000001) -- arredondados para 2 casas, que e' como R$ se
-- escreve.
--
-- ATENCAO ao reaplicar: e' um UPDATE em cima de uma chave conhecida
-- (tipo_regra, chave), no MESMO padrao ja usado -- ON CONFLICT DO UPDATE
-- SET valor = EXCLUDED.valor. Isso SUBSTITUI o jsonb inteiro da linha, por
-- isso o VALUES abaixo repete codigo e unidade junto com o valor_unitario
-- novo -- nao e' um merge parcial, e' o objeto completo de novo.
--
-- Nada aqui muda producao_consolidada nem listar_relatorios_painel: os
-- dois continuam lendo so codigo/unidade. valor_unitario fica disponivel
-- no catalogo, sem nada usar ainda -- o relatorio que vai le-lo e' trabalho
-- futuro, fora do escopo desta carga.

INSERT INTO regras_negocio (tipo_regra, chave, valor, ativo)
SELECT 'tarifa_descricao', d.chave, d.valor, true
FROM (VALUES
    ('CONSTRUÇÃO DE CAIXA DE CONTENÇÃO - UN', '{"codigo":"1001","unidade":"UN","valor_unitario":243.83}'::jsonb),
    ('LIMPEZA DE CAIXA DE CONTENÇÃO - UN', '{"codigo":"1002","unidade":"UN","valor_unitario":187.56}'::jsonb),
    ('CONSTRUÇÃO DE SAÍDAS D’ÁGUA - UN', '{"codigo":"1003","unidade":"UN","valor_unitario":186.59}'::jsonb),
    ('LIMPEZA DE SAÍDAS D’ÁGUA - UN', '{"codigo":"1004","unidade":"UN","valor_unitario":138.61}'::jsonb),
    ('CONSTRUÇÃO DE BACIA DE RETENÇÃO - UN', '{"codigo":"1005","unidade":"UN","valor_unitario":325.11}'::jsonb),
    ('LIMPEZA DE BACIA DE RETENÇÃO - UN', '{"codigo":"1006","unidade":"UN","valor_unitario":256.66}'::jsonb),
    ('CONSTRUÇÃO DE MINI CURVA - NÍVEL 1 - UN', '{"codigo":"1007","unidade":"UN","valor_unitario":308.47}'::jsonb),
    ('CONSTRUÇÃO DE MINI CURVA - NÍVEL 2 - UN', '{"codigo":"1008","unidade":"UN","valor_unitario":479.84}'::jsonb),
    ('CONSTRUÇÃO DE MINI CURVA - NÍVEL 3 - UN', '{"codigo":"1009","unidade":"UN","valor_unitario":187.76}'::jsonb),
    ('CONSTRUÇÃO DE MINI CURVA - NÍVEL 4 - UN', '{"codigo":"1010","unidade":"UN","valor_unitario":227.29}'::jsonb),
    ('LIMPEZA DE MINI CURVA - NÍVEL 1 - UN', '{"codigo":"1011","unidade":"UN","valor_unitario":215.93}'::jsonb),
    ('LIMPEZA DE MINI CURVA - NÍVEL 2 - UN', '{"codigo":"1012","unidade":"UN","valor_unitario":239.92}'::jsonb),
    ('LIMPEZA DE MINI CURVA - NÍVEL 3 - UN', '{"codigo":"1013","unidade":"UN","valor_unitario":143.95}'::jsonb),
    ('LIMPEZA DE MINI CURVA - NÍVEL 4 - UN', '{"codigo":"1014","unidade":"UN","valor_unitario":159.95}'::jsonb),
    ('CONSTRUÇÃO DE CAMALHÃO/MURCHÃO - NÍVEL 1 (SECUNDÁRIA) - UN', '{"codigo":"1015","unidade":"UN","valor_unitario":254.03}'::jsonb),
    ('CONSTRUÇÃO DE CAMALHÃO/MURCHÃO - NÍVEL 2 (PRIMÁRIA) - UN', '{"codigo":"1016","unidade":"UN","valor_unitario":359.88}'::jsonb),
    ('ABERTURA DE ESTRADAS SEM DESTOCAMENTO OU DERRUBADA - M²', '{"codigo":"1017","unidade":"M²","valor_unitario":0.33}'::jsonb),
    ('DERRUBADA DE ARVORE - NIVEL 1 - M²', '{"codigo":"1018","unidade":"M²","valor_unitario":2.71}'::jsonb),
    ('DERRUBADA DE ARVORE - NIVEL 2 - M²', '{"codigo":"1019","unidade":"M²","valor_unitario":4.06}'::jsonb),
    ('DESTOCA - NÍVEL 1 - M²', '{"codigo":"1020","unidade":"M²","valor_unitario":5.13}'::jsonb),
    ('DESTOCA - NÍVEL 2 - M²', '{"codigo":"1021","unidade":"M²","valor_unitario":3.79}'::jsonb),
    ('AGULHAMENTO - M²', '{"codigo":"1022","unidade":"M²","valor_unitario":1.13}'::jsonb),
    ('COMPACTAÇÃO DE BASE - M²', '{"codigo":"1023","unidade":"M²","valor_unitario":2.44}'::jsonb),
    ('LIMPEZA DE ACEIRO/GRADE - M²', '{"codigo":"1024","unidade":"M²","valor_unitario":0.25}'::jsonb),
    ('CONSTRUÇÃO DE PONTO DE MÓDULO C/ DESTOCA - NÍVEL 1 - UN', '{"codigo":"1025","unidade":"UN","valor_unitario":8271.03}'::jsonb),
    ('CONSTRUÇÃO DE PONTO DE MÓDULO C/ DESTOCA - NÍVEL 2 - UN', '{"codigo":"1026","unidade":"UN","valor_unitario":12406.54}'::jsonb),
    ('PATROLAMENTO - M²', '{"codigo":"1027","unidade":"M²","valor_unitario":0.13}'::jsonb),
    ('LIMPEZA DE ESTRADA - M²', '{"codigo":"1028","unidade":"M²","valor_unitario":0.23}'::jsonb),
    ('CARREGAMENTO DE MATERIAIS - M³', '{"codigo":"1029","unidade":"M³","valor_unitario":5.81}'::jsonb),
    ('LIMPEZA DE CAMADA VEGETAL - M³', '{"codigo":"1030","unidade":"M³","valor_unitario":5.25}'::jsonb),
    ('ESCAVAÇÃO E CARREGAMENTO - M³', '{"codigo":"1031","unidade":"M³","valor_unitario":5.08}'::jsonb),
    ('PREPARO DE LEITO COM SOLO NÍVEL 1 (10cm) - M³', '{"codigo":"1032","unidade":"M³","valor_unitario":9.32}'::jsonb),
    ('PREPARO DE LEITO COM SOLO NÍVEL 1 (15cm) - M³', '{"codigo":"1033","unidade":"M³","valor_unitario":12.12}'::jsonb),
    ('PREPARO DE LEITO COM SOLO NÍVEL 1 (20cm) - M³', '{"codigo":"1034","unidade":"M³","valor_unitario":12.93}'::jsonb),
    ('PREPARO DE LEITO COM SOLO NÍVEL 1 (25cm) - M³', '{"codigo":"1035","unidade":"M³","valor_unitario":16.16}'::jsonb),
    ('PREPARO DE LEITO COM BRITA - M³', '{"codigo":"1036","unidade":"M³","valor_unitario":14.94}'::jsonb),
    ('ELEVAÇÃO COM SOLO LOCAL - M³', '{"codigo":"1037","unidade":"M³","valor_unitario":14}'::jsonb),
    ('REGULARIZAÇÃO DE BASE - M³', '{"codigo":"1038","unidade":"M³","valor_unitario":11.86}'::jsonb),
    ('UMECTAÇÃO DE ESTRADAS - HT', '{"codigo":"1039","unidade":"HT","valor_unitario":372.97}'::jsonb),
    ('SERVIÇO DE CAMINHÃO PRANCHA - KM', '{"codigo":"1040","unidade":"KM","valor_unitario":15.04}'::jsonb),
    ('TRANSPORTE DE SOLOS (DMT 0 - 2,5 km) - M³', '{"codigo":"1041","unidade":"M³","valor_unitario":12.46}'::jsonb),
    ('TRANSPORTE DE SOLOS (DMT 2,5 - 5 km) - M³', '{"codigo":"1042","unidade":"M³","valor_unitario":14.96}'::jsonb),
    ('TRANSPORTE DE SOLOS (DMT 5 - 7,5 km) - M³', '{"codigo":"1043","unidade":"M³","valor_unitario":17.95}'::jsonb),
    ('TRANSPORTE DE SOLOS (DMT 7,5 - 10 km) - M³', '{"codigo":"1044","unidade":"M³","valor_unitario":21.54}'::jsonb),
    ('TRANSPORTE DE SOLOS (DMT 10 - 12,5 km) - M³', '{"codigo":"1045","unidade":"M³","valor_unitario":25.85}'::jsonb),
    ('TRANSPORTE DE SOLOS (DMT 12,5 - 15 km) - M³', '{"codigo":"1046","unidade":"M³","valor_unitario":31.02}'::jsonb),
    ('TRANSPORTE DE SOLOS (DMT 15 - 17,5 km) - M³', '{"codigo":"1047","unidade":"M³","valor_unitario":37.22}'::jsonb),
    ('TRANSPORTE DE SOLOS (DMT 17,5 - 20 km) - M³', '{"codigo":"1048","unidade":"M³","valor_unitario":44.66}'::jsonb),
    ('TRANSPORTE DE SOLOS (DMT 20 - 22,5 km) - M³', '{"codigo":"1049","unidade":"M³","valor_unitario":53.59}'::jsonb),
    ('TRANSPORTE DE SOLOS (DMT 22,5 - 25 km) - M³', '{"codigo":"1050","unidade":"M³","valor_unitario":64.31}'::jsonb),
    ('TRANSPORTE DE SOLOS (DMT 25 - 30 km) - M³', '{"codigo":"1051","unidade":"M³","valor_unitario":77.18}'::jsonb),
    ('TRANSPORTE DE SOLOS (DMT 30 - 35 km) - M³', '{"codigo":"1052","unidade":"M³","valor_unitario":92.61}'::jsonb),
    ('TRANSPORTE DE SOLOS (DMT 35 - 40 km) - M³', '{"codigo":"1053","unidade":"M³","valor_unitario":111.13}'::jsonb),
    ('TRANSPORTE DE SOLOS (DMT 40 - 45 km) - M³', '{"codigo":"1054","unidade":"M³","valor_unitario":133.36}'::jsonb),
    ('TRANSPORTE DE SOLOS (DMT 45 - 50 km) - M³', '{"codigo":"1055","unidade":"M³","valor_unitario":160.03}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 0 - 2,5 km) - M³', '{"codigo":"1056","unidade":"M³","valor_unitario":9.59}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 2,5 - 5 km) - M³', '{"codigo":"1057","unidade":"M³","valor_unitario":13.42}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 5 - 7,5 km) - M³', '{"codigo":"1058","unidade":"M³","valor_unitario":18.79}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 7,5 - 10 km) - M³', '{"codigo":"1059","unidade":"M³","valor_unitario":22.18}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 10 - 12,5 km) - M³', '{"codigo":"1060","unidade":"M³","valor_unitario":26.17}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 12,5 - 15 km) - M³', '{"codigo":"1061","unidade":"M³","valor_unitario":30.88}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 15 - 17,5 km) - M³', '{"codigo":"1062","unidade":"M³","valor_unitario":36.43}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 17,5 - 20 km) - M³', '{"codigo":"1063","unidade":"M³","valor_unitario":42.99}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 20 - 22,5 km) - M³', '{"codigo":"1064","unidade":"M³","valor_unitario":50.73}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 22,5 - 25 km) - M³', '{"codigo":"1065","unidade":"M³","valor_unitario":59.86}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 25 - 30 km) - M³', '{"codigo":"1066","unidade":"M³","valor_unitario":70.64}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 30 - 35 km) - M³', '{"codigo":"1067","unidade":"M³","valor_unitario":98.89}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 35 - 40 km) - M³', '{"codigo":"1068","unidade":"M³","valor_unitario":116.69}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 40 - 45 km) - M³', '{"codigo":"1069","unidade":"M³","valor_unitario":129.53}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 45 - 50 km) - M³', '{"codigo":"1070","unidade":"M³","valor_unitario":143.78}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 50 - 70 km) - M³', '{"codigo":"1071","unidade":"M³","valor_unitario":159.59}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 70 - 100 km) - M³', '{"codigo":"1072","unidade":"M³","valor_unitario":177.15}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 100 - 125 km) - M³', '{"codigo":"1073","unidade":"M³","valor_unitario":196.64}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 125 - 150 km) - M³', '{"codigo":"1074","unidade":"M³","valor_unitario":218.27}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 150 - 175 km) - M³', '{"codigo":"1075","unidade":"M³","valor_unitario":242.28}'::jsonb),
    ('TRANSPORTE DE BRITA (DMT 175 - 200 km) - M³', '{"codigo":"1076","unidade":"M³","valor_unitario":268.93}'::jsonb),
    ('CONSTRUÇÃO DE ATERRO - M³', '{"codigo":"1077","unidade":"M³","valor_unitario":34.41}'::jsonb),
    ('RECUPERAÇÃO DE JAZIDA – NÍVEL 1 - M³', '{"codigo":"1078","unidade":"M³","valor_unitario":4.27}'::jsonb),
    ('MOTONIVELADORA - HT', '{"codigo":"1079","unidade":"HT","valor_unitario":556.93}'::jsonb),
    ('ESCAVADEIRA HIDRÁULICA - HT', '{"codigo":"1080","unidade":"HT","valor_unitario":521.8}'::jsonb),
    ('RETROESCAVADEIRA - HT', '{"codigo":"1081","unidade":"HT","valor_unitario":327.24}'::jsonb),
    ('ROLO COMPACTADOR - HT', '{"codigo":"1082","unidade":"HT","valor_unitario":369.1}'::jsonb),
    ('CAMINHÃO CAÇAMBA - HT', '{"codigo":"1083","unidade":"HT","valor_unitario":366.82}'::jsonb),
    ('CAMINHÃO PIPA - HT', '{"codigo":"1084","unidade":"HT","valor_unitario":372.97}'::jsonb),
    ('PÁ CARREGADEIRA - HT', '{"codigo":"1085","unidade":"HT","valor_unitario":410.11}'::jsonb),
    ('TRATOR DE ESTEIRA - HT', '{"codigo":"1086","unidade":"HT","valor_unitario":586.52}'::jsonb),
    ('TRATOR DE GRADE - HT', '{"codigo":"1087","unidade":"HT","valor_unitario":336.19}'::jsonb),
    ('CARRETA PRANCHA - KM', '{"codigo":"1088","unidade":"KM","valor_unitario":15.04}'::jsonb),
    ('CAMINHÃO PLATAFORMA - KM', '{"codigo":"1089","unidade":"KM","valor_unitario":12.03}'::jsonb),
    ('MOTONIVELADORA - HD', '{"codigo":"1090","unidade":"HD","valor_unitario":389.85}'::jsonb),
    ('ESCAVADEIRA HIDRÁULICA - HD', '{"codigo":"1091","unidade":"HD","valor_unitario":365.26}'::jsonb),
    ('RETROESCAVADEIRA - HD', '{"codigo":"1092","unidade":"HD","valor_unitario":229.07}'::jsonb),
    ('ROLO COMPACTADOR - HD', '{"codigo":"1093","unidade":"HD","valor_unitario":258.37}'::jsonb),
    ('CAMINHÃO CAÇAMBA - HD', '{"codigo":"1094","unidade":"HD","valor_unitario":256.78}'::jsonb),
    ('CAMINHÃO PIPA - HD', '{"codigo":"1095","unidade":"HD","valor_unitario":261.08}'::jsonb),
    ('PÁ CARREGADEIRA - HD', '{"codigo":"1096","unidade":"HD","valor_unitario":287.07}'::jsonb),
    ('TRATOR DE ESTEIRA - HD', '{"codigo":"1097","unidade":"HD","valor_unitario":410.56}'::jsonb),
    ('TRATOR DE GRADE - HD', '{"codigo":"1098","unidade":"HD","valor_unitario":235.33}'::jsonb),
    ('MOTONIVELADORA - DIÁRIA', '{"codigo":"1099","unidade":"DIÁRIA","valor_unitario":4901}'::jsonb),
    ('ESCAVADEIRA HIDRÁULICA - DIÁRIA', '{"codigo":"1100","unidade":"DIÁRIA","valor_unitario":4288.43}'::jsonb),
    ('RETROESCAVADEIRA - DIÁRIA', '{"codigo":"1101","unidade":"DIÁRIA","valor_unitario":2908.85}'::jsonb),
    ('ROLO COMPACTADOR - DIÁRIA', '{"codigo":"1102","unidade":"DIÁRIA","valor_unitario":3248.05}'::jsonb),
    ('CAMINHÃO CAÇAMBA - DIÁRIA', '{"codigo":"1103","unidade":"DIÁRIA","valor_unitario":3228.05}'::jsonb),
    ('CAMINHÃO PIPA - DIÁRIA', '{"codigo":"1104","unidade":"DIÁRIA","valor_unitario":3282.14}'::jsonb),
    ('PÁ CARREGADEIRA - DIÁRIA', '{"codigo":"1105","unidade":"DIÁRIA","valor_unitario":3608.93}'::jsonb),
    ('TRATOR DE ESTEIRA - DIÁRIA', '{"codigo":"1106","unidade":"DIÁRIA","valor_unitario":5161.34}'::jsonb),
    ('TRATOR DE GRADE - DIÁRIA', '{"codigo":"1107","unidade":"DIÁRIA","valor_unitario":2958.44}'::jsonb),
    ('CARRETA PRANCHA - DIÁRIA', '{"codigo":"1108","unidade":"DIÁRIA","valor_unitario":5001.75}'::jsonb),
    ('CAMINHÃO PLATAFORMA - DIÁRIA', '{"codigo":"1109","unidade":"DIÁRIA","valor_unitario":4001.4}'::jsonb),
    ('FORA DE BASE - HOSPEDAGEM - UN', '{"codigo":"1110","unidade":"UN","valor_unitario":200}'::jsonb),
    ('FORA DE BASE - JANTAR - UN', '{"codigo":"1111","unidade":"UN","valor_unitario":30}'::jsonb),
    ('FORA DE BASE - KM EXCEDENTE VEICULOS VÃO RODANDO - KM', '{"codigo":"1112","unidade":"KM","valor_unitario":3.48}'::jsonb)
) AS d(chave, valor)
ON CONFLICT (tipo_regra, chave) DO UPDATE SET valor = EXCLUDED.valor, ativo = true;
