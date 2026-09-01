-- ============================================================================
-- GTM RDO — RLS + funções de sincronização e leitura
-- ============================================================================
-- Rode isso DEPOIS do schema_rdo.sql.
--
-- O que este arquivo faz:
--   1. Tranca as 6 tabelas com RLS ligado e ZERO políticas — ninguém com a
--      chave pública (anon) ou já logado (authenticated) consegue fazer
--      SELECT/INSERT/UPDATE/DELETE direto nelas.
--   2. Cria as funções SECURITY DEFINER que passam por cima da trava:
--        - sincronizar_relatorio_rdo(payload)  → sem login (PWA de campo)
--        - listar_cadastros()                  → sem login (PWA de campo)
--        - salvar_cadastro(...)                → exige login (painel/admin)
--        - excluir_cadastro(id)                → exige login (painel/admin)
--        - listar_relatorios_painel(...)       → exige login (painel)
--   3. Libera EXECUTE só nessas funções, pros papéis certos.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Trava geral
-- ----------------------------------------------------------------------------
ALTER TABLE relatorios ENABLE ROW LEVEL SECURITY;
ALTER TABLE atividades ENABLE ROW LEVEL SECURITY;
ALTER TABLE atividade_equipamentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE atividade_maquinas ENABLE ROW LEVEL SECURITY;
ALTER TABLE evidencias_fotos ENABLE ROW LEVEL SECURITY;
ALTER TABLE cadastros ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON relatorios, atividades, atividade_equipamentos,
             atividade_maquinas, evidencias_fotos, cadastros
  FROM anon, authenticated;

