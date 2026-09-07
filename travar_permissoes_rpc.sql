-- ============================================================================
-- GTM RDO — trava as permissões de execução de TODAS as RPCs
-- ============================================================================
-- Achado ao testar o login do PWA: o Postgres concede EXECUTE pra PUBLIC
-- automaticamente em toda função nova, a não ser que seja revogado
-- explicitamente. "REVOKE ... FROM anon" (o que várias funções já tinham)
-- NÃO revoga esse acesso via PUBLIC -- anon continua conseguindo chamar
-- porque herda de PUBLIC, não por uma concessão direta.
--
-- Na prática, a maioria das funções sensíveis já se protegia por dentro
-- (o PERFORM exige_mfa() no início barra quem não tem sessão válida de
-- painel) -- mas depender só disso é frágil: um bug futuro em alguma
-- função poderia abrir uma brecha de verdade. Esse arquivo trava direito,
-- na concessão, não só na lógica interna.
-- ============================================================================

-- Só leitura de catálogo, sem dado sensível -- continua liberado pro PWA
-- ler mesmo sem login (cadastros, regras, catálogo de tarifa se existir).
DO $$
DECLARE
  v_func text;
BEGIN
  FOREACH v_func IN ARRAY ARRAY[
    'listar_cadastros()',
    'listar_regras()'
  ]
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', v_func);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon, authenticated', v_func);
  END LOOP;
END $$;

-- As mesmas dessa lista só existem se o catálogo de tarifa (etapa que foi
-- revertida) ainda estiver no seu banco -- pula sem erro se não existir.
DO $$
BEGIN
  IF to_regprocedure('public.listar_atividades_tarifa()') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION listar_atividades_tarifa() FROM PUBLIC;
    GRANT EXECUTE ON FUNCTION listar_atividades_tarifa() TO anon, authenticated;
  END IF;
  IF to_regprocedure('public.listar_maquinas()') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION listar_maquinas() FROM PUBLIC;
    GRANT EXECUTE ON FUNCTION listar_maquinas() TO anon, authenticated;
  END IF;
END $$;

-- Exige autenticação de verdade (usuário logado no PWA) -- sincronizar e
-- as duas novas do fluxo de devolução/push.
DO $$
DECLARE
  v_func text;
BEGIN
  FOREACH v_func IN ARRAY ARRAY[
    'sincronizar_relatorio_rdo(jsonb)',
    'verificar_atividades_devolvidas()',
    'salvar_push_subscription(text,text,text)'
  ]
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', v_func);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_func);
  END LOOP;
END $$;

-- Só painel (exigem MFA por dentro também, isso aqui é a trava de fora)
DO $$
DECLARE
  v_func text;
BEGIN
  FOREACH v_func IN ARRAY ARRAY[
    'excluir_cadastro(uuid)',
    'excluir_regra(text,text)',
    'importar_cadastros_lote(jsonb)',
    'listar_cadastros_admin()',
    'listar_regras_admin()',
    'listar_relatorios_painel(date,date,text,text,integer)',
    'salvar_cadastro(uuid,text,text,boolean,integer)',
    'salvar_regra(text,text,jsonb)',
    'validar_atividade_rdo(uuid)',
    'devolver_atividade_rdo(uuid,text)'
  ]
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', v_func);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_func);
  END LOOP;
END $$;

-- Funções utilitárias internas -- não precisam ser chamadas direto por
-- ninguém de fora, só por outras funções SECURITY DEFINER (que usam o
-- privilégio de quem definiu a função, não de quem a chamou por fora).
REVOKE ALL ON FUNCTION exige_mfa() FROM PUBLIC;
REVOKE ALL ON FUNCTION normalizar_texto_cadastro(text) FROM PUBLIC;
DO $$
BEGIN
  IF to_regprocedure('public.trg_atualizar_timestamp()') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION trg_atualizar_timestamp() FROM PUBLIC;
  END IF;
END $$;

-- ============================================================================
-- Conferência: depois de rodar, isso deve devolver 0 linhas (nenhuma
-- função sensível continua liberada pra anon).
-- ============================================================================
-- SELECT proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public' AND has_function_privilege('anon', p.oid, 'EXECUTE')
-- AND proname NOT IN ('listar_cadastros','listar_regras','listar_atividades_tarifa','listar_maquinas');
