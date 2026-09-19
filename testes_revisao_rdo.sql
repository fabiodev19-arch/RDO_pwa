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
    'atividades.excluido_em',
    'atividades.excluido_por',
    'atividades.descricao_atividade',
    'atividades.dimensao_m',
    'atividades.editado_por',
    'atividades.editado_em',
    'atividades.producao_devolvida_indice',
    'atividades.producao_devolvida_maquina_uuid',
    'atividade_maquinas.uuid_maquina_dispositivo',
    -- 18/09: mesma marcação que atividades já tem -- produção removida vira
    -- MARCA, não DELETE literal (ver a seção C, "proteção contra perda de
    -- evidência").
    'atividade_maquinas.excluido_em',
    'atividade_maquinas.excluido_por',
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

-- As colunas de 17/09 (edição pelo painel + retrato da produção devolvida)
-- PRECISAM ser nullable, e isso não é detalhe: é a lição de 08/09, quando um
-- ADD COLUMN ... NOT NULL derrubou a sincronização de quem estava em campo,
-- porque a sincronizar_relatorio_rdo publicada não preenchia a coluna nova.
-- Apontamento nunca editado tem editado_por/editado_em nulos, e devolução sem
-- produção específica tem índice/uuid nulo -- nulo aqui é o estado NORMAL,
-- não falta de dado. producao_devolvida_indice ficou pra trás (substituído
-- pelo uuid, ver abaixo), mas continua nullable -- ninguém escreve nela mais.
DO $secao_a_edicao$
DECLARE
  v_col text;
BEGIN
  FOREACH v_col IN ARRAY ARRAY[
    'editado_por', 'editado_em', 'producao_devolvida_indice', 'producao_devolvida_maquina_uuid'
  ]
  LOOP
    PERFORM pg_temp.checar('A', 'atividades.' || v_col || ' é NULLABLE',
      EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'atividades'
          AND column_name = v_col AND is_nullable = 'YES'
      ),
      'NOT NULL aqui quebraria quem sincroniza sem conhecer a coluna');
  END LOOP;
END $secao_a_edicao$;

-- uuid_maquina_dispositivo é o oposto: PRECISA ser NOT NULL com DEFAULT
-- gen_random_uuid() -- é o que dá a cada máquina uma identidade mesmo quando
-- um app antigo não manda 'id' nenhum. NULL aqui destruiria a chave do
-- upsert (ON CONFLICT não casa linha com uuid nulo, e o comportamento
-- voltaria a ser apaga-e-recria sem ninguém perceber).
SELECT pg_temp.checar('A', 'atividade_maquinas.uuid_maquina_dispositivo é NOT NULL com DEFAULT',
  (SELECT attnotnull FROM pg_attribute
    WHERE attrelid = 'atividade_maquinas'::regclass AND attname = 'uuid_maquina_dispositivo')
  AND (SELECT column_default FROM information_schema.columns
        WHERE table_schema='public' AND table_name='atividade_maquinas'
          AND column_name='uuid_maquina_dispositivo') = 'gen_random_uuid()');

SELECT pg_temp.checar('A', 'nenhuma máquina sem uuid_maquina_dispositivo',
  NOT EXISTS (SELECT 1 FROM atividade_maquinas WHERE uuid_maquina_dispositivo IS NULL));

-- 18/09: NULLABLE de propósito -- máquina nunca removida tem excluido_em/por
-- nulos, e isso é o estado NORMAL (a maioria das máquinas nunca é removida).
SELECT pg_temp.checar('A', 'atividade_maquinas.excluido_em é NULLABLE',
  (SELECT is_nullable FROM information_schema.columns
    WHERE table_schema='public' AND table_name='atividade_maquinas' AND column_name='excluido_em') = 'YES',
  'NOT NULL aqui quebraria toda máquina que nunca foi removida');

SELECT pg_temp.checar('A', 'atividade_maquinas.excluido_por é NULLABLE',
  (SELECT is_nullable FROM information_schema.columns
    WHERE table_schema='public' AND table_name='atividade_maquinas' AND column_name='excluido_por') = 'YES');

-- É o que faz o upsert (ON CONFLICT) da sincronização funcionar.
SELECT pg_temp.checar('A', 'UNIQUE (atividade_id, uuid_maquina_dispositivo) existe',
  EXISTS (SELECT 1 FROM pg_constraint
          WHERE conrelid = 'atividade_maquinas'::regclass
            AND conname  = 'atividade_maquinas_atividade_uuid_disp_key'));

SELECT pg_temp.checar('A', 'tabela push_subscriptions existe',
  to_regclass('public.push_subscriptions') IS NOT NULL);

-- Dimensão (m), 10/09. Estes dois testes existem por causa do arquivo 1: um
-- NOT NULL numa coluna que o caminho de escrita vigente não preenchia derrubou
-- a sincronização de quem estava em campo. Coluna nova entra NULLABLE, e o
-- teste é o que impede alguém de "endurecer" isso depois sem pensar --
-- inclusive porque o campo é opcional na tela por decisão do Fábio.
SELECT pg_temp.checar('A', 'atividades.dimensao_m é numérica',
  (SELECT data_type FROM information_schema.columns
    WHERE table_schema='public' AND table_name='atividades' AND column_name='dimensao_m') = 'numeric');

SELECT pg_temp.checar('A', 'atividades.dimensao_m aceita nulo',
  (SELECT is_nullable FROM information_schema.columns
    WHERE table_schema='public' AND table_name='atividades' AND column_name='dimensao_m') = 'YES',
  'virou NOT NULL: todo apontamento sem dimensão passaria a falhar na sincronização');

-- Catálogo de descrições e o de-para de tarifa (descricao_atividade_e_tarifas.sql).
-- A contagem não é fixada em 108 de propósito: o catálogo cresce quando a
-- tarifa muda, e um teste que exige o número de hoje quebraria por acerto,
-- não por defeito. O que importa é que exista e que cada descrição tenha par.
SELECT pg_temp.checar('A', 'catálogo de descrições de atividade foi carregado',
  (SELECT count(*) FROM cadastros WHERE categoria = 'descricao_atividade' AND ativo) > 0);

SELECT pg_temp.checar('A', 'toda descrição do catálogo tem código e unidade de tarifa',
  NOT EXISTS (
    SELECT 1 FROM cadastros c
    WHERE c.categoria = 'descricao_atividade' AND c.ativo
      AND NOT EXISTS (
        SELECT 1 FROM regras_negocio r
        WHERE r.tipo_regra = 'tarifa_descricao' AND r.ativo
          AND r.chave = c.valor
          AND r.valor->>'codigo' IS NOT NULL
          AND r.valor->>'unidade' IS NOT NULL
      )
  ),
  'existe descrição no catálogo sem tarifa: o painel não conseguiria calcular a produção dela');

-- valor_unitario entrou em 17/09 (carga de valor_unitario_tarifas_17_09.sql),
-- pedido do Fábio para compor um relatório de faturamento que ainda não foi
-- construído. Mesmo espírito do teste acima: se alguma descrição ficar sem
-- valor, esse relatório futuro nasceria com um furo silencioso -- exatamente
-- o tipo de coisa que só aparece quando alguém for cobrar e faltar dado.
SELECT pg_temp.checar('A', 'toda tarifa tem valor_unitario numérico e positivo',
  NOT EXISTS (
    SELECT 1 FROM regras_negocio r
    WHERE r.tipo_regra = 'tarifa_descricao' AND r.ativo
      AND (
        r.valor->>'valor_unitario' IS NULL
        OR (r.valor->>'valor_unitario')::numeric <= 0
      )
  ),
  'existe tarifa sem valor_unitario, ou com valor zero/negativo');

