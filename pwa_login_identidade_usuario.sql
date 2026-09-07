-- ============================================================================
-- GTM RDO — login no PWA (usuário/senha, sem 2FA) + identidade por usuário
-- ============================================================================
-- Muda a base de "quem fez esse apontamento" de aparelho (dispositivo_fisico,
-- um workaround) para usuário logado de verdade (auth.uid()) -- mais
-- correto (a mesma pessoa pode trocar de aparelho; um aparelho pode ser
-- usado por pessoas diferentes) e fecha uma brecha real: hoje qualquer um
-- com a chave pública consegue gravar relatório falso, porque a
-- sincronização é anônima. A partir daqui, só usuário autenticado sincroniza.
-- ============================================================================

ALTER TABLE relatorios ADD COLUMN IF NOT EXISTS criado_por uuid REFERENCES auth.users(id);
CREATE INDEX IF NOT EXISTS idx_relatorios_criado_por ON relatorios(criado_por);

-- push_subscriptions: troca a base de dispositivo_fisico pra usuario_id
ALTER TABLE push_subscriptions RENAME COLUMN dispositivo_fisico TO usuario_id;
ALTER TABLE push_subscriptions DROP CONSTRAINT IF EXISTS push_subscriptions_uuid_dispositivo_endpoint_key;
ALTER TABLE push_subscriptions ADD CONSTRAINT push_subscriptions_usuario_endpoint_key UNIQUE (usuario_id, endpoint);
COMMENT ON COLUMN push_subscriptions.usuario_id IS 'auth.uid() de quem logou no PWA -- não mais um id de aparelho. Permite notificar a pessoa certa em qualquer aparelho que ela usar.';

-- ----------------------------------------------------------------------------
-- sincronizar_relatorio_rdo — agora exige authenticated (não mais anon).
-- Grava quem criou (só na primeira vez -- um reenvio não muda o dono).
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
    -- criado_por NÃO muda num reenvio -- preserva o dono original
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
      status_revisao   = CASE WHEN atividades.status_revisao = 'devolvido' THEN 'pendente' ELSE atividades.status_revisao END,
      motivo_devolucao = CASE WHEN atividades.status_revisao = 'devolvido' THEN NULL ELSE atividades.motivo_devolucao END
    RETURNING id INTO v_ativ_id;

    DELETE FROM atividade_equipamentos WHERE atividade_id = v_ativ_id;
    DELETE FROM atividade_maquinas WHERE atividade_id = v_ativ_id;
    DELETE FROM evidencias_fotos WHERE atividade_id = v_ativ_id;

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

  DELETE FROM atividades
  WHERE relatorio_id = v_relatorio_id
  AND NOT (uuid_atividade_dispositivo = ANY(v_ids_recebidos));

  RETURN jsonb_build_object(
    'id', v_relatorio_id,
    'uuid_dispositivo', v_uuid_dispositivo,
    'sincronizado_em', now()
  );
END;
$$;
REVOKE ALL ON FUNCTION sincronizar_relatorio_rdo(jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION sincronizar_relatorio_rdo(jsonb) TO authenticated;

-- ----------------------------------------------------------------------------
-- verificar_atividades_devolvidas / salvar_push_subscription — não recebem
-- mais um id como parâmetro, usam auth.uid() internamente. Isso também
-- fecha uma brecha: antes, qualquer um podia mandar um id de aparelho
-- qualquer e ver devolvidas de outro aparelho -- agora só vê as suas.
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS verificar_atividades_devolvidas(uuid);
CREATE FUNCTION verificar_atividades_devolvidas()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'relatorio_uuid_dispositivo', r.uuid_dispositivo,
    'fazenda', r.fazenda,
    'data_relatorio', r.data_relatorio,
    'atividade_id', a.uuid_atividade_dispositivo,
    'tipo_atividade', a.tipo_atividade,
    'motivo_devolucao', a.motivo_devolucao,
    'revisado_em', a.revisado_em
  ) ORDER BY a.revisado_em DESC), '[]'::jsonb)
  FROM atividades a
  JOIN relatorios r ON r.id = a.relatorio_id
  WHERE r.criado_por = auth.uid()
    AND a.status_revisao = 'devolvido';
$$;
GRANT EXECUTE ON FUNCTION verificar_atividades_devolvidas() TO authenticated;

DROP FUNCTION IF EXISTS salvar_push_subscription(uuid, text, text, text);
CREATE FUNCTION salvar_push_subscription(p_endpoint text, p_p256dh text, p_auth text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'É preciso estar logado.';
  END IF;
  IF p_endpoint IS NULL THEN
    RAISE EXCEPTION 'Dados de inscrição incompletos.';
  END IF;
  INSERT INTO push_subscriptions (usuario_id, endpoint, p256dh, auth)
  VALUES (auth.uid(), p_endpoint, p_p256dh, p_auth)
  ON CONFLICT (usuario_id, endpoint) DO UPDATE SET
    p256dh = EXCLUDED.p256dh, auth = EXCLUDED.auth;
END;
$$;
GRANT EXECUTE ON FUNCTION salvar_push_subscription(text, text, text) TO authenticated;

-- devolver_atividade_rdo: devolve usuario_id (criado_por do relatório) em
-- vez de dispositivo_fisico
CREATE OR REPLACE FUNCTION devolver_atividade_rdo(p_atividade_id uuid, p_motivo text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_relatorio_id uuid;
  v_usuario_id   uuid;
BEGIN
  PERFORM exige_mfa();
  IF trim(coalesce(p_motivo, '')) = '' THEN
    RAISE EXCEPTION 'Descreva o motivo da devolução.';
  END IF;

  UPDATE atividades
  SET status_revisao = 'devolvido', motivo_devolucao = trim(p_motivo),
      revisado_por = auth.uid(), revisado_em = now()
  WHERE id = p_atividade_id
  RETURNING relatorio_id INTO v_relatorio_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Atividade não encontrada.';
  END IF;

  SELECT criado_por INTO v_usuario_id FROM relatorios WHERE id = v_relatorio_id;

  RETURN jsonb_build_object('usuario_id', v_usuario_id);
END;
$$;
GRANT EXECUTE ON FUNCTION devolver_atividade_rdo(uuid, text) TO authenticated;
