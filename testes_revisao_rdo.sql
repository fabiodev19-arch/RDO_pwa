-- ============================================================================
-- GTM RDO — bateria de testes do fluxo de revisão
-- ============================================================================
-- Rode DEPOIS de aplicar os arquivos 1 a 4. É a linha de base que faltava:
-- enquanto os 47 testes headless não voltam, isto é o que existe de
-- verificação automatizada neste projeto.
--
-- COMO RODAR: cole o arquivo INTEIRO no SQL Editor e execute de uma vez.
--
-- SEGURANÇA -- por que dá pra rodar isso no banco de produção:
--
-- Tudo acontece entre um BEGIN e um ROLLBACK. O relatório, as atividades e a
-- inscrição de push que os testes criam existem só dentro da transação e
-- somem no fim -- nada é commitado, nunca. E se algum statement falhar no
-- meio, melhor ainda: o Postgres aborta a transação inteira e também não
-- commita nada. Não existe caminho em que este arquivo deixe lixo no banco.
--
-- O único jeito de persistir alguma coisa seria executar statement por
-- statement e dar COMMIT na mão. Não faça isso.
--
-- Os testes NÃO tocam nos dados que já existem: o relatório de teste usa um
-- uuid_dispositivo novo a cada execução, e todo DELETE que roda vem de dentro
-- da própria RPC, restrito a esse relatório.
--
-- COMO LER O RESULTADO: a última consulta devolve duas coisas -- a lista de
-- testes e um resumo. O que importa é `falharam = 0`. Não confie no
-- "Success" do editor: ele diz que o SQL rodou, não que os testes passaram.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- Mini-arcabouço de asserção
-- ----------------------------------------------------------------------------
-- Uma condição NULL conta como FALHA, de propósito. NULL aqui quase sempre
-- quer dizer "a consulta não achou a linha que eu esperava" -- que é
-- exatamente um teste falhando, não um teste inconclusivo.
CREATE TEMP TABLE _resultado_teste (
  ordem   serial,
  secao   text,
  nome    text,
  passou  boolean,
  pulado  boolean NOT NULL DEFAULT false,
  detalhe text
);

