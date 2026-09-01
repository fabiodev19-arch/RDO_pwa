-- ============================================================================
-- GTM RDO — schema principal
-- ============================================================================
-- Rode isso primeiro no SQL Editor do Supabase. Ainda sem RLS — o arquivo
-- sync_function_rdo.sql (rodar logo em seguida) tranca tudo e abre só as
-- funções controladas como porta de entrada, do mesmo jeito que fizemos no
-- schema_biomassa.sql + sync_function.sql.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. RELATÓRIOS (cabeçalho / identificação do RDO)
-- ----------------------------------------------------------------------------
CREATE TABLE relatorios (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  uuid_dispositivo   uuid NOT NULL UNIQUE, -- gerado no PWA; upsert usa essa chave

  empresa            text NOT NULL DEFAULT 'GTM',
  cliente            text NOT NULL,
  contrato           text NOT NULL,
  faena              text NOT NULL,
  tipo_estrada       text NOT NULL,
  equipe_frente      text NOT NULL,
  fazenda            text NOT NULL,
  data_relatorio     date NOT NULL,
  encarregado        text NOT NULL,
  supervisor         text NOT NULL,
  tecnico_arauco     text NOT NULL,
  supervisor_arauco  text NOT NULL,

  gps_lat            double precision,
  gps_lng            double precision,
  gps_precisao       numeric,
  gps_capturado_em   timestamptz,

  status             text NOT NULL DEFAULT 'concluido'
                       CHECK (status IN ('concluido')),

  criado_em          timestamptz NOT NULL,
  concluido_em       timestamptz,
  sincronizado_em    timestamptz NOT NULL DEFAULT now(),
  atualizado_em      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE relatorios IS 'Um RDO concluído e sincronizado pelo PWA de campo. Rascunhos não saem do aparelho.';
COMMENT ON COLUMN relatorios.uuid_dispositivo IS 'UUID gerado no PWA no momento da criação do relatório. Reenviar o mesmo relatório atualiza em vez de duplicar.';

CREATE INDEX idx_relatorios_data ON relatorios (data_relatorio DESC);
CREATE INDEX idx_relatorios_fazenda ON relatorios (fazenda);
CREATE INDEX idx_relatorios_cliente ON relatorios (cliente);

-- Mantém atualizado_em em dia a cada UPDATE
CREATE OR REPLACE FUNCTION trg_atualizar_timestamp()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.atualizado_em := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER relatorios_atualizado_em
  BEFORE UPDATE ON relatorios
  FOR EACH ROW EXECUTE FUNCTION trg_atualizar_timestamp();

-- ----------------------------------------------------------------------------
-- 2. ATIVIDADES (uma linha por atividade do dia, filha de relatorios)
-- ----------------------------------------------------------------------------
CREATE TABLE atividades (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relatorio_id       uuid NOT NULL REFERENCES relatorios(id) ON DELETE CASCADE,
  ordem              int NOT NULL DEFAULT 0,

  tipo_atividade     text NOT NULL,

  -- Atividades "de obra" (todas exceto Hora Máquina)
  comprimento_m      numeric,
  largura_m          numeric,
  profundidade_cm    numeric,
  dmt_km_inicial     numeric,
  dmt_km_final       numeric,
  trecho             text,

  -- Hora Máquina Trabalhada
  tipo               text, -- Carregamento | Transporte | Deslocamento

  observacao         text NOT NULL,

  criado_em          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_atividades_relatorio ON atividades (relatorio_id);
CREATE INDEX idx_atividades_tipo ON atividades (tipo_atividade);

-- ----------------------------------------------------------------------------
-- 3. EQUIPAMENTOS UTILIZADOS (filha de atividades — atividades "de obra")
-- ----------------------------------------------------------------------------
CREATE TABLE atividade_equipamentos (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  atividade_id       uuid NOT NULL REFERENCES atividades(id) ON DELETE CASCADE,
  equipamento        text NOT NULL,
  operador           text NOT NULL
);

CREATE INDEX idx_ativ_equip_atividade ON atividade_equipamentos (atividade_id);

-- ----------------------------------------------------------------------------
-- 4. MÁQUINAS UTILIZADAS (filha de atividades — Hora Máquina Trabalhada)
--    Cada máquina tem hora inicial/final próprias, independente das outras.
-- ----------------------------------------------------------------------------
CREATE TABLE atividade_maquinas (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  atividade_id       uuid NOT NULL REFERENCES atividades(id) ON DELETE CASCADE,
  equipamento        text NOT NULL,
  operador           text NOT NULL,
  hora_inicial       numeric NOT NULL,
  hora_final         numeric NOT NULL
);

CREATE INDEX idx_ativ_maq_atividade ON atividade_maquinas (atividade_id);

-- ----------------------------------------------------------------------------
-- 5. EVIDÊNCIAS FOTOGRÁFICAS (filha de atividades)
--    Fica vazia até criarmos o bucket no Supabase Storage e ligarmos o
--    upload — mesma ordem que seguimos no biomassa.
-- ----------------------------------------------------------------------------
CREATE TABLE evidencias_fotos (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  atividade_id       uuid NOT NULL REFERENCES atividades(id) ON DELETE CASCADE,
  storage_path       text NOT NULL,
  criado_em          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_evidencias_atividade ON evidencias_fotos (atividade_id);

-- ----------------------------------------------------------------------------
-- 6. CADASTROS (tabela genérica — alimenta os seletores do PWA e a tela de
--    administração do painel). Uma linha = uma opção de uma lista.
--    Categoria é texto livre controlado pela função salvar_cadastro(), não
--    enum — assim adicionar uma categoria nova (ex: um campo novo que só
--    vai existir daqui a 6 meses) não exige migração.
-- ----------------------------------------------------------------------------
CREATE TABLE cadastros (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  categoria          text NOT NULL,
  valor              text NOT NULL,
  ativo              boolean NOT NULL DEFAULT true,
  ordem              int NOT NULL DEFAULT 0,
  criado_em          timestamptz NOT NULL DEFAULT now(),
  atualizado_em      timestamptz NOT NULL DEFAULT now(),

  UNIQUE (categoria, valor)
);

COMMENT ON TABLE cadastros IS 'Catálogo genérico: cliente, contrato, tipo_estrada, equipe_frente, fazenda, encarregado, supervisor, tecnico_arauco, supervisor_arauco, trecho, tipo_atividade, tipo_hora_maquina, equipamento, operador.';

CREATE INDEX idx_cadastros_categoria ON cadastros (categoria, ordem);

CREATE TRIGGER cadastros_atualizado_em
  BEFORE UPDATE ON cadastros
  FOR EACH ROW EXECUTE FUNCTION trg_atualizar_timestamp();

-- ----------------------------------------------------------------------------
-- 7. Semente inicial dos cadastros — os mesmos valores que hoje estão fixos
--    no CATALOGO do index.html. Depois de rodar isso, o admin edita tudo
--    pela tela de Cadastros; o PWA para de usar valor fixo no código.
-- ----------------------------------------------------------------------------
INSERT INTO cadastros (categoria, valor, ordem) VALUES
  ('cliente', 'Colheita', 1),
  ('cliente', 'Transporte', 2),
  ('cliente', 'Silvicultura', 3),

  ('contrato', 'ARAUCO', 1),

  ('tipo_estrada', 'Acesso', 1),
  ('tipo_estrada', 'Estrada Interna da Fazenda', 2),
  ('tipo_estrada', 'Controle de Erosão', 3),
  ('tipo_estrada', 'Aceiro', 4),

  ('equipe_frente', 'GTM - Obra de Arte 02', 1),

  ('fazenda', 'Elo Dourado 2', 1),
  ('fazenda', 'Doce Moranga', 2),

  ('encarregado', 'Elson', 1),
  ('supervisor', 'Valmir', 1),
  ('tecnico_arauco', 'Edwilson', 1),
  ('supervisor_arauco', 'Luciano', 1),

  ('trecho', 'CAP-05', 1),
  ('trecho', '106', 2),

  ('tipo_atividade', 'Construção de Aterro', 1),
  ('tipo_atividade', 'Limpeza de Camada Vegetal', 2),
  ('tipo_atividade', 'Carregamento de Material', 3),
  ('tipo_atividade', 'Transporte de Material', 4),
  ('tipo_atividade', 'Hora Máquina Trabalhada', 5),

  ('tipo_hora_maquina', 'Carregamento', 1),
  ('tipo_hora_maquina', 'Transporte', 2),
  ('tipo_hora_maquina', 'Deslocamento', 3),

  ('equipamento', 'ESH-18', 1),
  ('equipamento', 'MN-16', 2),
  ('equipamento', 'PC-26-03', 3),
  ('equipamento', 'RC-09', 4),
  ('equipamento', 'CP-03', 5),
  ('equipamento', 'CB-20', 6),
  ('equipamento', 'CB-22', 7),

  ('operador', 'Leandro Félix', 1),
  ('operador', 'Leandro Recalde', 2),
  ('operador', 'Cherri dos Santos', 3),
  ('operador', 'Silvanei Costa', 4),
  ('operador', 'Antônio Cleonildo', 5),
  ('operador', 'Reginaldo da Silva', 6),
  ('operador', 'Gilberto Rodrigues', 7),
  ('operador', 'Elson', 8),
  ('operador', 'Valmir', 9),
  ('operador', 'Edwilson', 10),
  ('operador', 'Luciano', 11);