-- A unidade é o que decide a fórmula da produção consolidada, então uma
-- unidade escrita fora do combinado (minúscula, com espaço) viraria uma
-- atividade que nunca casa com nenhuma regra de cálculo.
SELECT pg_temp.checar('A', 'as unidades de tarifa estão todas na lista conhecida',
  NOT EXISTS (
    SELECT 1 FROM regras_negocio
    WHERE tipo_regra = 'tarifa_descricao' AND ativo
      AND valor->>'unidade' NOT IN ('M²','M³','HT','HD','KM','UN','DIÁRIA')
  ),
  (SELECT coalesce(string_agg(DISTINCT valor->>'unidade', ', '), '')
     FROM regras_negocio
    WHERE tipo_regra = 'tarifa_descricao' AND ativo
      AND valor->>'unidade' NOT IN ('M²','M³','HT','HD','KM','UN','DIÁRIA')));

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
    'public.sincronizar_relatorio_rdo(jsonb)',
    'public.salvar_descricao_tarifa(uuid,text,text,text,numeric,boolean)',
    'public.editar_atividade_rdo(uuid,text,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,text)',
    -- O overload de 3 parâmetros por INTEIRO foi o primeiro rascunho da
    -- devolução individual (17/09, mais cedo) -- superado ainda no mesmo dia
    -- pelo de uuid (o índice não sobrevive a uma correção, ver o comentário
    -- da seção C). Fica na lista de propósito: nada foi removido, e o de 2
    -- parâmetros continua sendo o atalho que o Painel publicado usa quando
    -- não aponta uma produção.
    'public.devolver_atividade_rdo(uuid,text,integer)',
    -- O overload por uuid da máquina é o que vale de verdade -- é o que o
    -- Painel chama quando o revisor aponta uma produção específica.
    'public.devolver_atividade_rdo(uuid,text,uuid)',
    -- Reconstrução local (18/09): o PWA usa isto quando o IndexedDB some por
    -- um motivo que não é a poda de 30 dias (cache/dados do site limpos,
    -- aparelho trocado) -- resgata o que já subiu, filtrado por dono.
    'public.listar_meus_relatorios_pwa()'
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
    'public.exige_mfa()',
    'public.salvar_descricao_tarifa(uuid,text,text,text,numeric,boolean)',
    'public.editar_atividade_rdo(uuid,text,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,text)',
    'public.devolver_atividade_rdo(uuid,text,integer)',
    'public.devolver_atividade_rdo(uuid,text,uuid)',
    'public.listar_meus_relatorios_pwa()'
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
  v_payload_cheio jsonb;
  v_qtd_antes_medida numeric;
  v_numero_inicial   bigint;
  v_resp_c10      jsonb;
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
      -- Descrição REAL do catálogo de tarifas (código 1077, unidade M³). Tem
      -- que ser real: é a chave do de-para, e uma inventada testaria só o
      -- caminho em que nada casa.
      'descricao_atividade', 'CONSTRUÇÃO DE ATERRO - M³',
      'observacao', 'TESTE AUTOMATIZADO - NAO DEVE PERSISTIR',
      'profundidade_cm', 30,
      -- A foto existe no payload por causa do C10: ela é a evidência que a
      -- exclusão apagava junto com a atividade, e o Storage não tem histórico.
      'fotos', jsonb_build_array(jsonb_build_object('storage_path','teste/evidencia-automatizada.jpg'))
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

  -- A descrição chegou ao banco? É ela que amarra o apontamento à tarifa.
  PERFORM pg_temp.checar('C', 'sincronizar grava a descrição de atividade',
    EXISTS (SELECT 1 FROM atividades a
             WHERE a.relatorio_id = v_rel_id
               AND a.descricao_atividade = 'CONSTRUÇÃO DE ATERRO - M³'),
    'a descrição não foi gravada: sem ela o apontamento não tem tarifa nem unidade');

  IF v_corte THEN
    PERFORM pg_temp.checar('C', 'sincronizar grava criado_por = quem estava logado',
      EXISTS (SELECT 1 FROM relatorios WHERE id = v_rel_id AND criado_por = v_uid));
  ELSE
    PERFORM pg_temp.pular('C', 'sincronizar grava criado_por = quem estava logado', v_pq);
  END IF;

  SELECT id, status_revisao INTO v_ativ_id, v_status
    FROM atividades WHERE relatorio_id = v_rel_id;
  v_numero_inicial := (SELECT numero FROM atividades WHERE id = v_ativ_id);
  PERFORM pg_temp.checar('C', 'o apontamento recebe número ao ser criado no banco',
    v_numero_inicial IS NOT NULL, 'número nulo');

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

  -- O painel recebe a tarifa RESOLVIDA, não a descrição crua: é o servidor que
  -- faz o de-para, porque a unidade decide a fórmula da produção -- número que
  -- vira faturamento não se calcula no navegador (BOAS_PRATICAS §2).
  PERFORM pg_temp.checar('C', 'o painel recebe código e unidade da tarifa já resolvidos',
    EXISTS (
      SELECT 1
      FROM jsonb_array_elements(listar_relatorios_painel(NULL, NULL, NULL, NULL, 100)) rel,
           jsonb_array_elements(rel->'atividades') ativ
      WHERE (rel->>'id')::uuid = v_rel_id
        AND ativ->>'descricao_atividade' = 'CONSTRUÇÃO DE ATERRO - M³'
        AND ativ->>'codigo_tarifa'  IS NOT NULL
        AND ativ->>'unidade_tarifa' = 'M³'
    ),
    'o de-para não resolveu: o painel receberia a descrição sem tarifa nem unidade');

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

    -- O FURO DO "VALIDADO QUE MUDA SOZINHO" -- e por que este teste mudou.
    --
    -- Até 08/09 o mecanismo era DETECTAR: se um dado do apontamento chegasse
    -- diferente, o status voltava para 'pendente' e o revisor olhava de novo.
    -- Este teste afirmava exatamente isso.
    --
    -- Em 09/09 a regra ficou mais forte, a pedido do Fábio: apontamento que já
    -- subiu não pode ser alterado, ponto (trava_edicao_pos_envio.sql). A
    -- alteração é IGNORADA na origem, então a medida nem chega a mudar e o
    -- status continua 'validado'.
    --
    -- Impedir é melhor do que detectar depois, mas o teste tinha que
    -- acompanhar: mantido do jeito antigo, ele falharia -- e falharia
    -- acusando o comportamento CORRETO, que é o pior tipo de teste velho.
    v_qtd_antes_medida := (SELECT profundidade_cm FROM atividades WHERE id = v_ativ_id);
    v_payload := jsonb_set(v_payload, '{atividades,0,profundidade_cm}', '45'::jsonb);
    PERFORM sincronizar_relatorio_rdo(v_payload);
    SELECT status_revisao INTO v_status FROM atividades WHERE id = v_ativ_id;

    PERFORM pg_temp.checar('C',
      'alterar medida de atividade JÁ VALIDADA é ignorado (não muda o dado)',
      (SELECT profundidade_cm FROM atividades WHERE id = v_ativ_id) = v_qtd_antes_medida,
      'a medida mudou para ' || coalesce((SELECT profundidade_cm::text FROM atividades WHERE id = v_ativ_id), 'NULL'));

    PERFORM pg_temp.checar('C',
      'e a atividade validada continua validada',
      v_status = 'validado', 'status = ' || coalesce(v_status, 'NULL'));

    -- O número visível não pode mudar ao longo de tudo isso: é a referência
    -- que o operador e o revisor usam para citar o mesmo apontamento.
    PERFORM pg_temp.checar('C', 'o número do apontamento não mudou em nenhum reenvio',
      (SELECT numero FROM atividades WHERE id = v_ativ_id) = v_numero_inicial,
      'número era ' || coalesce(v_numero_inicial::text,'NULL') ||
      ' e virou ' || coalesce((SELECT numero::text FROM atividades WHERE id = v_ativ_id),'NULL'));
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

  -- Guardado ANTES de esvaziar: é ele que devolve a atividade no fim do C10,
  -- para testar que recriar no aparelho limpa a marca de remoção.
  v_payload_cheio := v_payload;

  -- C9b -- ALTERNÂNCIA: painel devolve, campo corrige, painel pode de novo
  --
  -- Regra do Fábio (08/09): cada um faz a sua parte. Antes disto, o botão
  -- "Devolver" continuava ativo depois de devolver, e clicar de novo não
  -- mudava estado nenhum -- só disparava mais uma notificação para o operador
  -- sobre o mesmo pedido, o que em campo vira ruído e some com a confiança no
  -- aviso. Ver trava_devolucao_alternada.sql.
  PERFORM devolver_atividade_rdo(v_ativ_id, 'Primeira devolução');

  BEGIN
    PERFORM devolver_atividade_rdo(v_ativ_id, 'Insistindo sem o campo responder');
    PERFORM pg_temp.checar('C', 'ALTERNÂNCIA: devolver duas vezes seguidas é recusado',
      false, 'a segunda devolução passou -- a trava não está valendo');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'ALTERNÂNCIA: devolver duas vezes seguidas é recusado',
      SQLERRM ILIKE '%aguardando%', SQLERRM);
  END;

  -- A tentativa recusada não pode ter sobrescrito o motivo da devolução real.
  PERFORM pg_temp.checar('C', 'devolução recusada não altera o motivo já gravado',
    (SELECT motivo_devolucao = 'Primeira devolução' FROM atividades WHERE id = v_ativ_id),
    (SELECT coalesce(motivo_devolucao,'NULL') FROM atividades WHERE id = v_ativ_id));

  -- O campo faz a parte dele: corrige e reenvia.
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  v_payload := jsonb_set(v_payload, '{atividades,0,profundidade_cm}', '52'::jsonb);
  PERFORM sincronizar_relatorio_rdo(v_payload);
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);

  -- E agora o painel pode devolver de novo.
  BEGIN
    PERFORM devolver_atividade_rdo(v_ativ_id, 'Ainda não confere');
    PERFORM pg_temp.checar('C', 'ALTERNÂNCIA: depois da correção, devolver volta a ser permitido', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'ALTERNÂNCIA: depois da correção, devolver volta a ser permitido',
      false, SQLERRM);
  END;

  -- Validar uma devolvida continua permitido de propósito: é o revisor mudando
  -- de ideia, não ação repetida -- e validar não notifica ninguém.
  BEGIN
    PERFORM validar_atividade_rdo(v_ativ_id);
    PERFORM pg_temp.checar('C', 'validar uma atividade devolvida continua permitido', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'validar uma atividade devolvida continua permitido', false, SQLERRM);
  END;

  -- E devolver uma validada também: corrige aprovação equivocada, e o estado
  -- anterior não era 'devolvido', então a alternância segue respeitada.
  BEGIN
    PERFORM devolver_atividade_rdo(v_ativ_id, 'Aprovei por engano');
    PERFORM pg_temp.checar('C', 'devolver uma atividade validada continua permitido', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'devolver uma atividade validada continua permitido', false, SQLERRM);
  END;

  -- C10 -- apagar uma atividade DEVOLVIDA deixou de ser honrado (18/09)
  --
  -- Este teste já afirmou duas coisas diferentes: "é apagada do banco" (até
  -- 08/09) e depois "fica marcada com excluido_em, não apagada" (08/09 a
  -- 18/09). Mudou de novo, agora por pedido do Fábio: mesmo marcada, uma
  -- exclusão escondia que a produção questionada tinha sido DESCARTADA em
  -- vez de CORRIGIDA -- o `status_revisao` e o motivo sumiam junto. O
  -- caminho certo agora é só editar e reenviar; omitir do payload uma
  -- atividade devolvida simplesmente não é mais honrado -- ela continua
  -- EXATAMENTE como estava. Ver protecao_exclusao_devolucao.sql.
  v_payload := jsonb_set(v_payload, '{atividades}', '[]'::jsonb);
  v_resp_c10 := sincronizar_relatorio_rdo(v_payload);

  PERFORM pg_temp.checar('C', 'omitir uma atividade devolvida NÃO a remove nem marca -- continua devolvida, intacta',
    EXISTS (SELECT 1 FROM atividades WHERE id = v_ativ_id AND excluido_em IS NULL AND status_revisao = 'devolvido'));
  PERFORM pg_temp.checar('C', 'o relatório em si continua lá',
    EXISTS (SELECT 1 FROM relatorios WHERE id = v_rel_id));
  PERFORM pg_temp.checar('C', 'PWA continua cobrando a correção (a devolução não sumiu com a tentativa)',
    verificar_atividades_devolvidas() @>
         jsonb_build_array(jsonb_build_object('atividade_id', v_ativ_uuid)));
  -- O que mais importa nesta regra: nada se perde, porque a tentativa de
  -- remoção nem chega a ter efeito -- diferente da marcação (08/09), que já
  -- preservava mas mudava o status.
  PERFORM pg_temp.checar('C', 'as fotos continuam lá (nada foi removido de verdade)',
    EXISTS (SELECT 1 FROM evidencias_fotos WHERE atividade_id = v_ativ_id));
  PERFORM pg_temp.checar('C', 'o motivo da devolução continua lá, sem mudar',
    (SELECT motivo_devolucao IS NOT NULL FROM atividades WHERE id = v_ativ_id));
  PERFORM pg_temp.checar('C', 'painel continua vendo a atividade como devolvida, não como removida',
    EXISTS (
      SELECT 1 FROM jsonb_array_elements(listar_relatorios_painel(NULL,NULL,NULL,NULL,100)) rel,
                    jsonb_array_elements(rel->'atividades') ativ
       WHERE (rel->>'id')::uuid = v_rel_id AND (ativ->>'id')::uuid = v_ativ_id
         AND ativ->>'excluido_em' IS NULL AND ativ->>'status_revisao' = 'devolvido'));
  PERFORM pg_temp.checar('C', 'a tentativa de omitir é contabilizada em remocoes_negadas',
    (v_resp_c10->>'remocoes_negadas')::int >= 1, coalesce(v_resp_c10->>'remocoes_negadas', 'NULL'));

  -- Reenviar com a atividade de volta (payload completo) segue o caminho
  -- normal de correção -- devolvido volta a pendente, como sempre.
  PERFORM sincronizar_relatorio_rdo(v_payload_cheio);
  PERFORM pg_temp.checar('C', 'reenviar com a atividade de volta corrige normalmente (volta a pendente)',
    (SELECT status_revisao = 'pendente' AND excluido_em IS NULL FROM atividades WHERE id = v_ativ_id));

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
-- SEÇÃO C (continuação) — produção consolidada, uma linha por produção
-- ============================================================================
-- Um apontamento de "máquinas detalhado" vale N produções, uma por máquina,
-- cada uma com sua descrição, sua tarifa e sua unidade -- a escavadeira pode
-- estar em M³ e o caminhão em HT no mesmo serviço.
--
-- Este caminho não existia em dado nenhum do banco quando foi escrito: NENHUMA
-- atividade tinha mais de uma máquina. Ou seja, sem este teste a lógica de N
-- produções iria para produção sem nunca ter rodado.
DO $secao_c_prod$
DECLARE
  v_uid       uuid;
  v_rel_uuid  uuid := gen_random_uuid();
  v_ativ_uuid uuid := gen_random_uuid();
  v_prods     jsonb;
  v_p_area    jsonb;
  v_p_hora    jsonb;
