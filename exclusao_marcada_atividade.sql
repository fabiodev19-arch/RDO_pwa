-- ============================================================================
-- GTM RDO — exclusão de apontamento passa a ser MARCADA, não apagada
-- ============================================================================
-- Arquivo 5 da leva. Rodar DEPOIS do corte_sincronizacao_com_login.sql.
--
-- O PROBLEMA (demonstrado no banco em 2026-09-08, pergunta do Fábio):
--
-- O PWA deixa remover um apontamento (index.html:1690) e o botão não olha o
-- status de revisão. Na sincronização seguinte, o DELETE do fim da
-- sincronizar_relatorio_rdo apagava tudo o que não veio no payload. Efeito
-- medido, com uma atividade devolvida e outra validada:
--
--   antes  -> 2 atividades, 1 devolvida visível pro PWA, motivo gravado
--   depois -> 0 atividades, 0 devolvidas, NENHUM rastro da devolução
--
-- Ou seja: dava pra "resolver" uma devolução apagando o apontamento em vez de
-- corrigi-lo, e dava pra sumir com medição já aprovada pelo revisor. É o mesmo
-- furo do "validado que muda sozinho", só que por exclusão em vez de edição --
-- e este some com a linha inteira, então nem dá pra perceber depois.
--
-- A CORREÇÃO (decisão do Fábio, 08/09): nada some. A atividade removida no
-- aparelho é MARCADA como excluída e continua no banco; o painel mostra que o
-- operador a removeu, e quem decide o que fazer é o revisor.
--
-- Consequência boa de brinde: as filhas (equipamentos, máquinas e as FOTOS de
-- evidência) também continuam, porque só eram apagadas junto com a atividade.
-- Foto de evidência sumindo porque alguém apertou "Remover" seria perda de
-- dado sem volta -- o Storage não tem histórico aqui.
--
-- Tudo aditivo: ADD COLUMN + CREATE OR REPLACE. Nada é removido.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. As colunas da marcação
-- ----------------------------------------------------------------------------
ALTER TABLE atividades
  ADD COLUMN IF NOT EXISTS excluido_em  timestamptz,
  ADD COLUMN IF NOT EXISTS excluido_por uuid REFERENCES auth.users(id);

COMMENT ON COLUMN atividades.excluido_em IS
  'Quando o operador removeu este apontamento no aparelho. NULL = ativo. A linha NUNCA é apagada -- se estava devolvida ou validada, o painel precisa saber que sumiu do lado do campo.';
COMMENT ON COLUMN atividades.excluido_por IS
  'auth.uid() de quem sincronizou a remoção. É o operador, não o revisor.';

-- A consulta que o painel faz é "as atividades vivas deste relatório", então o
-- índice parcial cobre o caminho quente sem crescer com o histórico.
CREATE INDEX IF NOT EXISTS idx_atividades_vivas
  ON atividades (relatorio_id)
  WHERE excluido_em IS NULL;