CREATE FUNCTION pg_temp.checar(
  p_secao   text,
  p_nome    text,
  p_ok      boolean,
  p_detalhe text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _resultado_teste (secao, nome, passou, detalhe)
  VALUES (
    p_secao, p_nome, coalesce(p_ok, false),
    CASE WHEN coalesce(p_ok, false) THEN NULL
         ELSE coalesce(p_detalhe, 'condição falsa ou NULL') END
  );
END $$;

-- Um teste PULADO não é um teste que passou, e o relatório final não deixa os
-- dois se misturarem. Existe porque parte da seção C só faz sentido depois do
-- corte_sincronizacao_com_login.sql (arquivo 4) -- e o arquivo 4 só pode ser
-- aplicado DEPOIS de publicar o PWA com login. Sem isto a bateria teria uma
-- dependência circular: "não publique antes da bateria verde" x "a bateria só
-- fica verde depois de publicar".
--
-- Marcar como pulado é honesto; marcar como ok seria mentira, e deixar
-- explodir (que era o comportamento antes de 08/09) esconde TODAS as outras
-- seções -- a exceção aborta a transação inteira e não sai relatório nenhum.
CREATE FUNCTION pg_temp.pular(p_secao text, p_nome text, p_motivo text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _resultado_teste (secao, nome, passou, pulado, detalhe)
  VALUES (p_secao, p_nome, NULL, true, p_motivo);
END $$;

-- Existe a função, com esta assinatura exata?
CREATE FUNCTION pg_temp.existe_funcao(p_assinatura text)
RETURNS boolean LANGUAGE sql AS $$
  SELECT to_regprocedure(p_assinatura) IS NOT NULL;
$$;

-- anon consegue executar? (false também quando a função não existe -- e aí o
-- teste de existência da seção B é quem acusa)
CREATE FUNCTION pg_temp.anon_executa(p_assinatura text)
RETURNS boolean LANGUAGE sql AS $$
  SELECT coalesce(
    has_function_privilege('anon', to_regprocedure(p_assinatura), 'EXECUTE'),
    false
  );
$$;

-- ============================================================================
-- SEÇÃO A — schema (arquivo 1: revisao_schema_identidade_estavel.sql)
-- ============================================================================
DO $secao_a$
DECLARE
  v_col text;
BEGIN
  FOREACH v_col IN ARRAY ARRAY[
    'atividades.uuid_atividade_dispositivo',
    'atividades.status_revisao',
    'atividades.motivo_devolucao',
    'atividades.revisado_por',
    'atividades.revisado_em',
    'relatorios.criado_por'
  ]
  LOOP
    PERFORM pg_temp.checar('A', 'coluna ' || v_col || ' existe',
      EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name  = split_part(v_col, '.', 1)
          AND column_name = split_part(v_col, '.', 2)
      ));
  END LOOP;
END $secao_a$;

SELECT pg_temp.checar('A', 'tabela push_subscriptions existe',
  to_regclass('public.push_subscriptions') IS NOT NULL);

SELECT pg_temp.checar('A', 'push_subscriptions tem RLS ligada',
  (SELECT relrowsecurity FROM pg_class WHERE oid = to_regclass('public.push_subscriptions')));

-- A constraint é o que faz o upsert por identidade estável funcionar. Sem
-- ela, o ON CONFLICT do arquivo 4 nem compila.
SELECT pg_temp.checar('A', 'UNIQUE (relatorio_id, uuid_atividade_dispositivo) existe',
  EXISTS (SELECT 1 FROM pg_constraint
          WHERE conrelid = 'atividades'::regclass
            AND conname  = 'atividades_relatorio_uuid_dispositivo_key'));

SELECT pg_temp.checar('A', 'uuid_atividade_dispositivo é NOT NULL',
  (SELECT attnotnull FROM pg_attribute
    WHERE attrelid = 'atividades'::regclass AND attname = 'uuid_atividade_dispositivo'));

-- Backfill: nenhuma atividade antiga pode ter ficado sem identidade.
SELECT pg_temp.checar('A', 'nenhuma atividade sem uuid_atividade_dispositivo',
  NOT EXISTS (SELECT 1 FROM atividades WHERE uuid_atividade_dispositivo IS NULL));

SELECT pg_temp.checar('A', 'status_revisao só aceita os três valores previstos',
  EXISTS (SELECT 1 FROM pg_constraint
          WHERE conrelid = 'atividades'::regclass
            AND conname  = 'atividades_status_revisao_check'));

-- ============================================================================
-- SEÇÃO B — RPCs e permissões (arquivos 2 e 3)
-- ============================================================================
DO $secao_b$
DECLARE
  v_f text;
BEGIN
  FOREACH v_f IN ARRAY ARRAY[
    'public.validar_atividade_rdo(uuid)',
    'public.devolver_atividade_rdo(uuid,text)',
    'public.verificar_atividades_devolvidas()',
    'public.salvar_push_subscription(text,text,text)',
    'public.listar_relatorios_painel(date,date,text,text,integer)',
    'public.sincronizar_relatorio_rdo(jsonb)'
  ]
  LOOP
    PERFORM pg_temp.checar('B', 'função existe: ' || v_f, pg_temp.existe_funcao(v_f));
  END LOOP;

  -- Nenhuma destas pode ser chamável sem login. É o teste que responde à
  -- pergunta que abriu a auditoria de 08/09.
  FOREACH v_f IN ARRAY ARRAY[
    'public.validar_atividade_rdo(uuid)',
    'public.devolver_atividade_rdo(uuid,text)',
    'public.verificar_atividades_devolvidas()',
    'public.salvar_push_subscription(text,text,text)',
    'public.listar_relatorios_painel(date,date,text,text,integer)',
    'public.salvar_cadastro(uuid,text,text,boolean,integer)',
    'public.excluir_cadastro(uuid)',
    'public.salvar_regra(text,text,jsonb)',
    'public.excluir_regra(text,text)',
    'public.importar_cadastros_lote(jsonb)',
    'public.listar_cadastros_admin()',
    'public.listar_regras_admin()',
    'public.exige_mfa()'
  ]
  LOOP
    PERFORM pg_temp.checar('B', 'anon NÃO executa ' || v_f,
      NOT pg_temp.anon_executa(v_f));
  END LOOP;
END $secao_b$;

-- Estas duas são liberadas pra anon DE PROPÓSITO: o PWA lê o catálogo antes
-- de logar. Se um dia forem revogadas por engano, o app quebra na primeira
-- tela -- por isso o teste afirma o contrário das de cima.
SELECT pg_temp.checar('B', 'anon AINDA executa listar_cadastros() (proposital)',
  pg_temp.anon_executa('public.listar_cadastros()'));
SELECT pg_temp.checar('B', 'anon AINDA executa listar_regras() (proposital)',
  pg_temp.anon_executa('public.listar_regras()'));

-- sincronizar_relatorio_rdo é o ponto de corte: antes do arquivo 4 ela é
-- aberta pra anon, depois não. O teste aceita os dois estados mas registra
-- qual é -- assim a bateria não acusa falha falsa em quem ainda não cortou.
SELECT pg_temp.checar('B',
  'sincronizar_relatorio_rdo: estado do corte = ' ||
    CASE WHEN pg_temp.anon_executa('public.sincronizar_relatorio_rdo(jsonb)')
         THEN 'ABERTA pra anon (arquivo 4 ainda não aplicado)'
         ELSE 'fechada (arquivo 4 aplicado)' END,
  true);

-- ============================================================================
-- SEÇÃO C — comportamento do fluxo ponta a ponta
-- ============================================================================
-- Aqui os testes de verdade. Simulamos sessão do PostgREST com set_config
-- sobre 'request.jwt.claims', que é de onde auth.uid() e auth.jwt() leem
-- (conferido em pg_get_functiondef das duas). O 'aal' é o que o exige_mfa()
-- compara -- então dá pra testar com e sem 2FA sem precisar de um TOTP real.
DO $secao_c$
DECLARE
  v_uid       uuid;
  v_rel_uuid  uuid := gen_random_uuid();
  v_ativ_uuid uuid := gen_random_uuid();
  v_payload   jsonb;
  v_rel_id    uuid;
  v_ativ_id   uuid;
  v_status    text;
  v_motivo    text;
  v_qtd       int;
  v_corte     boolean;
  v_pq        text;
BEGIN
  -- criado_por tem FK pra auth.users, então precisamos de um usuário real.
  -- Não criamos um (mexer em auth.users é outro departamento) -- pegamos o
  -- que já existe. Nada é gravado nele; tudo cai no ROLLBACK.
  SELECT id INTO v_uid FROM auth.users ORDER BY created_at LIMIT 1;
  IF v_uid IS NULL THEN
    PERFORM pg_temp.checar('C', 'existe usuário em auth.users para testar', false,
      'auth.users vazia -- a seção C inteira foi pulada');
    RETURN;
  END IF;

  -- O arquivo 4 já entrou? A pergunta não é de gosto: sem ele a
  -- sincronizar_relatorio_rdo ainda apaga-e-recria as atividades a cada envio,
  -- e metade dos testes abaixo perde o sentido -- o id que eles seguem deixa
  -- de existir no meio do caminho. Detectamos pelo corpo da função, que é a
  -- fonte da verdade (o .sql em disco comprovadamente não é).
  v_corte := pg_get_functiondef('public.sincronizar_relatorio_rdo(jsonb)'::regprocedure)
             ILIKE '%uuid_atividade_dispositivo%';
  v_pq := 'depende do corte_sincronizacao_com_login.sql (arquivo 4), ainda não aplicado';

  PERFORM pg_temp.checar('C',
    'estado do arquivo 4 = ' || CASE WHEN v_corte THEN 'APLICADO (seção C roda inteira)'
                                     ELSE 'não aplicado (parte da seção C será pulada)' END,
    true);

  v_payload := jsonb_build_object(
    'uuid_dispositivo', v_rel_uuid,
    'cliente', 'Colheita', 'contrato', 'ARAUCO', 'faena', 'TESTE AUTOMATIZADO',
    'tipo_estrada', 'Acesso', 'equipe_frente', 'GTM - Obra de Arte 02',
    'fazenda', 'Elo Dourado 2', 'data', '2026-09-08',
    'encarregado', 'Elson', 'supervisor', 'Valmir',
    'tecnico_arauco', 'Edwilson', 'supervisor_arauco', 'Luciano',
    'criadoEm', now(), 'concluidoEm', now(),
    'atividades', jsonb_build_array(jsonb_build_object(
      'id', v_ativ_uuid,
      'tipo_atividade', 'Construção de Aterro',
      'observacao', 'TESTE AUTOMATIZADO - NAO DEVE PERSISTIR',
      'profundidade_cm', 30
    ))
  );

  -- C1 -- sem sessão, sincronizar tem que ser recusado.
  -- (Só vale depois do arquivo 4; antes dele a função aceita anônimo, e é
  -- justamente esse o furo que o corte fecha.)
  IF v_corte THEN
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      PERFORM sincronizar_relatorio_rdo(v_payload);
      PERFORM pg_temp.checar('C', 'sincronizar sem login é recusado', false,
        'a chamada passou -- o corte foi aplicado mas não está barrando anônimo');
    EXCEPTION WHEN OTHERS THEN
      PERFORM pg_temp.checar('C', 'sincronizar sem login é recusado',
        SQLERRM ILIKE '%logado%', SQLERRM);
    END;
  ELSE
    PERFORM pg_temp.pular('C', 'sincronizar sem login é recusado', v_pq);
  END IF;

  -- Daqui pra frente: sessão de operador de campo (logado, sem 2FA).
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);

  -- C2 -- sincronização cria relatório e atividade
  PERFORM sincronizar_relatorio_rdo(v_payload);

  SELECT id INTO v_rel_id FROM relatorios WHERE uuid_dispositivo = v_rel_uuid;
  PERFORM pg_temp.checar('C', 'sincronizar cria o relatório', v_rel_id IS NOT NULL);

  IF v_corte THEN
    PERFORM pg_temp.checar('C', 'sincronizar grava criado_por = quem estava logado',
      EXISTS (SELECT 1 FROM relatorios WHERE id = v_rel_id AND criado_por = v_uid));
  ELSE
    PERFORM pg_temp.pular('C', 'sincronizar grava criado_por = quem estava logado', v_pq);
  END IF;

  SELECT id, status_revisao INTO v_ativ_id, v_status
    FROM atividades WHERE relatorio_id = v_rel_id;
  PERFORM pg_temp.checar('C', 'atividade nasce pendente de revisão',
    v_status = 'pendente', 'status = ' || coalesce(v_status, 'NULL'));

  IF v_corte THEN
    PERFORM pg_temp.checar('C', 'atividade guarda o uuid que veio do aparelho',
      EXISTS (SELECT 1 FROM atividades
               WHERE id = v_ativ_id AND uuid_atividade_dispositivo = v_ativ_uuid));
  ELSE
    PERFORM pg_temp.pular('C', 'atividade guarda o uuid que veio do aparelho', v_pq);
  END IF;

  -- C3 -- devolver é ação de painel: sem 2FA, não passa
  BEGIN
    PERFORM devolver_atividade_rdo(v_ativ_id, 'motivo qualquer');
    PERFORM pg_temp.checar('C', 'devolver sem 2FA é recusado', false,
      'a chamada passou -- exige_mfa() não está barrando');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'devolver sem 2FA é recusado', true, SQLERRM);
  END;

  -- Agora sessão de revisor no painel (com 2FA confirmado).
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);

  -- C4 -- devolver sem escrever o motivo não pode passar
  BEGIN
    PERFORM devolver_atividade_rdo(v_ativ_id, '   ');
    PERFORM pg_temp.checar('C', 'devolver sem motivo é recusado', false,
      'a chamada passou -- espaço em branco foi aceito como motivo');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'devolver sem motivo é recusado',
      SQLERRM ILIKE '%motivo%', SQLERRM);
  END;

  -- C5 -- devolução de verdade
  PERFORM devolver_atividade_rdo(v_ativ_id, 'Profundidade nao bate com o combinado');
  SELECT status_revisao, motivo_devolucao INTO v_status, v_motivo
    FROM atividades WHERE id = v_ativ_id;
  PERFORM pg_temp.checar('C', 'devolver marca a atividade como devolvida',
    v_status = 'devolvido', 'status = ' || coalesce(v_status, 'NULL'));
  PERFORM pg_temp.checar('C', 'devolver guarda o motivo escrito pelo revisor',
    v_motivo = 'Profundidade nao bate com o combinado', coalesce(v_motivo, 'NULL'));
  PERFORM pg_temp.checar('C', 'devolver registra quem revisou',
    EXISTS (SELECT 1 FROM atividades
             WHERE id = v_ativ_id AND revisado_por = v_uid AND revisado_em IS NOT NULL));

  -- C6 -- o painel precisa enxergar o status (senão o badge fica sempre
  -- "pendente", que era o efeito de listar_relatorios_painel desatualizada)
  PERFORM pg_temp.checar('C', 'listar_relatorios_painel devolve status_revisao',
    EXISTS (
      SELECT 1
      FROM jsonb_array_elements(listar_relatorios_painel(NULL, NULL, NULL, NULL, 100)) rel,
           jsonb_array_elements(rel->'atividades') ativ
      WHERE (rel->>'id')::uuid = v_rel_id
        AND ativ->>'status_revisao' = 'devolvido'
    ));

  -- C7 -- o PWA precisa ver a devolução, e pelo id que ELE conhece.
  -- Depende de criado_por, que só é gravado pelo arquivo 4.
  IF v_corte THEN
    PERFORM pg_temp.checar('C', 'PWA vê a atividade devolvida',
      verificar_atividades_devolvidas() @>
        jsonb_build_array(jsonb_build_object('atividade_id', v_ativ_uuid)));
  ELSE
    PERFORM pg_temp.pular('C', 'PWA vê a atividade devolvida', v_pq);
  END IF;

  -- C8 e C9 -- reenvio e o furo do "validado que muda sozinho".
  --
  -- Este bloco inteiro só existe se o upsert por identidade estável estiver de
  -- pé. Sem o arquivo 4 a sincronização ainda faz DELETE + INSERT: no reenvio
  -- a atividade v_ativ_id deixa de existir e nasce outra com id novo. O
  -- validar_atividade_rdo seguinte levantava "Atividade não encontrada." e
  -- ABORTAVA a bateria inteira -- nenhuma seção saía no relatório, nem as que
  -- tinham passado. Foi o que aconteceu na primeira execução, em 08/09.
  IF v_corte THEN
    PERFORM sincronizar_relatorio_rdo(v_payload);

    SELECT status_revisao, motivo_devolucao INTO v_status, v_motivo
      FROM atividades WHERE id = v_ativ_id;
    PERFORM pg_temp.checar('C', 'reenvio de atividade devolvida volta pra pendente',
      v_status = 'pendente', 'status = ' || coalesce(v_status, 'NULL'));
    PERFORM pg_temp.checar('C', 'reenvio limpa o motivo da devolução',
      v_motivo IS NULL, coalesce(v_motivo, 'NULL'));

    SELECT count(*) INTO v_qtd FROM atividades WHERE relatorio_id = v_rel_id;
    PERFORM pg_temp.checar('C', 'reenvio não duplica a atividade',
      v_qtd = 1, 'atividades no relatório = ' || v_qtd);
    PERFORM pg_temp.checar('C', 'identidade estável: o id da atividade não muda no reenvio',
      EXISTS (SELECT 1 FROM atividades WHERE id = v_ativ_id AND relatorio_id = v_rel_id));

    PERFORM validar_atividade_rdo(v_ativ_id);
    SELECT status_revisao INTO v_status FROM atividades WHERE id = v_ativ_id;
    PERFORM pg_temp.checar('C', 'validar marca a atividade como validada',
      v_status = 'validado', 'status = ' || coalesce(v_status, 'NULL'));

    PERFORM sincronizar_relatorio_rdo(v_payload);
    SELECT status_revisao INTO v_status FROM atividades WHERE id = v_ativ_id;
    PERFORM pg_temp.checar('C', 'reenvio SEM mudança mantém validado',
      v_status = 'validado', 'status = ' || coalesce(v_status, 'NULL'));

    v_payload := jsonb_set(v_payload, '{atividades,0,profundidade_cm}', '45'::jsonb);
    PERFORM sincronizar_relatorio_rdo(v_payload);
    SELECT status_revisao INTO v_status FROM atividades WHERE id = v_ativ_id;
    PERFORM pg_temp.checar('C',
      'FURO: mudar medida de atividade JÁ VALIDADA volta pra pendente',
      v_status = 'pendente', 'status = ' || coalesce(v_status, 'NULL'));
  ELSE
    PERFORM pg_temp.pular('C', 'reenvio de atividade devolvida volta pra pendente', v_pq);
    PERFORM pg_temp.pular('C', 'reenvio limpa o motivo da devolução', v_pq);
    PERFORM pg_temp.pular('C', 'reenvio não duplica a atividade', v_pq);
    PERFORM pg_temp.pular('C', 'identidade estável: o id da atividade não muda no reenvio', v_pq);
    PERFORM pg_temp.pular('C', 'validar marca a atividade como validada', v_pq);
    PERFORM pg_temp.pular('C', 'reenvio SEM mudança mantém validado', v_pq);
    PERFORM pg_temp.pular('C', 'FURO: mudar medida de atividade JÁ VALIDADA volta pra pendente', v_pq);

    -- Sem o corte, validar/devolver ainda precisam ser exercitados de alguma
    -- forma -- só que na atividade que existe AGORA, não na que o reenvio
    -- destruiu. É o que dá pra afirmar hoje sobre validar_atividade_rdo.
    PERFORM validar_atividade_rdo(v_ativ_id);
    SELECT status_revisao INTO v_status FROM atividades WHERE id = v_ativ_id;
    PERFORM pg_temp.checar('C', 'validar marca a atividade como validada (sem reenvio)',
      v_status = 'validado', 'status = ' || coalesce(v_status, 'NULL'));
    PERFORM pg_temp.checar('C', 'validar limpa o motivo da devolução anterior',
      (SELECT motivo_devolucao IS NULL FROM atividades WHERE id = v_ativ_id));
  END IF;

  -- C10 -- atividade apagada no aparelho some do banco (e só ela)
  v_payload := jsonb_set(v_payload, '{atividades}', '[]'::jsonb);
  PERFORM sincronizar_relatorio_rdo(v_payload);
  PERFORM pg_temp.checar('C', 'atividade removida no aparelho é removida do banco',
    NOT EXISTS (SELECT 1 FROM atividades WHERE relatorio_id = v_rel_id));
  PERFORM pg_temp.checar('C', 'o relatório em si continua lá',
    EXISTS (SELECT 1 FROM relatorios WHERE id = v_rel_id));

  -- C11 -- inscrição de push
  PERFORM salvar_push_subscription('https://exemplo.invalido/push-teste', 'p256-a', 'auth-a');
  PERFORM pg_temp.checar('C', 'inscrição de push é salva no usuário logado',
    EXISTS (SELECT 1 FROM push_subscriptions
             WHERE usuario_id = v_uid AND endpoint = 'https://exemplo.invalido/push-teste'));

  -- O navegador renova as chaves de um endpoint que já existe: tem que
  -- atualizar, não criar uma segunda linha.
  PERFORM salvar_push_subscription('https://exemplo.invalido/push-teste', 'p256-b', 'auth-b');
  SELECT count(*) INTO v_qtd FROM push_subscriptions
   WHERE usuario_id = v_uid AND endpoint = 'https://exemplo.invalido/push-teste';
  PERFORM pg_temp.checar('C', 'reinscrição do mesmo endpoint atualiza, não duplica',
    v_qtd = 1, 'linhas = ' || v_qtd);
  PERFORM pg_temp.checar('C', 'reinscrição grava as chaves novas',
    EXISTS (SELECT 1 FROM push_subscriptions
             WHERE usuario_id = v_uid
               AND endpoint = 'https://exemplo.invalido/push-teste'
               AND p256dh = 'p256-b'));

  PERFORM set_config('request.jwt.claims', '', true);
