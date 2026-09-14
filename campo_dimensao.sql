-- ===========================================================================
-- Campo "Dimensão (m)" no formulário Padrão (obra)  --  2026-09-10
-- ===========================================================================
--
-- De onde veio: NÃO está na planilha da Arauco. As 442 strings da aba
-- APONTAMENTO não têm o termo, e as colunas de medida de lá são COMPRIMENTO,
-- LARGURA e ESPESSURA. O campo veio dos apontamentos que chegam por WhatsApp,
-- onde ele já é preenchido na mão. Pedido do Fábio: "vamos colocar esse campo
-- porque provavelmente vamos precisar para alguma finalidade".
--
-- Por isso ele nasce como REGISTRO, não como insumo de cálculo:
-- `producao_consolidada` NÃO é tocada aqui. O dia em que a finalidade for
-- decidida, muda-se a fórmula -- e aí a bateria acusa, porque os dois ramos
-- dela já têm teste.
--
-- Tudo aditivo (CLAUDE.md §1.1): uma coluna nova e dois CREATE OR REPLACE.
-- Nenhum DROP, nenhum DELETE, nenhuma coluna alterada.
--
-- ATENÇÃO ao que já mordeu este projeto uma vez: a coluna é NULLABLE e sem
-- DEFAULT. Foi um NOT NULL numa coluna que o caminho de escrita vigente não
-- preenchia (`uuid_atividade_dispositivo`, arquivo 1) que derrubou a
-- sincronização de quem estava em campo. "Aditivo" no papel não é o mesmo que
-- inofensivo.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. A coluna
-- ---------------------------------------------------------------------------
ALTER TABLE atividades ADD COLUMN IF NOT EXISTS dimensao_m numeric;

COMMENT ON COLUMN atividades.dimensao_m IS
  'Dimensão em metros, formulário Padrão (obra). Veio dos apontamentos de '
  'WhatsApp, não da planilha da Arauco. Por ora é registro: nenhuma fórmula '
  'de produção usa este valor (10/09/2026).';

