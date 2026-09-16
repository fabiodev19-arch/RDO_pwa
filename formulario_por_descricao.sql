-- ===========================================================================
-- Semente: formulário por DESCRIÇÃO da atividade  --  2026-09-14
-- ===========================================================================
--
-- Quem decide o formulário do PWA passa a ser a descrição, não o tipo de
-- atividade. Motivo, medido nas 2.126 linhas da aba APONTAMENTO: uma mesma
-- atividade reúne descrições que pedem formulários diferentes. Em DRENAGENS
-- IMPLANTAÇÃO convivem CONSTRUÇÃO DE MINI CURVA (quantidade e área, 560
-- linhas) e PÁ CARREGADEIRA - HT (só horas, 46 linhas).
--
-- A régua da semente: unidade HT/HD -> hora_maquina, resto -> padrao.
-- Das 19 descrições em HT/HD, 18 são literalmente nome de máquina.
--
-- NÃO sobrescreve regra já existente (o ON CONFLICT abaixo não toca em quem
-- já tem valor): escolha feita à mão no painel vale mais que o palpite.
--
-- Nenhum DDL. Só INSERT de dados em regras_negocio, que é a tabela de
-- configuração do projeto. As funções listar_regras() e salvar_regra() são
-- genéricas por tipo_regra, então nada precisou mudar no servidor.
-- ===========================================================================