-- ----------------------------------------------------------------------------
-- 2. sincronizar_relatorio_rdo — porta de entrada única do PWA de campo.
--    Recebe o relatório inteiro (com atividades aninhadas) em um único JSON,
--    upsert por uuid_dispositivo. Reenviar o mesmo relatório atualiza em vez
--    de duplicar. Sem exigir login — mesma lógica do sincronizar_visita do
--    biomassa.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION sincronizar_relatorio_rdo(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uuid_dispositivo uuid := (p_payload->>'uuid_dispositivo')::uuid;
  v_relatorio_id     uuid;
  v_ativ             jsonb;
  v_ativ_id          uuid;
  v_eq               jsonb;
  v_maq              jsonb;
  v_foto             jsonb;
  v_ordem            int := 0;
BEGIN
  IF v_uuid_dispositivo IS NULL THEN
    RAISE EXCEPTION 'uuid_dispositivo é obrigatório.';
  END IF;
  IF p_payload->>'cliente' IS NULL OR p_payload->>'data' IS NULL THEN
    RAISE EXCEPTION 'Relatório incompleto: cliente e data são obrigatórios.';
  END IF;

  INSERT INTO relatorios (
    uuid_dispositivo, empresa, cliente, contrato, faena, tipo_estrada,
    equipe_frente, fazenda, data_relatorio, encarregado, supervisor,
    tecnico_arauco, supervisor_arauco, gps_lat, gps_lng, gps_precisao,
    gps_capturado_em, criado_em, concluido_em
  ) VALUES (
    v_uuid_dispositivo,
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

  -- O PWA sempre manda o estado completo atual do relatório — mais simples
  -- e seguro apagar as atividades antigas e reinserir do zero do que tentar
  -- casar item a item.
  DELETE FROM atividades WHERE relatorio_id = v_relatorio_id;

  FOR v_ativ IN SELECT * FROM jsonb_array_elements(coalesce(p_payload->'atividades', '[]'::jsonb))
  LOOP
    INSERT INTO atividades (
      relatorio_id, ordem, tipo_atividade, comprimento_m, largura_m,
      profundidade_cm, dmt_km_inicial, dmt_km_final, trecho, tipo, observacao
    ) VALUES (
      v_relatorio_id, v_ordem, v_ativ->>'tipo_atividade',
      (v_ativ->>'comprimento_m')::numeric, (v_ativ->>'largura_m')::numeric,
      (v_ativ->>'profundidade_cm')::numeric, (v_ativ->>'dmt_km_inicial')::numeric,
      (v_ativ->>'dmt_km_final')::numeric, v_ativ->>'trecho', v_ativ->>'tipo',
      v_ativ->>'observacao'
    ) RETURNING id INTO v_ativ_id;

    FOR v_eq IN SELECT * FROM jsonb_array_elements(coalesce(v_ativ->'equipamentos', '[]'::jsonb))
    LOOP
      INSERT INTO atividade_equipamentos (atividade_id, equipamento, operador)
      VALUES (v_ativ_id, v_eq->>'equipamento', v_eq->>'operador');
    END LOOP;

    FOR v_maq IN SELECT * FROM jsonb_array_elements(coalesce(v_ativ->'maquinas', '[]'::jsonb))
    LOOP
      INSERT INTO atividade_maquinas (atividade_id, equipamento, operador, hora_inicial, hora_final)
      VALUES (
        v_ativ_id, v_maq->>'equipamento', v_maq->>'operador',
        (v_maq->>'hora_inicial')::numeric, (v_maq->>'hora_final')::numeric
      );
    END LOOP;

    FOR v_foto IN SELECT * FROM jsonb_array_elements(coalesce(v_ativ->'fotos', '[]'::jsonb))
    LOOP
      INSERT INTO evidencias_fotos (atividade_id, storage_path)
      VALUES (v_ativ_id, v_foto->>'storage_path');
    END LOOP;

    v_ordem := v_ordem + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'id', v_relatorio_id,
    'uuid_dispositivo', v_uuid_dispositivo,
    'sincronizado_em', now()
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. listar_cadastros — alimenta os seletores do PWA (substitui o CATALOGO
--    fixo no código) e também a tela de Cadastros do painel. Sem login.
--    Retorna {"cliente": ["Colheita", ...], "contrato": [...], ...}
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION listar_cadastros()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT coalesce(jsonb_object_agg(categoria, valores), '{}'::jsonb)
  FROM (
    SELECT categoria, jsonb_agg(valor ORDER BY ordem, valor) AS valores
    FROM cadastros
    WHERE ativo = true
    GROUP BY categoria
  ) agrupado;
$$;

-- ----------------------------------------------------------------------------
-- 4. salvar_cadastro / excluir_cadastro — CRUD da tela de Cadastros do
--    painel. Exigem sessão autenticada. Exclusão é lógica (ativo=false) pra
--    não quebrar o histórico de relatórios que já usaram aquele valor.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION salvar_cadastro(
  p_id        uuid DEFAULT NULL,
  p_categoria text DEFAULT NULL,
  p_valor     text DEFAULT NULL,
  p_ativo     boolean DEFAULT true,
  p_ordem     int DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sessão inválida — faça login para gerenciar cadastros.';
  END IF;
  IF p_categoria IS NULL OR trim(coalesce(p_valor, '')) = '' THEN
    RAISE EXCEPTION 'Categoria e valor são obrigatórios.';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO cadastros (categoria, valor, ativo, ordem)
    VALUES (p_categoria, trim(p_valor), coalesce(p_ativo, true), coalesce(p_ordem, 0))
    RETURNING id INTO v_id;
  ELSE
    UPDATE cadastros
    SET categoria = p_categoria,
        valor     = trim(p_valor),
        ativo     = coalesce(p_ativo, true),
        ordem     = coalesce(p_ordem, 0)
    WHERE id = p_id
    RETURNING id INTO v_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Cadastro não encontrado.';
    END IF;
  END IF;

  RETURN jsonb_build_object('id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION excluir_cadastro(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sessão inválida — faça login para gerenciar cadastros.';
  END IF;

  UPDATE cadastros SET ativo = false WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cadastro não encontrado.';
  END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. listar_relatorios_painel — leitura exclusiva do painel. Reaproveita a
--    mesma reconstrução de dados que o sync grava, só que pra leitura, com
--    filtros simples. Exige sessão autenticada.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION listar_relatorios_painel(
  p_data_inicio date DEFAULT NULL,
  p_data_fim    date DEFAULT NULL,
  p_cliente     text DEFAULT NULL,
  p_fazenda     text DEFAULT NULL,
  p_limite      int  DEFAULT 200
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_resultado jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sessão inválida — faça login para acessar o painel.';
  END IF;

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
          'tipo_atividade', a.tipo_atividade,
          'comprimento_m', a.comprimento_m,
          'largura_m', a.largura_m,
          'profundidade_cm', a.profundidade_cm,
          'dmt_km_inicial', a.dmt_km_inicial,
          'dmt_km_final', a.dmt_km_final,
          'trecho', a.trecho,
          'tipo', a.tipo,
          'observacao', a.observacao,
          'equipamentos', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('equipamento', e.equipamento, 'operador', e.operador)), '[]'::jsonb)
            FROM atividade_equipamentos e WHERE e.atividade_id = a.id
          ),
          'maquinas', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('equipamento', m.equipamento, 'operador', m.operador, 'hora_inicial', m.hora_inicial, 'hora_final', m.hora_final)), '[]'::jsonb)
            FROM atividade_maquinas m WHERE m.atividade_id = a.id
          ),
          'fotos', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('storage_path', f.storage_path)), '[]'::jsonb)
            FROM evidencias_fotos f WHERE f.atividade_id = a.id
          )
        ) ORDER BY a.ordem), '[]'::jsonb)
        FROM atividades a WHERE a.relatorio_id = rel.id
      )
    ) AS r,
    rel.data_relatorio AS data_ordenacao
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
$$;

-- ----------------------------------------------------------------------------
-- 6. Permissões — só EXECUTE nas funções, nada direto nas tabelas
-- ----------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION sincronizar_relatorio_rdo(jsonb) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION listar_cadastros() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION salvar_cadastro(uuid, text, text, boolean, int) TO authenticated;
GRANT EXECUTE ON FUNCTION excluir_cadastro(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION listar_relatorios_painel(date, date, text, text, int) TO authenticated;