-- ----------------------------------------------------------------------------
-- 2. sincronizar_relatorio_rdo — marcar em vez de apagar
-- ----------------------------------------------------------------------------
-- Só duas mudanças em relação ao corte_sincronizacao_com_login.sql:
--   a) o DELETE do fim virou UPDATE que marca;
--   b) o upsert limpa a marca quando a atividade volta (o operador removeu,
--      se arrependeu e recriou -- ou o aparelho reenviou um estado anterior).
-- O resto é idêntico, inclusive o CASE do status_revisao.
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
  v_uuid_ativ_disp   uuid;
  v_eq               jsonb;
  v_maq              jsonb;
  v_foto             jsonb;
  v_ordem            int := 0;
  v_ids_recebidos    uuid[] := '{}';
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

    INSERT INTO atividades (
      relatorio_id, ordem, uuid_atividade_dispositivo, tipo_atividade, up,
      comprimento_m, largura_m, profundidade_cm, dmt_km_inicial, dmt_km_final,
      trecho, tipo, observacao, data_execucao, status_revisao
    ) VALUES (
      v_relatorio_id, v_ordem, v_uuid_ativ_disp, v_ativ->>'tipo_atividade', v_ativ->>'up',
      (v_ativ->>'comprimento_m')::numeric, (v_ativ->>'largura_m')::numeric,
      (v_ativ->>'profundidade_cm')::numeric, (v_ativ->>'dmt_km_inicial')::numeric,
      (v_ativ->>'dmt_km_final')::numeric, v_ativ->>'trecho', v_ativ->>'tipo',
      v_ativ->>'observacao', (v_ativ->>'data_execucao')::date,
      'pendente'
    )
    ON CONFLICT (relatorio_id, uuid_atividade_dispositivo) DO UPDATE SET
      ordem            = EXCLUDED.ordem,
      tipo_atividade   = EXCLUDED.tipo_atividade,
      up               = EXCLUDED.up,
      comprimento_m    = EXCLUDED.comprimento_m,
      largura_m        = EXCLUDED.largura_m,
      profundidade_cm  = EXCLUDED.profundidade_cm,
      dmt_km_inicial   = EXCLUDED.dmt_km_inicial,
      dmt_km_final     = EXCLUDED.dmt_km_final,
      trecho           = EXCLUDED.trecho,
      tipo             = EXCLUDED.tipo,
      observacao       = EXCLUDED.observacao,
      data_execucao    = EXCLUDED.data_execucao,
      -- A atividade voltou no payload, então está viva de novo. Se tinha sido
      -- removida antes, a marca sai -- senão ela ficaria "excluída" pra sempre
      -- no painel, mesmo estando de volta na tela do operador.
      excluido_em      = NULL,
      excluido_por     = NULL,
      status_revisao   = CASE
                           WHEN atividades.status_revisao = 'devolvido' THEN 'pendente'
                           WHEN atividades.status_revisao = 'validado'
                            AND ROW(atividades.tipo_atividade, atividades.up,
                                    atividades.comprimento_m, atividades.largura_m,
                                    atividades.profundidade_cm, atividades.dmt_km_inicial,
                                    atividades.dmt_km_final, atividades.trecho,
                                    atividades.tipo, atividades.observacao,
                                    atividades.data_execucao)
                                IS DISTINCT FROM
                                ROW(EXCLUDED.tipo_atividade, EXCLUDED.up,
                                    EXCLUDED.comprimento_m, EXCLUDED.largura_m,
                                    EXCLUDED.profundidade_cm, EXCLUDED.dmt_km_inicial,
                                    EXCLUDED.dmt_km_final, EXCLUDED.trecho,
                                    EXCLUDED.tipo, EXCLUDED.observacao,
                                    EXCLUDED.data_execucao)
                             THEN 'pendente'
                           ELSE atividades.status_revisao
                         END,
      motivo_devolucao = CASE WHEN atividades.status_revisao = 'devolvido' THEN NULL ELSE atividades.motivo_devolucao END
    RETURNING id INTO v_ativ_id;

    -- As filhas não têm estado de revisão próprio, então recriar é simples e
    -- correto -- o aparelho é a fonte da verdade pra elas. Isso vale só pras
    -- atividades que VIERAM no payload; as marcadas como excluídas não passam
    -- por aqui, então as fotos delas ficam intactas.
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
      VALUES (
        v_ativ_id, v_maq->>'equipamento', v_maq->>'operador',
        coalesce(v_maq->'dados', '{}'::jsonb)
      );
    END LOOP;

    FOR v_foto IN SELECT * FROM jsonb_array_elements(coalesce(v_ativ->'fotos', '[]'::jsonb))
    LOOP
      INSERT INTO evidencias_fotos (atividade_id, storage_path)
      VALUES (v_ativ_id, v_foto->>'storage_path');
    END LOOP;

    v_ordem := v_ordem + 1;
  END LOOP;

  -- AQUI ESTÁ A MUDANÇA: era DELETE, virou marcação.
  --
  -- `excluido_em IS NULL` no WHERE não é detalhe: sem ele, toda sincronização
  -- posterior reescreveria a data de exclusão, e o painel passaria a mostrar
  -- "removido agora" para algo removido semana passada.
  UPDATE atividades
     SET excluido_em  = now(),
         excluido_por = auth.uid()
   WHERE relatorio_id = v_relatorio_id
     AND NOT (uuid_atividade_dispositivo = ANY(v_ids_recebidos))
     AND excluido_em IS NULL;

  RETURN jsonb_build_object(
    'id', v_relatorio_id,
    'uuid_dispositivo', v_uuid_dispositivo,
    'sincronizado_em', now()
  );