INSERT INTO regras_negocio (tipo_regra, chave, valor, ativo)
SELECT 'formulario_descricao', d.chave, to_jsonb(d.forma), true
FROM (VALUES
  ('ABERTURA DE ESTRADAS SEM DESTOCAMENTO OU DERRUBADA - M²', 'padrao'),
  ('AGULHAMENTO - M²', 'padrao'),
  ('CAMINHÃO CAÇAMBA - DIÁRIA', 'padrao'),
  ('CAMINHÃO CAÇAMBA - HD', 'hora_maquina'),
  ('CAMINHÃO CAÇAMBA - HT', 'hora_maquina'),
  ('CAMINHÃO PIPA - DIÁRIA', 'padrao'),
  ('CAMINHÃO PIPA - HD', 'hora_maquina'),
  ('CAMINHÃO PIPA - HT', 'hora_maquina'),
  ('CAMINHÃO PLATAFORMA - DIÁRIA', 'padrao'),
  ('CAMINHÃO PLATAFORMA - KM', 'padrao'),
  ('CARREGAMENTO DE MATERIAIS - M³', 'padrao'),
  ('CARRETA PRANCHA - DIÁRIA', 'padrao'),
  ('CARRETA PRANCHA - KM', 'padrao'),
  ('COMPACTAÇÃO DE BASE - M²', 'padrao'),
  ('CONSTRUÇÃO DE ATERRO - M³', 'padrao'),
  ('CONSTRUÇÃO DE BACIA DE RETENÇÃO - UN', 'padrao'),
  ('CONSTRUÇÃO DE CAIXA DE CONTENÇÃO - UN', 'padrao'),
  ('CONSTRUÇÃO DE CAMALHÃO/MURCHÃO - NÍVEL 1 (SECUNDÁRIA) - UN', 'padrao'),
  ('CONSTRUÇÃO DE CAMALHÃO/MURCHÃO - NÍVEL 2 (PRIMÁRIA) - UN', 'padrao'),
  ('CONSTRUÇÃO DE MINI CURVA - NÍVEL 1 - UN', 'padrao'),
  ('CONSTRUÇÃO DE MINI CURVA - NÍVEL 2 - UN', 'padrao'),
  ('CONSTRUÇÃO DE MINI CURVA - NÍVEL 3 - UN', 'padrao'),
  ('CONSTRUÇÃO DE MINI CURVA - NÍVEL 4 - UN', 'padrao'),
  ('CONSTRUÇÃO DE PONTO DE MÓDULO C/ DESTOCA - NÍVEL 1 - UN', 'padrao'),
  ('CONSTRUÇÃO DE PONTO DE MÓDULO C/ DESTOCA - NÍVEL 2 - UN', 'padrao'),
  ('CONSTRUÇÃO DE SAÍDAS D’ÁGUA - UN', 'padrao'),
  ('DERRUBADA DE ARVORE - NIVEL 1 - M²', 'padrao'),
  ('DERRUBADA DE ARVORE - NIVEL 2 - M²', 'padrao'),
  ('DESTOCA - NÍVEL 1 - M²', 'padrao'),
  ('DESTOCA - NÍVEL 2 - M²', 'padrao'),
  ('ELEVAÇÃO COM SOLO LOCAL - M³', 'padrao'),
  ('ESCAVAÇÃO E CARREGAMENTO - M³', 'padrao'),
  ('ESCAVADEIRA HIDRÁULICA - DIÁRIA', 'padrao'),
  ('ESCAVADEIRA HIDRÁULICA - HD', 'hora_maquina'),
  ('ESCAVADEIRA HIDRÁULICA - HT', 'hora_maquina'),
  ('LIMPEZA DE ACEIRO/GRADE - M²', 'padrao'),
  ('LIMPEZA DE BACIA DE RETENÇÃO - UN', 'padrao'),
  ('LIMPEZA DE CAIXA DE CONTENÇÃO - UN', 'padrao'),
  ('LIMPEZA DE CAMADA VEGETAL - M³', 'padrao'),
  ('LIMPEZA DE ESTRADA - M²', 'padrao'),
  ('LIMPEZA DE MINI CURVA - NÍVEL 1 - UN', 'padrao'),
  ('LIMPEZA DE MINI CURVA - NÍVEL 2 - UN', 'padrao'),
  ('LIMPEZA DE MINI CURVA - NÍVEL 3 - UN', 'padrao'),
  ('LIMPEZA DE MINI CURVA - NÍVEL 4 - UN', 'padrao'),
  ('LIMPEZA DE SAÍDAS D’ÁGUA - UN', 'padrao'),
  ('MOTONIVELADORA - DIÁRIA', 'padrao'),
  ('MOTONIVELADORA - HD', 'hora_maquina'),
  ('MOTONIVELADORA - HT', 'hora_maquina'),
  ('PÁ CARREGADEIRA - DIÁRIA', 'padrao'),
  ('PÁ CARREGADEIRA - HD', 'hora_maquina'),
  ('PÁ CARREGADEIRA - HT', 'hora_maquina'),
  ('PATROLAMENTO - M²', 'padrao'),
  ('PREPARO DE LEITO COM BRITA - M³', 'padrao'),
  ('PREPARO DE LEITO COM SOLO NÍVEL 1 (10cm) - M³', 'padrao'),
  ('PREPARO DE LEITO COM SOLO NÍVEL 1 (15cm) - M³', 'padrao'),
  ('PREPARO DE LEITO COM SOLO NÍVEL 1 (20cm) - M³', 'padrao'),
  ('PREPARO DE LEITO COM SOLO NÍVEL 1 (25cm) - M³', 'padrao'),
  ('RECUPERAÇÃO DE JAZIDA – NÍVEL 1 - M³', 'padrao'),
  ('REGULARIZAÇÃO DE BASE - M³', 'padrao'),
  ('RETROESCAVADEIRA - DIÁRIA', 'padrao'),
  ('RETROESCAVADEIRA - HD', 'hora_maquina'),
  ('RETROESCAVADEIRA - HT', 'hora_maquina'),
  ('ROLO COMPACTADOR - DIÁRIA', 'padrao'),
  ('ROLO COMPACTADOR - HD', 'hora_maquina'),
  ('ROLO COMPACTADOR - HT', 'hora_maquina'),
  ('SERVIÇO DE CAMINHÃO PRANCHA - KM', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 0 - 2,5 km) - M³', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 10 - 12,5 km) - M³', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 100 - 125 km) - M³', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 12,5 - 15 km) - M³', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 125 - 150 km) - M³', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 15 - 17,5 km) - M³', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 150 - 175 km) - M³', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 17,5 - 20 km) - M³', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 175 - 200 km) - M³', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 2,5 - 5 km) - M³', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 20 - 22,5 km) - M³', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 22,5 - 25 km) - M³', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 25 - 30 km) - M³', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 30 - 35 km) - M³', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 35 - 40 km) - M³', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 45 - 50 km) - M³', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 5 - 7,5 km) - M³', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 50 - 70 km) - M³', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 7,5 - 10 km) - M³', 'padrao'),
  ('TRANSPORTE DE BRITA (DMT 70 - 100 km) - M³', 'padrao'),
  ('TRANSPORTE DE SOLOS (DMT 0 - 2,5 km) - M³', 'padrao'),
  ('TRANSPORTE DE SOLOS (DMT 10 - 12,5 km) - M³', 'padrao'),
  ('TRANSPORTE DE SOLOS (DMT 12,5 - 15 km) - M³', 'padrao'),
  ('TRANSPORTE DE SOLOS (DMT 15 - 17,5 km) - M³', 'padrao'),
  ('TRANSPORTE DE SOLOS (DMT 17,5 - 20 km) - M³', 'padrao'),
  ('TRANSPORTE DE SOLOS (DMT 2,5 - 5 km) - M³', 'padrao'),
  ('TRANSPORTE DE SOLOS (DMT 20 - 22,5 km) - M³', 'padrao'),
  ('TRANSPORTE DE SOLOS (DMT 22,5 - 25 km) - M³', 'padrao'),
  ('TRANSPORTE DE SOLOS (DMT 25 - 30 km) - M³', 'padrao'),
  ('TRANSPORTE DE SOLOS (DMT 30 - 35 km) - M³', 'padrao'),
  ('TRANSPORTE DE SOLOS (DMT 35 - 40 km) - M³', 'padrao'),
  ('TRANSPORTE DE SOLOS (DMT 40 - 45 km) - M³', 'padrao'),
  ('TRANSPORTE DE SOLOS (DMT 45 - 50 km) - M³', 'padrao'),
  ('TRANSPORTE DE SOLOS (DMT 5 - 7,5 km) - M³', 'padrao'),
  ('TRANSPORTE DE SOLOS (DMT 7,5 - 10 km) - M³', 'padrao'),
  ('TRATOR DE ESTEIRA - DIÁRIA', 'padrao'),
  ('TRATOR DE ESTEIRA - HD', 'hora_maquina'),
  ('TRATOR DE ESTEIRA - HT', 'hora_maquina'),
  ('TRATOR DE GRADE - DIÁRIA', 'padrao'),
  ('TRATOR DE GRADE - HD', 'hora_maquina'),
  ('TRATOR DE GRADE - HT', 'hora_maquina'),
  ('UMECTAÇÃO DE ESTRADAS - HT', 'hora_maquina')
) AS d(chave, forma)
ON CONFLICT DO NOTHING;
