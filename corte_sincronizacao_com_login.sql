-- ============================================================================
-- GTM RDO — PONTO DE CORTE: sincronização passa a exigir login
-- ============================================================================
-- ATENÇÃO: este é o único arquivo desta leva que MUDA O COMPORTAMENTO DO QUE
-- ESTÁ EM CAMPO. Os outros três (revisao_schema_identidade_estavel,
-- revisao_rpcs, travar_permissoes_rpc_estado_atual) são invisíveis pro PWA
-- publicado. Este não é.
--
-- Depois de rodar isto, sincronizar_relatorio_rdo exige auth.uid(). O PWA que
-- está publicado hoje sincroniza ANONIMAMENTE -- o login por Supabase Auth
-- só existe em commit local, ainda não publicado. Rodar antes de publicar =
-- o operador termina o RDO, aperta sincronizar, e recebe erro, com o dia de
-- trabalho preso no aparelho.
--
-- ORDEM CERTA:
--   1. publicar o PWA com login (o commit que está parado no repositório)
--   2. bump do CACHE_NAME no sw.js, senão o navegador serve a versão velha
--   3. confirmar num aparelho de campo que o login funciona e sincroniza
--   4. SÓ ENTÃO rodar este arquivo
--   5. e o bloco 4 do travar_permissoes_rpc_estado_atual.sql, que é o par
--      deste aqui (a trava na permissão, enquanto esta é a trava no corpo)
--
-- Rodar isto e a publicação do PWA precisam acontecer perto um do outro. A
-- janela entre os dois é o período em que o campo fica sem sincronizar.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- sincronizar_relatorio_rdo — duas mudanças de fundo em relação ao banco
-- ----------------------------------------------------------------------------
-- 1. Exige login e grava criado_por. Fecha a brecha de gravar relatório com
--    a chave anon (que é pública e está no index.html), e é o que permite
--    saber pra quem notificar quando o painel devolve uma atividade.
--
-- 2. Para de apagar-e-recriar as atividades. A versão que está no banco faz
--    DELETE FROM atividades WHERE relatorio_id = ... e insere tudo de novo,
--    o que gera ids novos a cada sincronização. Com o fluxo de revisão isso
--    apagaria o status: a atividade devolvida deixaria de existir e nasceria
--    outra, sem histórico. Agora é upsert por
--    (relatorio_id, uuid_atividade_dispositivo).
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
    -- criado_por fica de fora de propósito: um reenvio não muda o dono
    -- original do relatório.
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
    -- O PWA manda o id que ele usa no IndexedDB. Se vier vazio (payload de
    -- versão antiga do app), gera um -- assim a atividade entra sem quebrar,
    -- só não vai casar com um reenvio posterior.
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
      -- Duas situações devolvem a atividade pra fila de revisão:
      --
      -- 1. Estava DEVOLVIDA e voltou -- é a correção chegando. Limpa o motivo
      --    antigo junto, senão o PWA continua mostrando o alerta de algo que
      --    já foi corrigido.
      --
      -- 2. Estava VALIDADA e algum dado do apontamento mudou. Sem isso, dava
      --    pra reabrir o relatório no PWA (index.html:1480), alterar uma
      --    medida já aprovada, reenviar, e o painel seguir mostrando
      --    "Validado" com número diferente do que o revisor viu. Se esse
      --    número vira medição faturável, é furo de controle.
      --
      -- Reenvio que não muda nada continua validado -- ROW(...) IS DISTINCT
      -- FROM ROW(...) compara campo a campo tratando NULL direito, então
      -- sincronizar duas vezes o mesmo relatório não gera falso alarme.
      --
      -- `ordem` fica de fora da comparação de propósito: é a posição da
      -- atividade na lista, não um dado do apontamento. Reordenar não
      -- invalida a aprovação de nada.
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
      motivo_devolucao = CASE WHEN atividades.status_revisao = 'devolvido' THEN NULL     ELSE atividades.motivo_devolucao END
    RETURNING id INTO v_ativ_id;

    -- As filhas não têm estado de revisão próprio, então recriar é simples e
    -- correto -- o aparelho é a fonte da verdade pra elas.
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

  -- Atividade apagada no aparelho some daqui também. O DELETE é restrito a
  -- ESTE relatório e ao que não veio no payload -- nunca varre a tabela.
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

-- A trava por fora, par da verificação de auth.uid() por dentro.
--
-- O `, anon` é obrigatório e não é redundância: neste banco o Supabase concede
-- EXECUTE a anon EXPLICITAMENTE (via ALTER DEFAULT PRIVILEGES no schema
-- public), então revogar só de PUBLIC deixaria a função aberta pra chave anon
-- e o script ainda diria "Success". Descoberto ao aplicar o revisao_rpcs.sql
-- em 08/09 -- ver BOAS_PRATICAS.md §2.
--
-- Aqui a trava de fora importa menos que nas outras funções, porque o corpo já
-- barra com auth.uid() IS NULL. Mas é ela que faz o PostgREST recusar antes de
-- executar, e é ela que a bateria mede.
REVOKE ALL ON FUNCTION sincronizar_relatorio_rdo(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION sincronizar_relatorio_rdo(jsonb) TO authenticated;

-- ============================================================================
-- CONFERÊNCIA -- esperado: anon_pode = false, auth_pode = true
-- ============================================================================
SELECT p.proname,
       has_function_privilege('anon', p.oid, 'EXECUTE')          AS anon_pode,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_pode
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'sincronizar_relatorio_rdo';

-- ============================================================================
-- NOTA -- o furo do "validado que muda sozinho", e o que sobrou dele
-- ============================================================================
-- O buraco era: atividade já VALIDADA reenviada pelo aparelho ficava com os
-- números novos e o carimbo de aprovação antigo. E o caminho existe mesmo --
-- o PWA deixa reabrir relatório concluído (index.html:1480, :1705-1715).
-- Corrigido no CASE do status_revisao acima: mudou dado, volta pra
-- 'pendente' e o revisor vê de novo.
--
-- O que NÃO mudei, pra você saber que foi escolha e não esquecimento:
--
-- 1. `revisado_por` e `revisado_em` continuam com a marca da última revisão,
--    mesmo quando o status volta pra 'pendente'. Não há tabela de histórico
--    neste projeto; apagar seria perder a única pista de quem olhou aquilo
--    por último. Se um dia quiser histórico de verdade, isso vira tabela
--    própria, não mais colunas aqui.
--
-- 2. Ninguém é NOTIFICADO quando uma validada volta pra pendente. O painel
--    mostra o badge mudado quando alguém abrir o relatório, e só. Se isso
--    precisa gerar aviso ativo pro revisor, é funcionalidade nova -- me diga
--    que a gente desenha.