END $secao_c$;

-- ============================================================================
-- SEÇÃO D — regressão: o que já funcionava tem que continuar funcionando
-- ============================================================================
-- É a parte que responde ao "garanta que nenhum passo quebre o anterior".
-- Estes testes não olham pro fluxo novo: olham pro que o PWA e o painel já
-- faziam antes desta leva e que os arquivos 1-4 poderiam ter quebrado sem
-- ninguém perceber.
SELECT pg_temp.checar('D', 'listar_cadastros() continua devolvendo o catálogo',
  jsonb_typeof(listar_cadastros()) = 'object' AND listar_cadastros() <> '{}'::jsonb);

SELECT pg_temp.checar('D', 'listar_regras() continua respondendo',
  jsonb_typeof(listar_regras()) = 'object');

-- As colunas antigas de atividades não podem ter sumido nem trocado de tipo
-- (o arquivo 1 só acrescenta, mas é exatamente esse tipo de promessa que um
-- teste serve pra cobrar).
DO $secao_d$
DECLARE
  v_par text;
BEGIN
  FOREACH v_par IN ARRAY ARRAY[
    'comprimento_m=numeric', 'largura_m=numeric', 'profundidade_cm=numeric',
    'dmt_km_inicial=numeric', 'dmt_km_final=numeric', 'trecho=text',
    'tipo=text', 'observacao=text', 'data_execucao=date', 'up=text',
    'tipo_atividade=text', 'ordem=integer'
  ]
  LOOP
    PERFORM pg_temp.checar('D',
      'atividades.' || split_part(v_par, '=', 1) || ' segue ' || split_part(v_par, '=', 2),
      EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'atividades'
                 AND column_name = split_part(v_par, '=', 1)
                 AND data_type   = split_part(v_par, '=', 2)));
  END LOOP;