BEGIN
  SELECT id INTO v_uid FROM auth.users ORDER BY created_at LIMIT 1;
  IF v_uid IS NULL THEN
    PERFORM pg_temp.pular('C', 'produção consolidada por máquina', 'auth.users vazia');
    RETURN;
  END IF;

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);

  -- Duas máquinas no MESMO apontamento, com descrições de unidades diferentes.
  PERFORM sincronizar_relatorio_rdo(jsonb_build_object(
    'uuid_dispositivo', v_rel_uuid,
    'cliente', 'Colheita', 'contrato', 'ARAUCO', 'faena', 'TESTE PRODUCAO',
    'tipo_estrada', 'Acesso', 'equipe_frente', 'GTM', 'fazenda', 'Elo Dourado 2',
    'data', '2026-09-09', 'encarregado', 'Elson', 'supervisor', 'Valmir',
    'tecnico_arauco', 'Edwilson', 'supervisor_arauco', 'Luciano', 'concluidoEm', now(),
    'atividades', jsonb_build_array(jsonb_build_object(
      'id', v_ativ_uuid,
      'tipo_atividade', 'Patrolamento',
      'maquinas', jsonb_build_array(
        -- por ÁREA: sem quantidade, unidade M³ -> comprimento * largura = 200
        jsonb_build_object('equipamento','MN-006','operador','JOSE',
          'dados', jsonb_build_object('descricao','CONSTRUÇÃO DE ATERRO - M³',
                                      'comprimento_m', 20, 'largura_m', 10)),
        -- por HORA: sem quantidade, unidade HT -> hora_final - hora_inicial = 3.5
        jsonb_build_object('equipamento','CB-014','operador','MARCELO',
          'dados', jsonb_build_object('descricao','CAMINHÃO CAÇAMBA - HT',
                                      'hora_inicial', 7.5, 'hora_final', 11))
      )))
  ));

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);

  SELECT ativ->'producoes' INTO v_prods
    FROM jsonb_array_elements(listar_relatorios_painel(NULL, NULL, NULL, NULL, 200)) rel,
         jsonb_array_elements(rel->'atividades') ativ
   WHERE rel->>'id' = (SELECT id::text FROM relatorios WHERE uuid_dispositivo = v_rel_uuid);

  PERFORM pg_temp.checar('C', 'apontamento com 2 máquinas rende 2 linhas de produção',
    jsonb_array_length(coalesce(v_prods, '[]'::jsonb)) = 2,
    'produções = ' || jsonb_array_length(coalesce(v_prods, '[]'::jsonb)));

  SELECT p INTO v_p_area FROM jsonb_array_elements(coalesce(v_prods,'[]'::jsonb)) p
   WHERE p->>'equipamento' = 'MN-006';
  SELECT p INTO v_p_hora FROM jsonb_array_elements(coalesce(v_prods,'[]'::jsonb)) p
   WHERE p->>'equipamento' = 'CB-014';

  PERFORM pg_temp.checar('C', 'cada máquina carrega a SUA tarifa, não a do apontamento',
    v_p_area->>'unidade_tarifa' = 'M³' AND v_p_hora->>'unidade_tarifa' = 'HT',
    'unidades: ' || coalesce(v_p_area->>'unidade_tarifa','?') || ' e ' || coalesce(v_p_hora->>'unidade_tarifa','?'));

  -- A fórmula, nos dois ramos que ela tem quando não há quantidade.
  PERFORM pg_temp.checar('C', 'produção por área = comprimento x largura',
    (v_p_area->>'producao')::numeric = 200,
    'veio ' || coalesce(v_p_area->>'producao','NULL') || ', esperado 200');

  PERFORM pg_temp.checar('C', 'produção por hora = hora final - hora inicial (unidade HT)',
    (v_p_hora->>'producao')::numeric = 3.5,
    'veio ' || coalesce(v_p_hora->>'producao','NULL') || ', esperado 3.5');

  PERFORM pg_temp.checar('C', 'a produção vem com o código de tarifa da própria máquina',
    v_p_area->>'codigo_tarifa' IS NOT NULL AND v_p_hora->>'codigo_tarifa' IS NOT NULL
      AND v_p_area->>'codigo_tarifa' <> v_p_hora->>'codigo_tarifa',
    'códigos: ' || coalesce(v_p_area->>'codigo_tarifa','?') || ' e ' || coalesce(v_p_hora->>'codigo_tarifa','?'));

  PERFORM set_config('request.jwt.claims', '', true);
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.checar('C', 'produção consolidada por máquina', false, SQLERRM);
END $secao_c_prod$;

-- ============================================================================
-- SEÇÃO C (continuação) — Dimensão (m) faz o caminho inteiro
-- ============================================================================
-- Campo novo de 10/09, do formulário Padrão (obra). Não veio da planilha da
-- Arauco: veio dos apontamentos que chegam por WhatsApp.
--
-- O que este teste protege é o caminho todo, não a coluna: o número sai do
-- aparelho, é gravado, e volta ao painel. Um campo que o PWA envia e a RPC
-- ignora em silêncio é a pior falha possível aqui -- o operador digita, vê o
-- check verde, e o dado nunca existiu. Não dá erro em lugar nenhum.
DO $secao_c_dim$
DECLARE
  v_uid       uuid;
  v_rel_uuid  uuid := gen_random_uuid();
  v_ativ_uuid uuid := gen_random_uuid();
  v_ativ      jsonb;
  v_prod      jsonb;
BEGIN
  SELECT id INTO v_uid FROM auth.users ORDER BY created_at LIMIT 1;
  IF v_uid IS NULL THEN
    PERFORM pg_temp.pular('C', 'dimensão faz o caminho inteiro', 'auth.users vazia');
    RETURN;
  END IF;

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);

  PERFORM sincronizar_relatorio_rdo(jsonb_build_object(
    'uuid_dispositivo', v_rel_uuid,
    'cliente', 'Colheita', 'contrato', 'ARAUCO', 'faena', 'TESTE DIMENSAO',
    'tipo_estrada', 'Acesso', 'equipe_frente', 'GTM', 'fazenda', 'Elo Dourado 2',
    'data', '2026-09-10', 'encarregado', 'Elson', 'supervisor', 'Valmir',
    'tecnico_arauco', 'Edwilson', 'supervisor_arauco', 'Luciano', 'concluidoEm', now(),
    'atividades', jsonb_build_array(jsonb_build_object(
      'id', v_ativ_uuid,
      'tipo_atividade', 'Patrolamento',
      'descricao_atividade', 'CONSTRUÇÃO DE ATERRO - M³',
      'up', 'UP-4471',
      'dimensao_m', 8.5,
      'comprimento_m', 20, 'largura_m', 10
    ))
  ));

  PERFORM pg_temp.checar('C', 'a dimensão enviada pelo PWA é gravada na atividade',
    (SELECT dimensao_m FROM atividades WHERE uuid_atividade_dispositivo = v_ativ_uuid) = 8.5,
    'gravado: ' || coalesce((SELECT dimensao_m::text FROM atividades
                              WHERE uuid_atividade_dispositivo = v_ativ_uuid), 'NULL'));

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);

  SELECT ativ INTO v_ativ
    FROM jsonb_array_elements(listar_relatorios_painel(NULL, NULL, NULL, NULL, 200)) rel,
         jsonb_array_elements(rel->'atividades') ativ
   WHERE ativ->>'id' = (SELECT id::text FROM atividades WHERE uuid_atividade_dispositivo = v_ativ_uuid);

  PERFORM pg_temp.checar('C', 'o painel recebe a dimensão do apontamento',
    (v_ativ->>'dimensao_m')::numeric = 8.5,
    'veio ' || coalesce(v_ativ->>'dimensao_m', 'NULL'));

  SELECT p INTO v_prod FROM jsonb_array_elements(coalesce(v_ativ->'producoes','[]'::jsonb)) p LIMIT 1;

  PERFORM pg_temp.checar('C', 'a dimensão também vem na linha de produção do padrão de obra',
    (v_prod->>'dimensao_m')::numeric = 8.5,
    'veio ' || coalesce(v_prod->>'dimensao_m', 'NULL'));

  -- A trava que impede a dimensão de mudar o faturamento sem ninguém decidir.
  -- Comprimento 20 x largura 10 = 200, e a dimensão (8.5) não entra na conta.
  -- No dia em que a finalidade dela for decidida, é AQUI que o teste acusa.
  PERFORM pg_temp.checar('C', 'a dimensão NÃO entra na produção consolidada (ainda é só registro)',
    (v_prod->>'producao')::numeric = 200,
    'produção veio ' || coalesce(v_prod->>'producao','NULL') || ', esperado 200 (comprimento x largura)');

  PERFORM set_config('request.jwt.claims', '', true);
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.checar('C', 'dimensão faz o caminho inteiro', false, SQLERRM);
END $secao_c_dim$;

-- ============================================================================
-- SEÇÃO C (continuação) — validar não é repetível
-- ============================================================================
-- Notado pelo Fábio em 10/09: dava para validar o mesmo apontamento quantas
-- vezes quisesse. O status não corrompia (seguia 'validado'), mas cada clique
-- regravava revisado_por e revisado_em -- apagando quem validou primeiro e
-- quando, que é a informação que essas colunas existem para guardar.
DO $secao_c_val$
DECLARE
  v_uid  uuid;
  v_rel  uuid := gen_random_uuid();
  v_aid  uuid;
  v_rev1 timestamptz;
  v_rev2 timestamptz;
  v_st   text;
BEGIN
  SELECT id INTO v_uid FROM auth.users ORDER BY created_at LIMIT 1;
  IF v_uid IS NULL THEN
    PERFORM pg_temp.pular('C', 'validar não é repetível', 'auth.users vazia');
    RETURN;
  END IF;

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  PERFORM sincronizar_relatorio_rdo(jsonb_build_object('uuid_dispositivo', v_rel,
    'cliente','Colheita','contrato','ARAUCO','faena','TESTE TRAVA VALIDACAO','tipo_estrada','Acesso',
    'equipe_frente','GTM','fazenda','Elo Dourado 2','data','2026-09-10','encarregado','Elson',
    'supervisor','Valmir','tecnico_arauco','Edwilson','supervisor_arauco','Luciano','concluidoEm', now(),
    'atividades', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(),
      'tipo_atividade','Construção de Aterro','comprimento_m',10,'largura_m',4))));
  SELECT a.id INTO v_aid
    FROM atividades a JOIN relatorios r ON r.id = a.relatorio_id
   WHERE r.uuid_dispositivo = v_rel;

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);

  PERFORM validar_atividade_rdo(v_aid);
  SELECT revisado_em INTO v_rev1 FROM atividades WHERE id = v_aid;
  PERFORM pg_temp.checar('C', 'a primeira validação passa', v_rev1 IS NOT NULL);

  BEGIN
    PERFORM validar_atividade_rdo(v_aid);
    PERFORM pg_temp.checar('C', 'validar DUAS VEZES é recusado', false, 'a segunda passou');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'validar DUAS VEZES é recusado', SQLERRM ILIKE '%já foi validado%', SQLERRM);
  END;

  -- O que a trava protege de verdade: o carimbo de quem validou primeiro.
  SELECT revisado_em, status_revisao INTO v_rev2, v_st FROM atividades WHERE id = v_aid;
  PERFORM pg_temp.checar('C', 'a recusa preserva o carimbo da primeira revisão',
    v_rev1 = v_rev2,
    'revisado_em foi regravado -- perdeu-se quem validou primeiro e quando');
  PERFORM pg_temp.checar('C', 'e o status continua validado depois da recusa',
    v_st = 'validado', 'status = ' || coalesce(v_st,'NULL'));

  -- O caminho legítimo de revalidar continua aberto: devolver reabre o ciclo.
  PERFORM devolver_atividade_rdo(v_aid, 'Revisando de novo');
  BEGIN
    PERFORM validar_atividade_rdo(v_aid);
    PERFORM pg_temp.checar('C', 'depois de devolver, validar volta a ser permitido', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'depois de devolver, validar volta a ser permitido', false, SQLERRM);
  END;

  PERFORM set_config('request.jwt.claims', '', true);
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.checar('C', 'validar não é repetível', false, SQLERRM);
END $secao_c_val$;

-- A quantidade ganha de tudo: é o primeiro ramo da fórmula do Excel, e o que
-- mais aparece em campo. Testado direto na função para não depender de uma
-- sincronização inteira.
SELECT pg_temp.checar('C', 'quantidade preenchida vence horas e área',
  producao_consolidada(7, 'HT', 1, 99, 50, 50) = 7,
  'a quantidade deixou de ter prioridade na fórmula');

SELECT pg_temp.checar('C', 'sem medida nenhuma, a produção é nula (não zero)',
  producao_consolidada(NULL, 'M³', NULL, NULL, NULL, NULL) IS NULL,
  'zero seria lido como "produziu nada", e o certo é "não dá para calcular"');