END;
$$;
REVOKE ALL ON FUNCTION sincronizar_relatorio_rdo(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION sincronizar_relatorio_rdo(jsonb) TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. verificar_atividades_devolvidas — não cobrar correção do que foi removido
-- ----------------------------------------------------------------------------
-- Se o operador removeu o apontamento, mostrar "corrija esta atividade" no
-- banner do PWA seria pedir correção de algo que não está mais na tela dele --
-- um alerta que ele não tem como resolver. Quem precisa saber da remoção é o
-- revisor, no painel, não o operador.
CREATE OR REPLACE FUNCTION verificar_atividades_devolvidas()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'relatorio_uuid_dispositivo', r.uuid_dispositivo,
    'fazenda',                    r.fazenda,
    'data_relatorio',             r.data_relatorio,
    'atividade_id',               a.uuid_atividade_dispositivo,
    'tipo_atividade',             a.tipo_atividade,
    'motivo_devolucao',           a.motivo_devolucao,
    'revisado_em',                a.revisado_em
  ) ORDER BY a.revisado_em DESC), '[]'::jsonb)
  FROM atividades a
  JOIN relatorios r ON r.id = a.relatorio_id
  WHERE r.criado_por = auth.uid()
    AND a.status_revisao = 'devolvido'
    AND a.excluido_em IS NULL;
$$;
REVOKE ALL ON FUNCTION verificar_atividades_devolvidas() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION verificar_atividades_devolvidas() TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. listar_relatorios_painel — entrega a marca pro painel decidir
-- ----------------------------------------------------------------------------
-- As excluídas CONTINUAM na lista, de propósito: o objetivo da mudança inteira
-- é o revisor enxergar que o operador removeu um apontamento que ele já tinha
-- devolvido ou aprovado. Filtrar aqui seria reproduzir o sumiço, só que na
-- consulta em vez de no DELETE.
--
-- Vão dois campos novos: excluido_em e status_anterior_exclusao -- este último
-- é o que responde "e o que era essa atividade antes de sumir?", que é a
-- pergunta que o revisor faz ao ver a marca.
CREATE OR REPLACE FUNCTION listar_relatorios_painel(
  p_data_inicio date    DEFAULT NULL,
  p_data_fim    date    DEFAULT NULL,
  p_cliente     text    DEFAULT NULL,
  p_fazenda     text    DEFAULT NULL,
  p_limite      integer DEFAULT 200
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
          'tipo_atividade', a.tipo_atividade,
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
          -- Só faz sentido quando a atividade foi removida; nas vivas fica
          -- null pro painel não ter que adivinhar.
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
        -- As removidas vão pro fim da lista: o que o revisor precisa ver
        -- primeiro é o apontamento vivo.
        ) ORDER BY (a.excluido_em IS NOT NULL), a.ordem), '[]'::jsonb)
        FROM atividades a WHERE a.relatorio_id = rel.id
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
$$;
REVOKE ALL ON FUNCTION listar_relatorios_painel(date, date, text, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION listar_relatorios_painel(date, date, text, text, integer) TO authenticated;

-- ============================================================================
-- O QUE NÃO FOI FEITO, e por quê -- pra ficar claro que foi escolha
-- ============================================================================
-- 1. O botão "Remover atividade" do PWA continua existindo para qualquer
--    status. Bloquear no aparelho é melhoria de experiência, não proteção
--    (cliente mente), e esconder o botão de uma atividade devolvida tiraria um
--    caminho legítimo: às vezes a devolução é justamente "esse apontamento não
--    deveria estar aqui". Agora, apagar deixa rastro -- que era o furo real.
--
-- 2. Não existe "desfazer exclusão" pelo painel. Se o revisor quiser a
--    atividade de volta, hoje o caminho é o operador recriá-la no aparelho
--    (o upsert limpa a marca sozinho). Botão de restaurar no painel é
--    funcionalidade nova -- se precisar, a gente desenha.
--
-- 3. `validar_atividade_rdo` e `devolver_atividade_rdo` NÃO recusam atividade
--    excluída. O revisor pode querer registrar a devolução de algo que o
--    operador removeu -- e barrar isso criaria um estado sem saída, onde
--    ninguém consegue mais tocar na linha. O painel mostra a marca; a decisão
--    é de quem está lendo.
-- ============================================================================