END $secao_d$;

-- O upsert de relatório depende deste UNIQUE desde o começo. Se ele sumir,
-- reenviar um RDO passa a duplicar em vez de atualizar.
SELECT pg_temp.checar('D', 'relatorios.uuid_dispositivo continua UNIQUE',
  EXISTS (SELECT 1 FROM pg_constraint
           WHERE conrelid = 'relatorios'::regclass AND contype = 'u'
             AND pg_get_constraintdef(oid) ILIKE '%uuid_dispositivo%'));

-- As tabelas do RDO não podem ter perdido RLS. (push_subscriptions é checada
-- na seção A; aqui vão as que já existiam antes desta leva.)
DO $secao_d2$
DECLARE
  v_t text;
BEGIN
  FOREACH v_t IN ARRAY ARRAY[
    'relatorios', 'atividades', 'atividade_equipamentos',
    'atividade_maquinas', 'evidencias_fotos', 'cadastros', 'regras_negocio'
  ]
  LOOP
    PERFORM pg_temp.checar('D', v_t || ' segue com RLS ligada',
      (SELECT relrowsecurity FROM pg_class WHERE oid = to_regclass('public.' || v_t)));
  END LOOP;
END $secao_d2$;

-- Nada do RDO pode ter virado tabela aberta pra anon por acidente. O teste
-- lista NOMINALMENTE as tabelas do RDO em vez de varrer "toda tabela do
-- schema": este banco hospeda outros apps (ver CLAUDE.md §1.6), e o que é
-- deles não é assunto desta bateria -- nem para reprovar, nem para relatar.
SELECT pg_temp.checar('D', 'nenhuma tabela do RDO tem policy liberando anon',
  NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename IN ('relatorios','atividades','atividade_equipamentos',
                         'atividade_maquinas','evidencias_fotos','cadastros',
                         'regras_negocio','push_subscriptions')
       AND 'anon' = ANY (roles)
  ));