-- ---------------------------------------------------------------------------
-- 2. A sincronização passa a gravar o campo
-- ---------------------------------------------------------------------------
-- Idêntica à que está no banco, com `dimensao_m` no INSERT e no UPDATE do
-- ramo "devolvido". Os outros ramos seguem intocados: apontamento congelado
-- continua congelado, e é isso que a trava de edição garante.
--
-- A ACL NÃO é tocada aqui de propósito -- CREATE OR REPLACE preserva a que
-- existe. Esta função ainda tem GRANT para `anon` (resto do bloco 5 do
-- `travar_permissoes_rpc_estado_atual.sql`, que nunca foi descomentado).
-- Revogar é decisão à parte, não efeito colateral de acrescentar um campo.
-- Na prática `anon` não consegue nada: a primeira linha do corpo exige
-- auth.uid().
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
        descricao_atividade, up, dimensao_m,
        comprimento_m, largura_m, profundidade_cm, dmt_km_inicial, dmt_km_final,
        trecho, tipo, observacao, data_execucao, status_revisao
      ) VALUES (
        v_relatorio_id, v_ordem, v_uuid_ativ_disp, v_ativ->>'tipo_atividade',
        nullif(v_ativ->>'descricao_atividade', ''), v_ativ->>'up',
        (v_ativ->>'dimensao_m')::numeric,
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
        dimensao_m          = (v_ativ->>'dimensao_m')::numeric,
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

-- ---------------------------------------------------------------------------
-- 3. O painel passa a receber o campo
-- ---------------------------------------------------------------------------
-- Sem isto o operador digitaria a dimensão, ela chegaria ao banco e ninguém
-- a veria -- que é a pior das três situações possíveis.
--
-- A dimensão entra em dois lugares: no apontamento e na linha de produção do
-- caminho 2 (padrão de obra, onde as medidas são do apontamento). NÃO entra no
-- caminho 1 (máquina detalhada / hora máquina) de propósito: lá cada máquina
-- tem as medidas dela, e o formulário Padrão -- o único que tem Dimensão --
-- nunca produz linhas por aquele caminho.
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
          'dimensao_m', a.dimensao_m,
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

          -- ----- as linhas de produção -----
          'producoes', COALESCE(
            -- caminho 1: máquinas com medidas próprias (detalhado / hora máquina)
            (
              SELECT jsonb_agg(jsonb_build_object(
                'origem', 'maquina',
                'equipamento', m.equipamento,
                'operador', m.operador,
                'descricao_atividade', coalesce(m.dados->>'descricao', a.descricao_atividade),
                'codigo_tarifa',  tm.valor->>'codigo',
                'unidade_tarifa', tm.valor->>'unidade',
                'up',            coalesce(m.dados->>'up', a.up),
                'trecho',        coalesce(m.dados->>'trecho', a.trecho),
                'quantidade',      (m.dados->>'quantidade')::numeric,
                'hora_inicial',    (m.dados->>'hora_inicial')::numeric,
                'hora_final',      (m.dados->>'hora_final')::numeric,
                'comprimento_m',   (m.dados->>'comprimento_m')::numeric,
                'largura_m',       (m.dados->>'largura_m')::numeric,
                'profundidade_cm', (m.dados->>'profundidade_cm')::numeric,
                'observacao',      m.dados->>'observacao',
                'producao', producao_consolidada(
                  (m.dados->>'quantidade')::numeric,
                  tm.valor->>'unidade',
                  (m.dados->>'hora_inicial')::numeric,
                  (m.dados->>'hora_final')::numeric,
                  (m.dados->>'comprimento_m')::numeric,
                  (m.dados->>'largura_m')::numeric
                )
              ) ORDER BY m.id)
              FROM atividade_maquinas m
              LEFT JOIN regras_negocio tm
                     ON tm.tipo_regra = 'tarifa_descricao'
                    AND tm.chave = coalesce(m.dados->>'descricao', a.descricao_atividade)
                    AND tm.ativo
             WHERE m.atividade_id = a.id
               AND m.dados IS NOT NULL
               AND m.dados <> '{}'::jsonb
            ),
            -- caminho 2: padrão de obra -- as medidas são do apontamento, e as
            -- máquinas/equipamentos apenas participaram dele. Uma produção só.
            jsonb_build_array(jsonb_build_object(
              'origem', 'atividade',
              'equipamento', NULL,
              'operador', NULL,
              'descricao_atividade', a.descricao_atividade,
              'codigo_tarifa',  tar.valor->>'codigo',
              'unidade_tarifa', tar.valor->>'unidade',
              'up', a.up,
              'trecho', a.trecho,
              'quantidade', NULL,
              'hora_inicial', NULL,
              'hora_final', NULL,
              'dimensao_m', a.dimensao_m,
              'comprimento_m', a.comprimento_m,
              'largura_m', a.largura_m,
              'profundidade_cm', a.profundidade_cm,
              'observacao', a.observacao,
              -- A dimensão NÃO entra aqui. Vira insumo de cálculo no dia em
              -- que a finalidade for decidida -- não antes.
              'producao', producao_consolidada(
                NULL, tar.valor->>'unidade', NULL, NULL, a.comprimento_m, a.largura_m
              )
            ))
          ),

          'equipamentos', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('equipamento', e.equipamento, 'operador', e.operador)), '[]'::jsonb)
            FROM atividade_equipamentos e WHERE e.atividade_id = a.id
          ),
          'maquinas', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('equipamento', m2.equipamento, 'operador', m2.operador, 'dados', m2.dados)), '[]'::jsonb)
            FROM atividade_maquinas m2 WHERE m2.atividade_id = a.id
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

-- As duas linhas de sempre (BOAS_PRATICAS §2). Aqui elas RESTAURAM a ACL que
-- a função já tinha -- `anon` nunca alcançou esta, e continua não alcançando.
REVOKE ALL ON FUNCTION public.listar_relatorios_painel(date, date, text, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.listar_relatorios_painel(date, date, text, text, integer) TO authenticated;