-- ============================================================================
-- SEÇÃO C (continuação) — Descrição (Tarifa): salvar_descricao_tarifa
-- ============================================================================
-- Cadastros ganhou uma guia de verdade para gerenciar descrição/código/
-- unidade/valor das tarifas (17/09, pedido do Fábio: "para quando mudar um
-- valor de uma atividade, podermos gerenciar isso nos cadastros"). Não dava
-- pra reaproveitar salvar_cadastro: ela chama normalizar_texto_cadastro, que
-- tira acento ("M³" viraria "M3") e quebraria a chave que
-- formulario_descricao e campos_ocultos_descricao usam para achar a
-- descrição. salvar_descricao_tarifa grava o cadastro e a tarifa
-- (regras_negocio) juntos, preservando o texto exato.
DO $secao_c_tarifa$
DECLARE
  v_uid    uuid;
  v_ret    jsonb;
  v_id     uuid;
  v_texto  text;
  v_ativo  boolean;
  v_tarifa jsonb;
BEGIN
  SELECT id INTO v_uid FROM auth.users ORDER BY created_at LIMIT 1;
  IF v_uid IS NULL THEN
    PERFORM pg_temp.pular('C', 'salvar_descricao_tarifa', 'auth.users vazia');
    RETURN;
  END IF;

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);

  -- criar, com acento e minúscula de propósito
  v_ret := salvar_descricao_tarifa(NULL, 'teste bateria âçãocriação - un', '99001', 'UN', 55.5, true);
  v_id := (v_ret->>'id')::uuid;
  SELECT valor INTO v_texto FROM cadastros WHERE id = v_id;
  PERFORM pg_temp.checar('C', 'tarifa: cria preservando acento e maiúscula',
    v_texto = 'TESTE BATERIA ÂÇÃOCRIAÇÃO - UN', 'gravou: ' || coalesce(v_texto, 'NULL'));

  SELECT valor INTO v_tarifa FROM regras_negocio WHERE tipo_regra = 'tarifa_descricao' AND chave = v_texto;
  PERFORM pg_temp.checar('C', 'tarifa: regras_negocio grava com a MESMA chave',
    v_tarifa->>'codigo' = '99001' AND v_tarifa->>'unidade' = 'UN' AND (v_tarifa->>'valor_unitario')::numeric = 55.5,
    'tarifa: ' || coalesce(v_tarifa::text, 'NULL'));

  -- editar: código/unidade/valor mudam, descrição NÃO muda mesmo mandando outro texto
  PERFORM salvar_descricao_tarifa(v_id, 'TEXTO QUE DEVERIA SER IGNORADO', '99002', 'HT', 77.7, true);
  SELECT valor INTO v_texto FROM cadastros WHERE id = v_id;
  PERFORM pg_temp.checar('C', 'tarifa: editar NÃO renomeia a descrição',
    v_texto = 'TESTE BATERIA ÂÇÃOCRIAÇÃO - UN', 'virou: ' || coalesce(v_texto, 'NULL'));
  SELECT r.valor INTO v_tarifa FROM regras_negocio r WHERE r.tipo_regra = 'tarifa_descricao' AND r.chave = v_texto;
  PERFORM pg_temp.checar('C', 'tarifa: editar troca código/unidade/valor',
    v_tarifa->>'codigo' = '99002' AND v_tarifa->>'unidade' = 'HT' AND (v_tarifa->>'valor_unitario')::numeric = 77.7,
    'tarifa depois de editar: ' || coalesce(v_tarifa::text, 'NULL'));

  -- desativar reaproveita excluir_cadastro (genérico) -- só toca `ativo`,
  -- seguro pra qualquer categoria, conferido lendo o corpo da função.
  PERFORM excluir_cadastro(v_id);
  SELECT ativo INTO v_ativo FROM cadastros WHERE id = v_id;
  PERFORM pg_temp.checar('C', 'tarifa: excluir_cadastro desativa', v_ativo = false);

  -- reativar via salvar_descricao_tarifa -- o caso crítico: acento sobrevive
  -- (reativar pelo salvar_cadastro genérico normalizaria e perderia)
  PERFORM salvar_descricao_tarifa(v_id, NULL, '99002', 'HT', 77.7, true);
  SELECT valor, ativo INTO v_texto, v_ativo FROM cadastros WHERE id = v_id;
  PERFORM pg_temp.checar('C', 'tarifa: reativar preserva o acento',
    v_ativo = true AND v_texto = 'TESTE BATERIA ÂÇÃOCRIAÇÃO - UN',
    'valor=' || coalesce(v_texto,'NULL') || ' ativo=' || v_ativo);

  BEGIN
    PERFORM salvar_descricao_tarifa(NULL, v_texto, '99003', 'UN', 1, true);
    PERFORM pg_temp.checar('C', 'tarifa: duplicata é recusada', false, 'não falhou -- criou duplicata');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'tarifa: duplicata é recusada', true);
  END;

  BEGIN
    PERFORM salvar_descricao_tarifa(NULL, 'TESTE BATERIA OUTRO ITEM - UN', '99004', 'UN', 0, true);
    PERFORM pg_temp.checar('C', 'tarifa: valor zero é recusado', false, 'não falhou');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'tarifa: valor zero é recusado', true);
  END;

  BEGIN
    PERFORM salvar_descricao_tarifa(NULL, 'TESTE BATERIA OUTRO ITEM 2 - UN', '', 'UN', 10, true);
    PERFORM pg_temp.checar('C', 'tarifa: sem código é recusado', false, 'não falhou');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'tarifa: sem código é recusado', true);
  END;

  PERFORM set_config('request.jwt.claims', '', true);
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.checar('C', 'salvar_descricao_tarifa', false, SQLERRM);
END $secao_c_tarifa$;

-- ============================================================================
-- SEÇÃO C (continuação) — editar pelo painel + devolução individual (17/09)
-- ============================================================================
-- Dois pedidos do Fábio: (1) corrigir um apontamento direto no painel, sem
-- devolver pro PWA por causa de um detalhe; (2) quando o apontamento tem
-- várias produções (linha "irmã"), deixar claro QUAL delas foi apontada.
--
-- A devolução individual nasceu apontando um ÍNDICE (posição na lista) e foi
-- CORRIGIDA ainda no mesmo dia: índice não sobrevive a nada, porque
-- atividade_maquinas era apagada e recriada inteira a cada sincronização (id
-- novo toda vez) -- ORDER BY m.id nem preservava a ordem que o operador
-- cadastrou. A versão de verdade aponta pelo UUID DE DISPOSITIVO da máquina
-- (uuid_maquina_dispositivo), que agora sobrevive a sincronizações porque
-- sincronizar_relatorio_rdo faz upsert por esse uuid em vez de apaga-e-recria.
-- O overload por índice (uuid,text,integer) fica no banco sem uso, testado
-- à parte (seção B); os testes de comportamento abaixo já usam só o de uuid.
DO $secao_c_edicao$
DECLARE
  v_uid    uuid;
  v_rel    uuid := gen_random_uuid();
  v_muid_a uuid := gen_random_uuid();
  v_muid_b uuid := gen_random_uuid();
  v_aid    uuid;
  v_ret    jsonb;
  v_st     text;
  v_ed     timestamptz;
  v_edpor  uuid;
  v_mmuid  uuid;
  v_mot    text;
  v_comp   numeric;
  v_id_maq1 uuid;
  v_id_maq2 uuid;