-- O teste que faltava em 08/09, e que teria evitado uma quebra em produção.
--
-- O arquivo 1 marca uuid_atividade_dispositivo como NOT NULL. A
-- sincronizar_relatorio_rdo que está EM CAMPO não preenche essa coluna, então
-- sem DEFAULT toda sincronização de operador passa a falhar com violação de
-- not-null -- e o RDO do dia fica preso no aparelho. Foi o que aconteceu ao
-- aplicar: a coluna virou NOT NULL e ninguém percebeu até conferir o corpo da
-- função no banco.
--
-- Este é um teste de seção D e não de A porque o que ele protege não é a
-- coluna nova: é o caminho de escrita ANTIGO, que já estava de pé.
SELECT pg_temp.checar('D', 'uuid_atividade_dispositivo tem DEFAULT (sem ele o PWA em campo quebra)',
  (SELECT column_default IS NOT NULL FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'atividades'
      AND column_name = 'uuid_atividade_dispositivo'));

-- E o mesmo pelo comportamento, que é o que de fato importa: o caminho de
-- sincronização vigente ainda consegue gravar um RDO inteiro.
DO $secao_d3$
DECLARE
  v_uid   uuid;
  v_uuid  uuid := gen_random_uuid();
  v_qtd   int;
  v_nulos int;
