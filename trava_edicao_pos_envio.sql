-- ============================================================================
-- GTM RDO — enviou, acabou: só a devolução reabre o apontamento
-- ============================================================================
-- Arquivo 8 da leva. Regra definida pelo Fábio em 2026-09-08:
--
--   "um apontamento que está no PWA não pode ser apagado, pois quebraria o
--    fluxo, e também só pode ser reaberto se o usuário do painel devolver."
--
-- Fecha o ciclo que começou com a alternância na devolução: cada lado age na
-- sua vez, e o RDO sincronizado fica "com o painel" até ser devolvido.
--
-- O QUE MUDA NA PRÁTICA
--
--   atividade nova            -> entra normalmente (INSERT)
--   atividade 'devolvido'     -> pode ser editada E removida (é a correção)
--   atividade 'pendente'      -> CONGELADA: reenvio não altera nada
--   atividade 'validado'      -> CONGELADA: reenvio não altera nada
--
-- POR QUE O SERVIDOR IGNORA EM VEZ DE RECUSAR A SINCRONIZAÇÃO INTEIRA
--
-- O PWA é offline-first. O aparelho pode passar horas sem sinal e não ter ideia
-- de que o painel validou algo nesse meio-tempo. Se a sincronização inteira
-- falhasse por causa de uma atividade congelada, o RDO do dia -- inclusive os
-- apontamentos novos e legítimos -- ficaria preso no aparelho. Isso é
-- exatamente o desastre que a §1.1 do CLAUDE.md existe para evitar.
--
-- Então o servidor grava o que pode, mantém intocado o que está congelado, e
-- DEVOLVE a contagem do que ignorou. O PWA usa esse número para avisar o
-- operador, em vez de deixá-lo achar que a edição foi salva.
--
-- ISTO É A TRAVA DE VERDADE. O bloqueio na tela do PWA (botões escondidos) é
-- conveniência: um aparelho com versão antiga do app continua mandando payload
-- completo, e é aqui que ele é barrado.
--
-- SOBRE A EXCLUSÃO
--
-- Antes deste arquivo, remover um apontamento no aparelho marcava excluido_em
-- em qualquer estado. Agora só vale para 'devolvido' -- que é o caso legítimo:
-- o revisor devolveu dizendo "este apontamento não deveria existir", e remover
-- é atender ao pedido. Nos outros estados a remoção é ignorada e a atividade
-- continua viva no banco.
-- ============================================================================

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
  v_status_atual     text;
  v_eq               jsonb;
  v_maq              jsonb;
  v_foto             jsonb;
  v_ordem            int := 0;
  v_ids_recebidos    uuid[] := '{}';
  v_congeladas       int := 0;   -- alterações ignoradas por estarem travadas
  v_remocoes_negadas int := 0;   -- remoções ignoradas pelo mesmo motivo
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

    -- Estado atual antes de decidir. FOR UPDATE porque entre ler e escrever o
    -- painel poderia validar a mesma atividade.
    SELECT id, status_revisao INTO v_ativ_id, v_status_atual
      FROM atividades
     WHERE relatorio_id = v_relatorio_id
       AND uuid_atividade_dispositivo = v_uuid_ativ_disp
     FOR UPDATE;

    IF v_ativ_id IS NULL THEN
      -- Apontamento novo: entra normalmente.
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
      ) RETURNING id INTO v_ativ_id;

    ELSIF v_status_atual = 'devolvido' THEN
      -- A correção que o painel pediu. Volta pra fila e limpa o motivo, senão
      -- o PWA continua alertando sobre algo já corrigido.
      UPDATE atividades SET
        ordem            = v_ordem,
        tipo_atividade   = v_ativ->>'tipo_atividade',
        up               = v_ativ->>'up',
        comprimento_m    = (v_ativ->>'comprimento_m')::numeric,
        largura_m        = (v_ativ->>'largura_m')::numeric,
        profundidade_cm  = (v_ativ->>'profundidade_cm')::numeric,
        dmt_km_inicial   = (v_ativ->>'dmt_km_inicial')::numeric,
        dmt_km_final     = (v_ativ->>'dmt_km_final')::numeric,
        trecho           = v_ativ->>'trecho',
        tipo             = v_ativ->>'tipo',
        observacao       = v_ativ->>'observacao',
        data_execucao    = (v_ativ->>'data_execucao')::date,
        status_revisao   = 'pendente',
        motivo_devolucao = NULL,
        excluido_em      = NULL,
        excluido_por     = NULL
      WHERE id = v_ativ_id;

    ELSE
      -- CONGELADA ('pendente' ou 'validado'): nada é alterado.
      --
      -- Não levanta exceção de propósito -- ver o cabeçalho. O `ordem` também
      -- não é atualizado: mexer nele seria aceitar metade da edição, e a
      -- posição na lista não vale o precedente.
      v_congeladas := v_congeladas + 1;
      v_ordem := v_ordem + 1;
      CONTINUE;   -- pula as filhas: elas fazem parte do apontamento congelado
    END IF;

    -- Só chega aqui atividade nova ou devolvida. As filhas são recriadas a
    -- partir do aparelho, que é a fonte da verdade para elas.
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

  -- Sumiu do payload = o operador removeu no aparelho.
  --
  -- Só vale para 'devolvido': é o caso em que o revisor pediu justamente para
  -- o apontamento sair. Nos outros estados a remoção é ignorada e a atividade
  -- continua viva -- "enviou, acabou" também vale para apagar.
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

  -- congeladas/remocoes_negadas são o que o PWA usa para avisar o operador de
  -- que aquela alteração não valeu. Sem isso ele acha que salvou.
  RETURN jsonb_build_object(
    'id', v_relatorio_id,
    'uuid_dispositivo', v_uuid_dispositivo,
    'sincronizado_em', now(),
    'congeladas', v_congeladas,
    'remocoes_negadas', v_remocoes_negadas
  );
END;
$$;
REVOKE ALL ON FUNCTION sincronizar_relatorio_rdo(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION sincronizar_relatorio_rdo(jsonb) TO authenticated;