BEGIN
  SELECT id INTO v_uid FROM auth.users ORDER BY created_at LIMIT 1;
  IF v_uid IS NULL THEN
    PERFORM pg_temp.pular('C', 'editar pelo painel + devolução individual', 'auth.users vazia');
    RETURN;
  END IF;

  -- Duas máquinas de propósito, cada uma com seu uuid de dispositivo -- é o
  -- caso da "linha irmã", o que dá sentido a apontar UMA delas na devolução.
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  PERFORM sincronizar_relatorio_rdo(jsonb_build_object('uuid_dispositivo', v_rel,
    'cliente','Colheita','contrato','ARAUCO','faena','TESTE EDICAO PAINEL','tipo_estrada','Acesso',
    'equipe_frente','GTM','fazenda','Elo Dourado 2','data','2026-09-17','encarregado','Elson',
    'supervisor','Valmir','tecnico_arauco','Edwilson','supervisor_arauco','Luciano','concluidoEm', now(),
    'atividades', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(),
      'tipo_atividade','Construção de Aterro','comprimento_m',10,'largura_m',4,
      'observacao','ORIGINAL',
      'maquinas', jsonb_build_array(
        jsonb_build_object('id', v_muid_a, 'equipamento','ESH-18','operador','Leandro Félix',
          'dados', jsonb_build_object('quantidade', 5)),
        jsonb_build_object('id', v_muid_b, 'equipamento','MN-16','operador','Silvanei Costa',
          'dados', jsonb_build_object('quantidade', 8))
      )))));
  SELECT a.id INTO v_aid
    FROM atividades a JOIN relatorios r ON r.id = a.relatorio_id
   WHERE r.uuid_dispositivo = v_rel;
  SELECT id INTO v_id_maq1 FROM atividade_maquinas WHERE atividade_id = v_aid AND uuid_maquina_dispositivo = v_muid_a;

  -- --- editar_atividade_rdo é ação de painel: sem 2FA não passa ---
  BEGIN
    PERFORM editar_atividade_rdo(v_aid, 'Construção de Aterro', NULL, NULL, NULL, NULL,
                                 NULL, 11, 4, NULL, NULL, NULL, 'ORIGINAL');
    PERFORM pg_temp.checar('C', 'editar sem 2FA é recusado', false,
      'passou -- exige_mfa() não está barrando a edição pelo painel');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'editar sem 2FA é recusado', true, SQLERRM);
  END;

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);

  -- --- tipo de atividade é o mínimo: sem ele o apontamento não identifica nada ---
  BEGIN
    PERFORM editar_atividade_rdo(v_aid, '   ', NULL, NULL, NULL, NULL,
                                 NULL, 11, 4, NULL, NULL, NULL, 'ORIGINAL');
    PERFORM pg_temp.checar('C', 'editar sem tipo de atividade é recusado', false, 'passou');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'editar sem tipo de atividade é recusado',
      SQLERRM ILIKE '%obrigat%', SQLERRM);
  END;

  -- --- salvar SEM mudar nada não carimba "editado no painel" ---
  -- O selo avisa o revisor seguinte que os números não são mais os que o campo
  -- mandou. Se abrir o formulário, olhar e salvar já carimbasse, o selo
  -- apareceria em apontamento intocado -- e selo que aparece à toa deixa de ser
  -- lido quando aparece de verdade.
  --
  -- Testado pela AUSÊNCIA do carimbo, não comparando dois timestamps: `now()`
  -- devolve o mesmo valor durante toda a transação, então "antes == depois"
  -- seria verdade mesmo se a função regravasse a cada chamada. A primeira
  -- versão deste teste caiu nessa e passou verde com a função sabotada.
  -- A atividade acabou de ser criada, então editado_em é NULL aqui; os
  -- parâmetros abaixo repetem exatamente o que ela já tem.
  PERFORM editar_atividade_rdo(v_aid, 'Construção de Aterro', NULL, NULL, NULL, NULL,
                               NULL, 10, 4, NULL, NULL, NULL, 'ORIGINAL');
  SELECT editado_em INTO v_ed FROM atividades WHERE id = v_aid;
  PERFORM pg_temp.checar('C', 'salvar sem mudar nada NÃO carimba a edição',
    v_ed IS NULL,
    'editado_em foi gravado numa edição que não alterou dado nenhum');

  -- --- caminho feliz: pendente continua pendente, e fica o carimbo de quem editou ---
  v_ret := editar_atividade_rdo(v_aid, 'Construção de Aterro', NULL, NULL, NULL, NULL,
                                NULL, 12, 4, NULL, NULL, NULL, 'EDITADO PELO PAINEL');
  SELECT status_revisao, editado_em, editado_por, comprimento_m, observacao
    INTO v_st, v_ed, v_edpor, v_comp, v_mot
    FROM atividades WHERE id = v_aid;
  PERFORM pg_temp.checar('C', 'editar grava o valor novo',
    v_comp = 12 AND v_mot = 'EDITADO PELO PAINEL',
    'comprimento=' || coalesce(v_comp::text,'NULL') || ' obs=' || coalesce(v_mot,'NULL'));
  PERFORM pg_temp.checar('C', 'editar carimba editado_por/editado_em',
    v_ed IS NOT NULL AND v_edpor = v_uid);
  PERFORM pg_temp.checar('C', 'editar um pendente não muda o status',
    v_st = 'pendente', 'status = ' || coalesce(v_st,'NULL'));
  PERFORM pg_temp.checar('C', 'editar um pendente não diz que voltou pra pendente',
    (v_ret->>'voltou_pendente')::boolean = false, v_ret::text);

  -- --- validado + edição que NÃO muda nada => segue validado (sem falso alarme) ---
  PERFORM validar_atividade_rdo(v_aid);
  v_ret := editar_atividade_rdo(v_aid, 'Construção de Aterro', NULL, NULL, NULL, NULL,
                                NULL, 12, 4, NULL, NULL, NULL, 'EDITADO PELO PAINEL');
  SELECT status_revisao INTO v_st FROM atividades WHERE id = v_aid;
  PERFORM pg_temp.checar('C', 'editar validado SEM mudar nada mantém validado',
    v_st = 'validado', 'status = ' || coalesce(v_st,'NULL'));
  PERFORM pg_temp.checar('C', 'e a resposta não diz que voltou pra pendente',
    (v_ret->>'voltou_pendente')::boolean = false, v_ret::text);

  -- --- validado + mudança de verdade => volta pra pendente ---
  -- Mesmo princípio do furo "validado que muda sozinho" (C9): não faz sentido
  -- seguir aprovado com número diferente do que foi aprovado -- e vale também
  -- quando a mudança vem do próprio painel, não só do reenvio do campo.
  v_ret := editar_atividade_rdo(v_aid, 'Construção de Aterro', NULL, NULL, NULL, NULL,
                                NULL, 99, 4, NULL, NULL, NULL, 'EDITADO PELO PAINEL');
  SELECT status_revisao INTO v_st FROM atividades WHERE id = v_aid;
  PERFORM pg_temp.checar('C', 'editar validado MUDANDO medida volta pra pendente',
    v_st = 'pendente', 'status = ' || coalesce(v_st,'NULL'));
  PERFORM pg_temp.checar('C', 'e a resposta avisa que voltou pra pendente',
    (v_ret->>'voltou_pendente')::boolean = true, v_ret::text);

  -- --- uuid de máquina que não pertence à atividade é recusado ---
  -- Testado ANTES da primeira devolução de propósito: com a atividade já
  -- 'pendente', é a validação de posse da máquina que tem de barrar -- feito
  -- depois de já devolvida, quem barraria primeiro seria a trava de
  -- alternância (também correta, mas não é o que este teste quer isolar).
  -- Sem esta checagem, um id de OUTRA atividade (ou inventado) travaria a
  -- edição errada no PWA sem ninguém perceber até o encarregado reclamar.
  BEGIN
    PERFORM devolver_atividade_rdo(p_atividade_id => v_aid,
      p_motivo => 'nunca deveria funcionar', p_maquina_uuid => gen_random_uuid());
    PERFORM pg_temp.checar('C', 'devolver com uuid de outra atividade é recusado', false, 'passou');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'devolver com uuid de outra atividade é recusado',
      SQLERRM ILIKE '%não pertence%', SQLERRM);
  END;

  -- --- devolução individual: guarda QUAL produção foi apontada, pelo uuid ---
  -- Chamada NOMEADA de propósito: é como o Supabase RPC sempre chama (o
  -- corpo JSON vira parâmetros nomeados), e é o que desambigua entre os dois
  -- overloads de 3 parâmetros quando o valor é NULL -- POSICIONAL um NULL
  -- seria ambíguo entre (uuid,text,integer) e (uuid,text,uuid).
  PERFORM devolver_atividade_rdo(p_atividade_id => v_aid,
    p_motivo => 'A segunda máquina está com quantidade errada', p_maquina_uuid => v_muid_b);
  SELECT status_revisao, producao_devolvida_maquina_uuid, motivo_devolucao
    INTO v_st, v_mmuid, v_mot FROM atividades WHERE id = v_aid;
  PERFORM pg_temp.checar('C', 'devolver com uuid grava qual produção foi apontada',
    v_st = 'devolvido' AND v_mmuid = v_muid_b,
    'status=' || coalesce(v_st,'NULL') || ' maquina=' || coalesce(v_mmuid::text,'NULL'));

  -- --- o painel precisa receber o uuid, senão não desenha a distinção ---
  PERFORM pg_temp.checar('C', 'listar_relatorios_painel devolve producao_devolvida_maquina_uuid',
    EXISTS (
      SELECT 1
      FROM jsonb_array_elements(listar_relatorios_painel(NULL, NULL, NULL, NULL, 200)) rel,
           jsonb_array_elements(rel->'atividades') ativ
      WHERE (ativ->>'id')::uuid = v_aid
        AND (ativ->>'producao_devolvida_maquina_uuid')::uuid = v_muid_b
    ));

  -- --- e cada produção precisa vir com o PRÓPRIO uuid, senão o painel não
  --     tem com o que comparar linha por linha ---
  PERFORM pg_temp.checar('C', 'listar_relatorios_painel expõe maquina_uuid em cada produção',
    (SELECT count(*) FROM (
      SELECT DISTINCT prod->>'maquina_uuid' AS mu
      FROM jsonb_array_elements(listar_relatorios_painel(NULL, NULL, NULL, NULL, 200)) rel,
           jsonb_array_elements(rel->'atividades') ativ,
           jsonb_array_elements(ativ->'producoes') prod
      WHERE (ativ->>'id')::uuid = v_aid
    ) t) = 2,
    'esperava 2 uuids de máquina distintos (uma por produção)');

  PERFORM pg_temp.checar('C', 'listar_relatorios_painel devolve editado_em/editado_por',
    EXISTS (
      SELECT 1
      FROM jsonb_array_elements(listar_relatorios_painel(NULL, NULL, NULL, NULL, 200)) rel,
           jsonb_array_elements(rel->'atividades') ativ
      WHERE (ativ->>'id')::uuid = v_aid
        AND ativ->>'editado_em' IS NOT NULL
        AND ativ->>'editado_por' IS NOT NULL
    ));

  -- --- devolvido está em trânsito com o campo: o painel não edita por cima ---
  BEGIN
    PERFORM editar_atividade_rdo(v_aid, 'Construção de Aterro', NULL, NULL, NULL, NULL,
                                 NULL, 50, 4, NULL, NULL, NULL, 'NAO DEVERIA ENTRAR');
    PERFORM pg_temp.checar('C', 'editar um DEVOLVIDO é recusado', false,
      'passou -- o painel sobrescreveria o que o encarregado está corrigindo');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'editar um DEVOLVIDO é recusado', true, SQLERRM);
  END;

  -- --- a trava de alternância continua valendo com o overload novo ---
  BEGIN
    PERFORM devolver_atividade_rdo(p_atividade_id => v_aid,
      p_motivo => 'Outra devolução seguida', p_maquina_uuid => v_muid_a);
    PERFORM pg_temp.checar('C', 'devolver DUAS VEZES seguidas é recusado (com uuid)', false,
      'passou -- geraria outro push pro mesmo pedido');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'devolver DUAS VEZES seguidas é recusado (com uuid)', true, SQLERRM);
  END;

  -- --- o reenvio do campo apaga o retrato, no mesmo instante em que ele
  --     deixa de ser verdade -- e o upsert preserva o id real das máquinas
  --     que não mudaram (é o que faz a identidade sobreviver de verdade,
  --     ao contrário do índice antigo) ---
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  PERFORM sincronizar_relatorio_rdo(jsonb_build_object('uuid_dispositivo', v_rel,
    'cliente','Colheita','contrato','ARAUCO','faena','TESTE EDICAO PAINEL','tipo_estrada','Acesso',
    'equipe_frente','GTM','fazenda','Elo Dourado 2','data','2026-09-17','encarregado','Elson',
    'supervisor','Valmir','tecnico_arauco','Edwilson','supervisor_arauco','Luciano','concluidoEm', now(),
    'atividades', jsonb_build_array(jsonb_build_object(
      'id', (SELECT uuid_atividade_dispositivo FROM atividades WHERE id = v_aid),
      'tipo_atividade','Construção de Aterro','comprimento_m',10,'largura_m',4,
      'observacao','CORRIGIDO NO CAMPO',
      -- mesmo uuid da máquina A, quantidade corrigida; a B foi removida no
      -- aparelho (encarregado decidiu que não precisava mais dela).
      'maquinas', jsonb_build_array(
        jsonb_build_object('id', v_muid_a, 'equipamento','ESH-18','operador','Leandro Félix',
          'dados', jsonb_build_object('quantidade', 6))
      )))));
  SELECT status_revisao, producao_devolvida_maquina_uuid, motivo_devolucao
    INTO v_st, v_mmuid, v_mot FROM atividades WHERE id = v_aid;
  PERFORM pg_temp.checar('C', 'reenvio limpa o uuid da produção devolvida',
    v_mmuid IS NULL, 'uuid = ' || coalesce(v_mmuid::text,'NULL'));
  PERFORM pg_temp.checar('C', 'reenvio também limpa o motivo e volta pra pendente',
    v_st = 'pendente' AND v_mot IS NULL,
    'status=' || coalesce(v_st,'NULL') || ' motivo=' || coalesce(v_mot,'NULL'));

  SELECT id INTO v_id_maq2 FROM atividade_maquinas WHERE atividade_id = v_aid AND uuid_maquina_dispositivo = v_muid_a;
  PERFORM pg_temp.checar('C', 'upsert preserva o id real da máquina que não mudou',
    v_id_maq2 IS NOT NULL AND v_id_maq2 = v_id_maq1,
    'id antes=' || coalesce(v_id_maq1::text,'NULL') || ' id depois=' || coalesce(v_id_maq2::text,'NULL'));
  -- 18/09: deixou de ser DELETE literal -- a máquina removida no aparelho
  -- agora é MARCADA (excluido_em), não apagada. Ver protecao_exclusao_devolucao.sql
  -- e a seção C dedicada ("proteção contra perda de evidência numa devolução").
  PERFORM pg_temp.checar('C', 'a máquina removida no aparelho é marcada, não apagada do banco',
    EXISTS (SELECT 1 FROM atividade_maquinas
             WHERE atividade_id = v_aid AND uuid_maquina_dispositivo = v_muid_b AND excluido_em IS NOT NULL));

  -- --- REGRESSÃO do overload de 2 parâmetros: continua no ar, mesmo sem uso ---
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  PERFORM devolver_atividade_rdo(v_aid, 'Devolução sem apontar produção');
  SELECT status_revisao, producao_devolvida_maquina_uuid INTO v_st, v_mmuid
    FROM atividades WHERE id = v_aid;
  PERFORM pg_temp.checar('C', 'devolver com 2 parâmetros continua funcionando',
    v_st = 'devolvido', 'status = ' || coalesce(v_st,'NULL'));
  PERFORM pg_temp.checar('C', 'e deixa o uuid da produção nulo (devolução do apontamento inteiro)',
    v_mmuid IS NULL, 'uuid = ' || coalesce(v_mmuid::text,'NULL'));

  PERFORM set_config('request.jwt.claims', '', true);
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.checar('C', 'editar pelo painel + devolução individual', false, SQLERRM);
END $secao_c_edicao$;

-- ----------------------------------------------------------------------------
-- Retenção local do PWA (18/09): depois de 30 dias sincronizado e sem
-- correção pendente, o aparelho apaga o relatório sozinho
-- (PWA/RDO/RDO/index.html, podarRelatoriosAntigos). Devolver um apontamento
-- passado esse prazo poderia apontar pra um dado que já não existe mais no
-- aparelho -- a notificação chegaria sem ter o que corrigir. O botão
-- desabilitado no painel é conveniência; quem garante de verdade é esta
-- checagem em devolver_atividade_rdo, mesmo padrão da alternância obrigatória.
-- ----------------------------------------------------------------------------
DO $secao_c_retencao$
DECLARE
  v_uid uuid;
  v_rel_uuid_velha  uuid := gen_random_uuid();
  v_rel_uuid_nova   uuid := gen_random_uuid();
  v_ativ_uuid_velha uuid := gen_random_uuid();
  v_ativ_uuid_nova  uuid := gen_random_uuid();
  v_payload jsonb;
  v_rel_id_velha uuid;
  v_rel_id_nova  uuid;
  v_aid_velha uuid;
  v_aid_nova  uuid;
  v_st text;