BEGIN
  -- Depois do arquivo 4 a função exige login, então o teste entra com sessão.
  -- Antes dele a sessão é ignorada -- o teste vale nos dois estados.
  SELECT id INTO v_uid FROM auth.users ORDER BY created_at LIMIT 1;
  IF v_uid IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims',
      jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  END IF;

  PERFORM sincronizar_relatorio_rdo(jsonb_build_object(
    'uuid_dispositivo', v_uuid,
    'cliente', 'Colheita', 'contrato', 'ARAUCO', 'faena', 'TESTE REGRESSAO',
    'tipo_estrada', 'Acesso', 'equipe_frente', 'GTM - Obra de Arte 02',
    'fazenda', 'Elo Dourado 2', 'data', '2026-09-08',
    'encarregado', 'Elson', 'supervisor', 'Valmir',
    'tecnico_arauco', 'Edwilson', 'supervisor_arauco', 'Luciano',
    'concluidoEm', now(),
    'atividades', jsonb_build_array(jsonb_build_object(
      'id', gen_random_uuid(),
      'tipo_atividade', 'Construção de Aterro', 'profundidade_cm', 30))
  ));

  SELECT count(*), count(*) FILTER (WHERE a.uuid_atividade_dispositivo IS NULL)
    INTO v_qtd, v_nulos
    FROM atividades a JOIN relatorios r ON r.id = a.relatorio_id
   WHERE r.uuid_dispositivo = v_uuid;

  PERFORM pg_temp.checar('D', 'sincronizar um RDO completo continua funcionando',
    v_qtd = 1, 'atividades gravadas = ' || v_qtd);
  PERFORM pg_temp.checar('D', 'a atividade sincronizada nunca fica sem uuid de dispositivo',
    v_nulos = 0, 'atividades com uuid nulo = ' || v_nulos);

  PERFORM set_config('request.jwt.claims', '', true);