BEGIN
  SELECT id INTO v_uid FROM auth.users ORDER BY created_at LIMIT 1;

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);

  v_payload := jsonb_build_object(
    'uuid_dispositivo', v_rel_uuid_velha,
    'cliente', 'Colheita', 'contrato', 'ARAUCO', 'faena', 'TESTE RETENCAO',
    'tipo_estrada', 'Acesso', 'equipe_frente', 'GTM - Teste',
    'fazenda', 'Elo Dourado 2', 'data', '2026-08-01',
    'encarregado', 'Elson', 'supervisor', 'Valmir',
    'tecnico_arauco', 'Edwilson', 'supervisor_arauco', 'Luciano',
    'atividades', jsonb_build_array(jsonb_build_object(
      'id', v_ativ_uuid_velha, 'tipo_atividade', 'TESTE RETENCAO VELHO'
    ))
  );
  PERFORM sincronizar_relatorio_rdo(v_payload);

  v_payload := jsonb_build_object(
    'uuid_dispositivo', v_rel_uuid_nova,
    'cliente', 'Colheita', 'contrato', 'ARAUCO', 'faena', 'TESTE RETENCAO',
    'tipo_estrada', 'Acesso', 'equipe_frente', 'GTM - Teste',
    'fazenda', 'Elo Dourado 2', 'data', '2026-09-17',
    'encarregado', 'Elson', 'supervisor', 'Valmir',
    'tecnico_arauco', 'Edwilson', 'supervisor_arauco', 'Luciano',
    'atividades', jsonb_build_array(jsonb_build_object(
      'id', v_ativ_uuid_nova, 'tipo_atividade', 'TESTE RETENCAO NOVO'
    ))
  );
  PERFORM sincronizar_relatorio_rdo(v_payload);

  SELECT id INTO v_rel_id_velha FROM relatorios WHERE uuid_dispositivo = v_rel_uuid_velha;
  SELECT id INTO v_rel_id_nova  FROM relatorios WHERE uuid_dispositivo = v_rel_uuid_nova;
  SELECT id INTO v_aid_velha FROM atividades WHERE relatorio_id = v_rel_id_velha;
  SELECT id INTO v_aid_nova  FROM atividades WHERE relatorio_id = v_rel_id_nova;

  -- Simula os 31 dias sem esperar 31 dias.
  UPDATE relatorios SET sincronizado_em = now() - interval '31 days' WHERE id = v_rel_id_velha;

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);

  BEGIN
    PERFORM devolver_atividade_rdo(p_atividade_id => v_aid_velha, p_motivo => 'teste', p_maquina_uuid => NULL::uuid);
    PERFORM pg_temp.checar('C', 'devolver (overload uuid) recusa apontamento sincronizado há mais de 30 dias', false,
      'deveria ter recusado e não recusou');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'devolver (overload uuid) recusa apontamento sincronizado há mais de 30 dias',
      SQLERRM LIKE '%sincronizado há mais de 30 dias%', SQLERRM);
  END;

  BEGIN
    PERFORM devolver_atividade_rdo(p_atividade_id => v_aid_velha, p_motivo => 'teste', p_indice_producao => NULL::integer);
    PERFORM pg_temp.checar('C', 'devolver (overload integer, ainda existe mas morto) também recusa', false,
      'deveria ter recusado e não recusou');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'devolver (overload integer, ainda existe mas morto) também recusa',
      SQLERRM LIKE '%sincronizado há mais de 30 dias%', SQLERRM);
  END;

  BEGIN
    PERFORM devolver_atividade_rdo(v_aid_velha, 'teste');
    PERFORM pg_temp.checar('C', 'devolver (wrapper de 2 parâmetros) também recusa', false,
      'deveria ter recusado e não recusou');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'devolver (wrapper de 2 parâmetros) também recusa',
      SQLERRM LIKE '%sincronizado há mais de 30 dias%', SQLERRM);
  END;

  -- O recente (sincronizado agora, pelo DEFAULT now() da coluna) continua
  -- funcionando normalmente -- a trava não pode pegar quem está dentro do prazo.
  PERFORM devolver_atividade_rdo(p_atividade_id => v_aid_nova, p_motivo => 'teste ok', p_maquina_uuid => NULL::uuid);
  SELECT status_revisao INTO v_st FROM atividades WHERE id = v_aid_nova;
  PERFORM pg_temp.checar('C', 'devolver um apontamento recente continua funcionando normalmente',
    v_st = 'devolvido', 'status = ' || coalesce(v_st, 'NULL'));

  PERFORM set_config('request.jwt.claims', '', true);
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.checar('C', 'retenção local: trava de 30 dias em devolver_atividade_rdo', false, SQLERRM);
END $secao_c_retencao$;

-- ----------------------------------------------------------------------------
-- Reconstrução local a partir do servidor (18/09): o PWA usa isto quando o
-- IndexedDB some por um motivo que não é a poda (cache/dados do site
-- limpos, aparelho trocado) -- o que já subiu pro banco não pode ficar
-- irrecuperável só por isso.
-- ----------------------------------------------------------------------------
DO $secao_c_reconstrucao$
DECLARE
  v_uid uuid;
  v_uid_outro uuid;
  v_rel_uuid uuid := gen_random_uuid();
  v_ativ_uuid uuid := gen_random_uuid();
  v_ativ_excluida_uuid uuid := gen_random_uuid();
  v_muid_a uuid := gen_random_uuid();
  v_muid_b uuid := gen_random_uuid();
  v_payload jsonb;
  v_ativ_excluida_id uuid;
  v_resultado jsonb;
  v_rel_out jsonb;
  v_ativ_out jsonb;
  v_maq_a jsonb;
  v_maq_b jsonb;
BEGIN
  SELECT id INTO v_uid FROM auth.users ORDER BY created_at LIMIT 1;
  SELECT id INTO v_uid_outro FROM auth.users WHERE id <> v_uid ORDER BY created_at LIMIT 1;
  IF v_uid IS NULL THEN
    PERFORM pg_temp.pular('C', 'reconstrução local a partir do servidor', 'auth.users vazia');
    RETURN;
  END IF;

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);

  v_payload := jsonb_build_object(
    'uuid_dispositivo', v_rel_uuid,
    'cliente', 'Colheita', 'contrato', 'ARAUCO', 'faena', 'TESTE RECONSTRUCAO',
    'tipo_estrada', 'Acesso', 'equipe_frente', 'GTM - Teste',
    'fazenda', 'Elo Dourado 2', 'data', '2026-09-01',
    'encarregado', 'Elson', 'supervisor', 'Valmir',
    'tecnico_arauco', 'Edwilson', 'supervisor_arauco', 'Luciano',
    'criadoEm', now(), 'concluidoEm', now(),
    'atividades', jsonb_build_array(
      jsonb_build_object(
        'id', v_ativ_uuid, 'tipo_atividade', 'PÁ CARREGADEIRA - HT',
        'maquinas', jsonb_build_array(
          jsonb_build_object('id', v_muid_a, 'equipamento', 'PC-19', 'operador', 'RICARDO',
            'dados', jsonb_build_object('hora_inicial', 7.5, 'hora_final', 12)),
          jsonb_build_object('id', v_muid_b, 'equipamento', 'MN-16', 'operador', 'SILVANEI',
            'dados', jsonb_build_object('hora_inicial', 8, 'hora_final', 16))
        ),
        'fotos', jsonb_build_array(jsonb_build_object('storage_path', 'teste/evidencia-reconstrucao.jpg'))
      ),
      jsonb_build_object('id', v_ativ_excluida_uuid, 'tipo_atividade', 'ESTA SOME DEPOIS')
    )
  );
  PERFORM sincronizar_relatorio_rdo(v_payload);

  -- 18/09: omitir uma atividade devolvida do payload deixou de marcar
  -- excluido_em (ver protecao_exclusao_devolucao.sql) -- não existe mais
  -- caminho normal que produza uma atividade excluída a partir daqui. Para
  -- este teste especificamente (reconstrução não pode ressuscitar dado
  -- excluído), simula-se uma exclusão HISTÓRICA -- de antes desta mudança
  -- de regra -- com um UPDATE direto, e confirma que a reconstrução
  -- continua respeitando esse registro antigo.
  -- status_revisao = 'devolvido' junto: é o invariante que SEMPRE valeu até
  -- esta mudança (só se excluía omitindo uma atividade devolvida) -- a
  -- seção D tem um teste dedicado que cobra justamente isso, e a simulação
  -- precisa respeitar o mesmo formato do dado real que existia antes.
  SELECT id INTO v_ativ_excluida_id FROM atividades WHERE uuid_atividade_dispositivo = v_ativ_excluida_uuid;
  UPDATE atividades SET excluido_em = now(), excluido_por = v_uid, status_revisao = 'devolvido'
   WHERE id = v_ativ_excluida_id;

  SELECT listar_meus_relatorios_pwa() INTO v_resultado;
  SELECT r INTO v_rel_out FROM jsonb_array_elements(v_resultado) r WHERE (r->>'id')::uuid = v_rel_uuid;

  PERFORM pg_temp.checar('C', 'reconstrução: achou o relatório do próprio usuário', v_rel_out IS NOT NULL);
  PERFORM pg_temp.checar('C', 'reconstrução: campo "data" no formato local (não data_relatorio)',
    v_rel_out->>'data' = '2026-09-01', coalesce(v_rel_out->>'data', 'NULL'));
  PERFORM pg_temp.checar('C', 'reconstrução: rpcSincronizado=true e status=concluido',
    (v_rel_out->>'rpcSincronizado')::boolean = true AND v_rel_out->>'status' = 'concluido');
  PERFORM pg_temp.checar('C', 'reconstrução: sincronizadoEm preenchido (usado pela poda de 30 dias no PWA)',
    v_rel_out->>'sincronizadoEm' IS NOT NULL);
  PERFORM pg_temp.checar('C', 'reconstrução: atividade excluída no aparelho não volta',
    jsonb_array_length(v_rel_out->'atividades') = 1,
    'esperava 1, veio ' || jsonb_array_length(v_rel_out->'atividades'));

  SELECT a INTO v_ativ_out FROM jsonb_array_elements(v_rel_out->'atividades') a WHERE (a->>'id')::uuid = v_ativ_uuid;
  PERFORM pg_temp.checar('C', 'reconstrução: atividade com o id do dispositivo', v_ativ_out IS NOT NULL);
  PERFORM pg_temp.checar('C', 'reconstrução: enviadaEm preenchido (trava de excluir/editar)',
    v_ativ_out->>'enviadaEm' IS NOT NULL);

  SELECT m INTO v_maq_a FROM jsonb_array_elements(v_ativ_out->'maquinas') m WHERE (m->>'id')::uuid = v_muid_a;
  SELECT m INTO v_maq_b FROM jsonb_array_elements(v_ativ_out->'maquinas') m WHERE (m->>'id')::uuid = v_muid_b;
  PERFORM pg_temp.checar('C',
    'reconstrução: as duas máquinas voltam com o MESMO id de dispositivo (é o que a trava de edição do PWA compara)',
    v_maq_a IS NOT NULL AND v_maq_b IS NOT NULL);
  PERFORM pg_temp.checar('C', 'reconstrução: dados da máquina vêm achatados (hora_inicial no nível certo, não dentro de "dados")',
    (v_maq_a->>'hora_inicial')::numeric = 7.5 AND (v_maq_a->>'hora_final')::numeric = 12,
    coalesce(v_maq_a::text, 'NULL'));
  PERFORM pg_temp.checar('C', 'reconstrução: foto volta com storagePath em camelCase (formato local)',
    (v_ativ_out->'fotos'->0->>'storagePath') = 'teste/evidencia-reconstrucao.jpg');

  IF v_uid_outro IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims',
      jsonb_build_object('sub', v_uid_outro, 'role', 'authenticated', 'aal', 'aal1')::text, true);
    SELECT listar_meus_relatorios_pwa() INTO v_resultado;
    PERFORM pg_temp.checar('C', 'reconstrução: outro usuário NÃO vê este relatório (filtro por criado_por)',
      NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_resultado) r WHERE (r->>'id')::uuid = v_rel_uuid));
  ELSE
    PERFORM pg_temp.pular('C', 'reconstrução: outro usuário NÃO vê este relatório', 'só existe 1 usuário em auth.users');
  END IF;

  PERFORM set_config('request.jwt.claims', '', true);
  BEGIN
    PERFORM listar_meus_relatorios_pwa();
    PERFORM pg_temp.checar('C', 'reconstrução: sem login é recusado', false, 'a chamada passou');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'reconstrução: sem login é recusado', SQLERRM ILIKE '%logado%', SQLERRM);
  END;
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.checar('C', 'reconstrução local a partir do servidor', false, SQLERRM);
END $secao_c_reconstrucao$;

-- ----------------------------------------------------------------------------
-- Proteção contra perda de evidência numa devolução (18/09): produção
-- removida vira MARCA (não DELETE), e apagar um apontamento devolvido por
-- omissão no payload deixa de ser honrado pelo servidor.
-- ----------------------------------------------------------------------------
DO $secao_c_protecao$
DECLARE
  v_uid uuid;
  v_rel_uuid uuid := gen_random_uuid();
  v_ativ_uuid uuid := gen_random_uuid();
  v_ativ3_uuid uuid := gen_random_uuid();
  v_muid_a uuid := gen_random_uuid();
  v_muid_b uuid := gen_random_uuid();
  v_payload jsonb;
  v_payload_final jsonb;
  v_rel_id uuid;
  v_ativ_id uuid;
  v_ativ3_id uuid;
  v_resultado jsonb;
  v_prod jsonb;
  v_st text;
  v_excl timestamptz;
  v_resp jsonb;
BEGIN
  SELECT id INTO v_uid FROM auth.users ORDER BY created_at LIMIT 1;
  IF v_uid IS NULL THEN
    PERFORM pg_temp.pular('C', 'proteção contra perda de evidência numa devolução', 'auth.users vazia');
    RETURN;
  END IF;

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);

  v_payload := jsonb_build_object(
    'uuid_dispositivo', v_rel_uuid,
    'cliente', 'Colheita', 'contrato', 'ARAUCO', 'faena', 'TESTE PROTECAO',
    'tipo_estrada', 'Acesso', 'equipe_frente', 'GTM - Teste',
    'fazenda', 'Elo Dourado 2', 'data', '2026-09-18',
    'encarregado', 'Elson', 'supervisor', 'Valmir',
    'tecnico_arauco', 'Edwilson', 'supervisor_arauco', 'Luciano',
    'atividades', jsonb_build_array(
      jsonb_build_object('id', v_ativ_uuid, 'tipo_atividade', 'PÁ CARREGADEIRA - HT',
        'maquinas', jsonb_build_array(
          jsonb_build_object('id', v_muid_a, 'equipamento', 'PC-19', 'operador', 'RICARDO',
            'dados', jsonb_build_object('hora_inicial', 7, 'hora_final', 12)),
          jsonb_build_object('id', v_muid_b, 'equipamento', 'MN-16', 'operador', 'SILVANEI',
            'dados', jsonb_build_object('hora_inicial', 8, 'hora_final', 16))
        ))
    )
  );
  PERFORM sincronizar_relatorio_rdo(v_payload);
  SELECT id INTO v_rel_id FROM relatorios WHERE uuid_dispositivo = v_rel_uuid;
  SELECT id INTO v_ativ_id FROM atividades WHERE relatorio_id = v_rel_id AND uuid_atividade_dispositivo = v_ativ_uuid;

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  PERFORM devolver_atividade_rdo(p_atividade_id => v_ativ_id, p_motivo => 'teste', p_maquina_uuid => v_muid_a);

  -- Reenvio omitindo a máquina A -- ela é MARCADA, não apagada de verdade.
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  v_payload := jsonb_set(v_payload, '{atividades,0,maquinas}', jsonb_build_array(v_payload->'atividades'->0->'maquinas'->1));
  PERFORM sincronizar_relatorio_rdo(v_payload);

  PERFORM pg_temp.checar('C', 'produção removida continua existindo no banco (marcada, não apagada)',
    EXISTS (SELECT 1 FROM atividade_maquinas WHERE atividade_id = v_ativ_id AND uuid_maquina_dispositivo = v_muid_a));
  SELECT excluido_em INTO v_excl FROM atividade_maquinas WHERE atividade_id = v_ativ_id AND uuid_maquina_dispositivo = v_muid_a;
  PERFORM pg_temp.checar('C', 'produção removida tem excluido_em preenchido', v_excl IS NOT NULL);

  SELECT status_revisao INTO v_st FROM atividades WHERE id = v_ativ_id;
  PERFORM pg_temp.checar('C', 'reenvio de correção continua funcionando (atividade volta a pendente)',
    v_st = 'pendente', 'status = ' || coalesce(v_st, 'NULL'));

  -- Devolver apontando pra uma produção já removida é recusado.
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  BEGIN
    PERFORM devolver_atividade_rdo(p_atividade_id => v_ativ_id, p_motivo => 'teste',
      p_maquina_uuid => v_muid_a);
    PERFORM pg_temp.checar('C', 'devolver uma produção já removida é recusado', false, 'a chamada passou');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.checar('C', 'devolver uma produção já removida é recusado',
      SQLERRM LIKE '%já foi removida%', SQLERRM);
  END;

  -- O painel vê a produção removida (com excluido_em), não some da lista.
  SELECT listar_relatorios_painel(NULL,NULL,NULL,NULL,200) INTO v_resultado;
  SELECT p INTO v_prod
    FROM jsonb_array_elements(v_resultado) rel,
         jsonb_array_elements(rel->'atividades') ativ,
         jsonb_array_elements(ativ->'producoes') p
   WHERE (rel->>'id')::uuid = v_rel_id AND (ativ->>'id')::uuid = v_ativ_id
     AND p->>'maquina_uuid' = v_muid_a::text;
  PERFORM pg_temp.checar('C', 'painel enxerga a produção removida (não some da lista)', v_prod IS NOT NULL);
  PERFORM pg_temp.checar('C', 'a produção removida vem com excluido_em preenchido para o painel',
    v_prod IS NOT NULL AND v_prod->>'excluido_em' IS NOT NULL);

  SELECT p INTO v_prod
    FROM jsonb_array_elements(v_resultado) rel,
         jsonb_array_elements(rel->'atividades') ativ,
         jsonb_array_elements(ativ->'producoes') p
   WHERE (rel->>'id')::uuid = v_rel_id AND (ativ->>'id')::uuid = v_ativ_id
     AND p->>'maquina_uuid' = v_muid_b::text;
  PERFORM pg_temp.checar('C', 'produção NÃO removida continua sem excluido_em',
    v_prod IS NOT NULL AND v_prod->>'excluido_em' IS NULL);

  -- Reconstrução (PWA) não ressuscita a produção removida.
  SELECT listar_meus_relatorios_pwa() INTO v_resultado;
  PERFORM pg_temp.checar('C', 'reconstrução NÃO ressuscita a produção removida',
    NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_resultado) r,
                    jsonb_array_elements(r->'atividades') a,
                    jsonb_array_elements(a->'maquinas') m
       WHERE (r->>'id')::uuid = v_rel_uuid AND m->>'id' = v_muid_a::text
    ));

  -- Reenviar a MESMA máquina de novo limpa a marca de exclusão.
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  PERFORM devolver_atividade_rdo(p_atividade_id => v_ativ_id, p_motivo => 'de novo', p_maquina_uuid => NULL::uuid);
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  v_payload := jsonb_set(v_payload, '{atividades,0,maquinas}',
    jsonb_build_array(v_payload->'atividades'->0->'maquinas'->0,
      jsonb_build_object('id', v_muid_a, 'equipamento', 'PC-19', 'operador', 'RICARDO',
        'dados', jsonb_build_object('hora_inicial', 7, 'hora_final', 12))));
  PERFORM sincronizar_relatorio_rdo(v_payload);
  SELECT excluido_em INTO v_excl FROM atividade_maquinas WHERE atividade_id = v_ativ_id AND uuid_maquina_dispositivo = v_muid_a;
  PERFORM pg_temp.checar('C', 'recriar a mesma produção no aparelho limpa a marca de exclusão', v_excl IS NULL);

  -- Apagar um APONTAMENTO devolvido (omitir do payload) deixou de ser
  -- honrado -- atividade isolada, devolvida uma única vez, sem nenhum
  -- reenvio de correção no meio (que já desfaria o devolvido por outro
  -- caminho e confundiria o que este teste quer provar).
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  v_payload_final := jsonb_build_object(
    'uuid_dispositivo', v_rel_uuid,
    'cliente', 'Colheita', 'contrato', 'ARAUCO', 'faena', 'TESTE PROTECAO',
    'tipo_estrada', 'Acesso', 'equipe_frente', 'GTM - Teste',
    'fazenda', 'Elo Dourado 2', 'data', '2026-09-18',
    'encarregado', 'Elson', 'supervisor', 'Valmir',
    'tecnico_arauco', 'Edwilson', 'supervisor_arauco', 'Luciano',
    'atividades', jsonb_build_array(jsonb_build_object('id', v_ativ3_uuid, 'tipo_atividade', 'TESTE ATIVIDADE 3'))
  );
  PERFORM sincronizar_relatorio_rdo(v_payload_final);
  SELECT id INTO v_ativ3_id FROM atividades WHERE relatorio_id = v_rel_id AND uuid_atividade_dispositivo = v_ativ3_uuid;

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  PERFORM devolver_atividade_rdo(p_atividade_id => v_ativ3_id, p_motivo => 'teste', p_maquina_uuid => NULL::uuid);

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  v_payload_final := jsonb_set(v_payload_final, '{atividades}', '[]'::jsonb);
  v_resp := sincronizar_relatorio_rdo(v_payload_final);

  SELECT excluido_em, status_revisao INTO v_excl, v_st FROM atividades WHERE id = v_ativ3_id;
  PERFORM pg_temp.checar('C', 'omitir um apontamento DEVOLVIDO não marca mais excluido_em',
    v_excl IS NULL);
  PERFORM pg_temp.checar('C', 'e ele continua devolvido, intacto (não vira pendente nem some)',
    v_st = 'devolvido', 'status = ' || coalesce(v_st, 'NULL'));
  PERFORM pg_temp.checar('C', 'a tentativa de omitir é contabilizada em remocoes_negadas',
    (v_resp->>'remocoes_negadas')::int >= 1, 'veio ' || coalesce(v_resp->>'remocoes_negadas', 'NULL'));

  PERFORM set_config('request.jwt.claims', '', true);
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.checar('C', 'proteção contra perda de evidência numa devolução', false, SQLERRM);
END $secao_c_protecao$;

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

  -- ESTE é o teste que protege quem está em campo AGORA.
  --
  -- O payload acima não tem 'descricao_atividade' -- de propósito: é o payload
  -- do PWA publicado, que não conhece o campo. Se a coluna nova tivesse nascido
  -- NOT NULL, ou se a função exigisse a chave, toda sincronização de operador
  -- passaria a falhar e o RDO do dia ficaria preso no aparelho. Já aconteceu
  -- neste projeto, com uuid_atividade_dispositivo (ver ESTADO.md).
  PERFORM pg_temp.checar('D', 'RDO sem descrição de atividade continua sincronizando',
    v_qtd = 1,
    'o PWA que está em campo não manda esse campo: exigi-lo prende o dia de trabalho no aparelho');

  PERFORM pg_temp.checar('D', 'apontamento sem descrição fica com a coluna nula, não vazia',
    EXISTS (SELECT 1 FROM atividades a JOIN relatorios r ON r.id = a.relatorio_id
             WHERE r.uuid_dispositivo = v_uuid AND a.descricao_atividade IS NULL),
    'gravou string vazia em vez de NULL -- o LEFT JOIN da tarifa passaria a procurar por ""');

  PERFORM set_config('request.jwt.claims', '', true);