EXCEPTION WHEN OTHERS THEN
  -- Uma exceção aqui é a própria falha -- registra em vez de abortar a bateria.
  PERFORM pg_temp.checar('D', 'sincronizar um RDO completo continua funcionando',
    false, SQLERRM);
END $secao_d3$;

-- ============================================================================
-- RESULTADO
-- ============================================================================
-- Uma consulta só, de propósito: alguns clientes (o MCP do Supabase, por
-- exemplo) devolvem apenas o resultado do ÚLTIMO SELECT do lote. Com o resumo
-- e a lista separados em dois, a lista de falhas simplesmente sumia -- e ficar
-- sabendo que "falharam = 3" sem poder ver QUAIS é quase tão ruim quanto não
-- rodar. O resumo vem na primeira linha, as falhas logo abaixo.
-- "VERDE" aqui quer dizer: nada que foi avaliado falhou. Se houver pulados, o
-- veredito diz isso na cara -- porque uma bateria verde com metade dos testes
-- pulados não é a mesma coisa que uma bateria verde, e essa diferença é
-- exatamente o que separa "pode publicar" de "ainda não".
WITH resumo AS (
  SELECT count(*)                                          AS total,
         count(*) FILTER (WHERE passou)                    AS passaram,
         count(*) FILTER (WHERE NOT pulado AND NOT passou) AS falharam,
         count(*) FILTER (WHERE pulado)                    AS pulados
  FROM _resultado_teste
)
SELECT resultado, secao, nome, detalhe FROM (
  SELECT 0 AS bloco, 0 AS ordem,
         CASE WHEN falharam > 0        THEN 'TEM FALHA'
              WHEN pulados  > 0        THEN 'VERDE (c/ pulados)'
              ELSE 'BATERIA VERDE' END                             AS resultado,
         '='                                                       AS secao,
         total || ' testes | ' || passaram || ' ok | ' || falharam
               || ' falharam | ' || pulados || ' pulados'          AS nome,
         CASE WHEN falharam > 0 THEN 'as linhas FALHA abaixo dizem o que veio'
              WHEN pulados  > 0 THEN 'as linhas PULADO dizem o que ainda não foi verificado'
              ELSE NULL END                                        AS detalhe
    FROM resumo
  UNION ALL
  SELECT 1, ordem,
         CASE WHEN pulado THEN 'PULADO'
              WHEN passou THEN 'ok    '
              ELSE 'FALHA ' END,
         secao, nome, detalhe
    FROM _resultado_teste
) t
ORDER BY bloco,
         CASE resultado WHEN 'FALHA ' THEN 0 WHEN 'PULADO' THEN 1 ELSE 2 END,
         ordem;

-- Nada acima é gravado. Este ROLLBACK é o que garante isso.
ROLLBACK;