EXCEPTION WHEN OTHERS THEN
  -- Uma exceção aqui é a própria falha -- registra em vez de abortar a bateria.
  PERFORM pg_temp.checar('D', 'sincronizar um RDO completo continua funcionando',
    false, SQLERRM);
END $secao_d3$;

-- A marcação de exclusão (08/09) mexeu no mesmo UPDATE/DELETE que trata as
-- atividades vivas. Estes dois cobram que ela não tenha estragado o caminho
-- normal, que é o que roda todo dia: sincronizar um RDO com atividades e
-- reenviá-lo depois.
DO $secao_d4$
DECLARE
  v_uid uuid; v_uuid uuid := gen_random_uuid(); v_ativ uuid := gen_random_uuid();
  v_pay jsonb; v_rel_id uuid; v_vivas int; v_fotos int;
BEGIN
  SELECT id INTO v_uid FROM auth.users ORDER BY created_at LIMIT 1;
  IF v_uid IS NULL THEN RETURN; END IF;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub',v_uid,'role','authenticated','aal','aal1')::text, true);

  v_pay := jsonb_build_object(
    'uuid_dispositivo', v_uuid,
    'cliente','Colheita','contrato','ARAUCO','faena','TESTE REGRESSAO EXCLUSAO',
    'tipo_estrada','Acesso','equipe_frente','GTM','fazenda','Elo Dourado 2',
    'data','2026-09-08','encarregado','Elson','supervisor','Valmir',
    'tecnico_arauco','Edwilson','supervisor_arauco','Luciano','concluidoEm', now(),
    'atividades', jsonb_build_array(jsonb_build_object(
      'id', v_ativ, 'tipo_atividade','Limpeza de valeta','comprimento_m',100,
      'fotos', jsonb_build_array(jsonb_build_object('storage_path','teste/regressao.jpg')))));

  PERFORM sincronizar_relatorio_rdo(v_pay);
  PERFORM sincronizar_relatorio_rdo(v_pay);  -- reenvio do mesmo conteúdo

  SELECT id INTO v_rel_id FROM relatorios WHERE uuid_dispositivo = v_uuid;
  SELECT count(*) INTO v_vivas FROM atividades
   WHERE relatorio_id = v_rel_id AND excluido_em IS NULL;
  SELECT count(*) INTO v_fotos FROM evidencias_fotos f
    JOIN atividades a ON a.id = f.atividade_id WHERE a.relatorio_id = v_rel_id;

  PERFORM pg_temp.checar('D', 'atividade que continua no aparelho NÃO é marcada como excluída',
    v_vivas = 1, 'vivas = ' || v_vivas);
  PERFORM pg_temp.checar('D', 'reenvio não duplica as fotos da atividade viva',
    v_fotos = 1, 'fotos = ' || v_fotos);

  PERFORM set_config('request.jwt.claims','',true);
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.checar('D','regressão do caminho normal de sincronização', false, SQLERRM);
END $secao_d4$;

-- ----------------------------------------------------------------------------
-- D5 — o campo novo não pode ter quebrado quem não o manda
-- ----------------------------------------------------------------------------
-- Esta é a seção D fazendo o trabalho dela: não olha para a Dimensão, olha
-- para o que já estava de pé e podia ter caído junto.
--
-- O PWA que está NO BOLSO dos operadores hoje não conhece `dimensao_m` e nunca
-- vai mandá-la -- ele só ganha o campo quando alguém abrir o app depois do
-- deploy, e em campo isso pode demorar. Se a coluna nova tivesse ficado NOT
-- NULL, ou se a RPC passasse a exigir a chave no payload, o RDO do dia ficaria
-- preso no aparelho. Foi exatamente o que aconteceu com o arquivo 1.
DO $secao_d5$
DECLARE
  v_uid       uuid;
  v_rel_uuid  uuid := gen_random_uuid();
  v_ativ_uuid uuid := gen_random_uuid();
  v_dim       numeric;
  v_ativs     int;
BEGIN
  SELECT id INTO v_uid FROM auth.users ORDER BY created_at LIMIT 1;
  IF v_uid IS NULL THEN
    PERFORM pg_temp.pular('D', 'sincronização sem o campo dimensão', 'auth.users vazia');
    RETURN;
  END IF;

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);

  -- Payload EXATAMENTE como o app publicado monta: sem a chave dimensao_m.
  PERFORM sincronizar_relatorio_rdo(jsonb_build_object(
    'uuid_dispositivo', v_rel_uuid,
    'cliente', 'Colheita', 'contrato', 'ARAUCO', 'faena', 'TESTE SEM DIMENSAO',
    'tipo_estrada', 'Acesso', 'equipe_frente', 'GTM', 'fazenda', 'Elo Dourado 2',
    'data', '2026-09-10', 'encarregado', 'Elson', 'supervisor', 'Valmir',
    'tecnico_arauco', 'Edwilson', 'supervisor_arauco', 'Luciano', 'concluidoEm', now(),
    'atividades', jsonb_build_array(jsonb_build_object(
      'id', v_ativ_uuid,
      'tipo_atividade', 'Patrolamento',
      'up', 'UP-4471',
      'comprimento_m', 20, 'largura_m', 10
    ))
  ));

  SELECT count(*) INTO v_ativs FROM atividades WHERE uuid_atividade_dispositivo = v_ativ_uuid;
  PERFORM pg_temp.checar('D', 'app sem o campo novo continua sincronizando',
    v_ativs = 1, 'atividades gravadas = ' || v_ativs);

  SELECT dimensao_m INTO v_dim FROM atividades WHERE uuid_atividade_dispositivo = v_ativ_uuid;
  PERFORM pg_temp.checar('D', 'dimensão ausente vira NULL, não zero',
    v_dim IS NULL,
    'veio ' || coalesce(v_dim::text,'NULL') || ' -- zero seria uma medida inventada, e o painel a exibiria como se fosse real');

  PERFORM set_config('request.jwt.claims','',true);
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.checar('D','sincronização sem o campo dimensão', false, SQLERRM);
END $secao_d5$;

-- ----------------------------------------------------------------------------
-- D — o que a leva de 17/09 (edição pelo painel) podia ter derrubado
-- ----------------------------------------------------------------------------
-- editar_atividade_e_devolucao_individual.sql REDEFINIU por cópia duas funções
-- que já estavam em produção: sincronizar_relatorio_rdo e
-- listar_relatorios_painel. Cópia é o jeito mais fácil de reverter uma
-- melhoria sem perceber -- CREATE OR REPLACE não reclama de nada. Os testes
-- abaixo cobram o que o Painel e o PWA publicados dependem dessas duas.

-- O Histórico do Painel desenha uma linha por PRODUÇÃO. Se a chave `producoes`
-- sumisse do retorno, a tela ficaria vazia sem erro nenhum no console.
DO $secao_d6$
DECLARE
  v_chave text;
BEGIN
  FOREACH v_chave IN ARRAY ARRAY[
    'producoes', 'numero', 'status_revisao', 'motivo_devolucao', 'excluido_em',
    'status_anterior_exclusao', 'descricao_atividade', 'codigo_tarifa',
    'unidade_tarifa', 'dimensao_m', 'equipamentos', 'maquinas', 'fotos',
    'producao_devolvida_maquina_uuid', 'maquina_uuid', 'editado_em', 'editado_por'
  ]
  LOOP
    PERFORM pg_temp.checar('D',
      'listar_relatorios_painel ainda monta a chave "' || v_chave || '"',
      (SELECT prosrc LIKE '%''' || v_chave || '''%'
         FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'listar_relatorios_painel'),
      'a cópia de 17/09 pode ter deixado essa chave de fora');
  END LOOP;
END $secao_d6$;

-- "Enviou, acabou": atividade que não está devolvida não é alterada por um
-- reenvio, e o número dela volta na resposta de qualquer jeito (o operador
-- precisa dele para citar o apontamento). A cópia de 17/09 mexeu justamente
-- no ramo que decide isso.
DO $secao_d7$
DECLARE
  v_uid    uuid;
  v_rel    uuid := gen_random_uuid();
  v_adisp  uuid := gen_random_uuid();
  v_ret    jsonb;
  v_obs    text;
BEGIN
  SELECT id INTO v_uid FROM auth.users ORDER BY created_at LIMIT 1;
  IF v_uid IS NULL THEN
    PERFORM pg_temp.pular('D', 'reenvio não mexe em apontamento congelado', 'auth.users vazia');
    RETURN;
  END IF;

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid, 'role', 'authenticated', 'aal', 'aal1')::text, true);

  PERFORM sincronizar_relatorio_rdo(jsonb_build_object('uuid_dispositivo', v_rel,
    'cliente','Colheita','contrato','ARAUCO','faena','TESTE CONGELADA 17/09','tipo_estrada','Acesso',
    'equipe_frente','GTM','fazenda','Elo Dourado 2','data','2026-09-17','encarregado','Elson',
    'supervisor','Valmir','tecnico_arauco','Edwilson','supervisor_arauco','Luciano','concluidoEm', now(),
    'atividades', jsonb_build_array(jsonb_build_object('id', v_adisp,
      'tipo_atividade','Construção de Aterro','observacao','PRIMEIRO ENVIO',
      'comprimento_m',10,'largura_m',4))));

  -- Segundo envio com observação diferente: como está 'pendente' (não
  -- devolvida), nada pode mudar.
  v_ret := sincronizar_relatorio_rdo(jsonb_build_object('uuid_dispositivo', v_rel,
    'cliente','Colheita','contrato','ARAUCO','faena','TESTE CONGELADA 17/09','tipo_estrada','Acesso',
    'equipe_frente','GTM','fazenda','Elo Dourado 2','data','2026-09-17','encarregado','Elson',
    'supervisor','Valmir','tecnico_arauco','Edwilson','supervisor_arauco','Luciano','concluidoEm', now(),
    'atividades', jsonb_build_array(jsonb_build_object('id', v_adisp,
      'tipo_atividade','Construção de Aterro','observacao','TENTATIVA DE SOBRESCREVER',
      'comprimento_m',777,'largura_m',4))));

  SELECT observacao INTO v_obs FROM atividades WHERE uuid_atividade_dispositivo = v_adisp;
  PERFORM pg_temp.checar('D', 'reenvio NÃO altera apontamento que não foi devolvido',
    v_obs = 'PRIMEIRO ENVIO', 'observação virou: ' || coalesce(v_obs,'NULL'));
  PERFORM pg_temp.checar('D', 'e o reenvio conta a atividade como congelada',
    (v_ret->>'congeladas')::int = 1, 'congeladas = ' || coalesce(v_ret->>'congeladas','NULL'));
  PERFORM pg_temp.checar('D', 'o número do apontamento volta mesmo estando congelado',
    (v_ret->'numeros'->>(v_adisp::text)) IS NOT NULL,
    'sem o número o operador não tem como citar o apontamento');

  PERFORM set_config('request.jwt.claims','',true);
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.checar('D','reenvio não mexe em apontamento congelado', false, SQLERRM);
END $secao_d7$;

-- Invariante que a checagem de editar_atividade_rdo se apoia sem dizer: ela
-- barra pelo STATUS ('pendente'/'validado'), não por excluido_em. Isso só é
-- suficiente porque, no fluxo de hoje, atividade removida está sempre
-- 'devolvido' -- a marcação de exclusão só acontece nesse ramo, e o reenvio
-- limpa excluido_em junto. Se algum dia passar a existir removida com status
-- 'pendente', o painel voltaria a poder editá-la: este teste é o alarme.
SELECT pg_temp.checar('D', 'removida implica devolvida (invariante que protege a edição)',
  NOT EXISTS (
    SELECT 1 FROM atividades
     WHERE excluido_em IS NOT NULL AND status_revisao <> 'devolvido'
  ),
  'há atividade removida fora de "devolvido" -- editar_atividade_rdo passaria a aceitá-la');

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
