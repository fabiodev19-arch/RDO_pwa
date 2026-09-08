-- ============================================================================
-- GTM RDO — trava as permissões das RPCs que EXISTEM no banco hoje
-- ============================================================================
-- Por que este arquivo existe, se já tem um travar_permissoes_rpc.sql?
--
-- Porque aquele não roda. Auditoria do banco em 2026-09-08 mostrou que o banco
-- estava numa versão anterior ao trabalho de revisão/devolução: não existiam
-- validar_atividade_rdo, devolver_atividade_rdo, verificar_atividades_devolvidas
-- nem salvar_push_subscription. O arquivo original lista as quatro dentro de um
-- DO $$ ... FOREACH: o REVOKE na primeira inexistente levanta
-- "function does not exist" e aborta o bloco inteiro -- inclusive as funções
-- que existem e deveriam ter sido travadas. Resultado: nada é travado, e a
-- mensagem de erro parece um detalhe.
--
-- CORREÇÃO DE 2026-09-08 (tarde) -- REVOKE FROM PUBLIC não basta neste banco:
--
-- A versão anterior deste arquivo dizia que as funções estavam abertas "com
-- EXECUTE para PUBLIC, o default do Postgres" e que "anon herda de PUBLIC".
-- Isso está errado, e foi conferido lendo pg_proc.proacl direto no banco. A
-- ACL real de cada função é assim:
--
--   =X/postgres | postgres=X/postgres | anon=X/postgres | authenticated=X/...
--    ^ PUBLIC                            ^ anon EXPLÍCITO, não herdado
--
-- O `anon=X` vem de um ALTER DEFAULT PRIVILEGES que o próprio Supabase
-- instala no schema public (dois, na verdade: um do papel `postgres` e outro
-- do `supabase_admin` -- veja em pg_default_acl). Todo CREATE FUNCTION novo
-- neste schema já nasce com EXECUTE concedido a anon, authenticated e
-- service_role, de forma explícita.
--
-- Consequência prática: revogar de PUBLIC remove só o `=X/postgres` e deixa o
-- `anon=X/postgres` de pé. A função continua chamável sem login por
-- /rest/v1/rpc/<nome> com a chave anon, e o script termina com "Success" --
-- que é o pior jeito de uma trava falhar. Foi exatamente o que aconteceu ao
-- aplicar o revisao_rpcs.sql: as 5 funções nasceram com REVOKE FROM PUBLIC e
-- mesmo assim has_function_privilege('anon', ...) devolvia true.
--
-- Por isso todo bloco abaixo revoga de PUBLIC **e** de anon. As duas linhas.
-- A regra do BOAS_PRATICAS.md §2 continua valendo -- ela só estava incompleta:
-- não basta revogar de um dos dois, tem que ser dos dois.
--
-- Cada função é referenciada pela assinatura exata; rodar de novo é inofensivo
-- (REVOKE/GRANT são idempotentes).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Leitura de catálogo -- sem dado sensível, o PWA lê antes de logar.
--    Continua liberada pra anon DE PROPÓSITO: aqui o GRANT é o objetivo, não
--    um resto de configuração.
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION listar_cadastros() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION listar_cadastros() TO anon, authenticated;

REVOKE ALL ON FUNCTION listar_regras() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION listar_regras() TO anon, authenticated;

-- ----------------------------------------------------------------------------
-- 2. Só painel. Estas oito já chamam PERFORM exige_mfa() na primeira linha do
--    corpo (conferido no banco), então a brecha aqui é de profundidade, não
--    de porta escancarada: sem aal2 elas já levantam exceção. O REVOKE é a
--    trava de fora, pra que um bug futuro no corpo não vire brecha de verdade.
--    Travar isto NÃO quebra nada em campo -- quem usa é o painel, autenticado.
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION excluir_cadastro(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION excluir_cadastro(uuid) TO authenticated;

REVOKE ALL ON FUNCTION excluir_regra(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION excluir_regra(text, text) TO authenticated;

REVOKE ALL ON FUNCTION importar_cadastros_lote(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION importar_cadastros_lote(jsonb) TO authenticated;

REVOKE ALL ON FUNCTION listar_cadastros_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION listar_cadastros_admin() TO authenticated;

REVOKE ALL ON FUNCTION listar_regras_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION listar_regras_admin() TO authenticated;

REVOKE ALL ON FUNCTION listar_relatorios_painel(date, date, text, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION listar_relatorios_painel(date, date, text, text, integer) TO authenticated;

REVOKE ALL ON FUNCTION salvar_cadastro(uuid, text, text, boolean, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION salvar_cadastro(uuid, text, text, boolean, integer) TO authenticated;

REVOKE ALL ON FUNCTION salvar_regra(text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION salvar_regra(text, text, jsonb) TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. As quatro do fluxo de revisão (criadas pelo revisao_rpcs.sql). Elas já
--    trazem REVOKE/GRANT no próprio arquivo, mas só de PUBLIC -- pelo motivo
--    explicado no topo, isso deixou anon de pé. Aqui é onde anon sai.
--
--    As duas do PWA (verificar_atividades_devolvidas, salvar_push_subscription)
--    são chamadas DEPOIS do login, então authenticated é o papel certo. Elas
--    usam auth.uid() por dentro e não recebem id de usuário por parâmetro --
--    com anon, auth.uid() seria NULL e a função não devolveria nada de útil,
--    mas o certo é nem deixar chamar.
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION validar_atividade_rdo(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION validar_atividade_rdo(uuid) TO authenticated;

REVOKE ALL ON FUNCTION devolver_atividade_rdo(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION devolver_atividade_rdo(uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION verificar_atividades_devolvidas() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION verificar_atividades_devolvidas() TO authenticated;

REVOKE ALL ON FUNCTION salvar_push_subscription(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION salvar_push_subscription(text, text, text) TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. Utilitárias internas -- fechadas para todo mundo de fora, sem GRANT.
--
--    Podem ser fechadas sem medo porque só são chamadas de DENTRO de funções
--    SECURITY DEFINER, que rodam com o privilégio do dono (postgres) -- a
--    checagem de EXECUTE não passa pelo papel de quem fez a chamada REST.
--    Conferido no banco: as 10 chamadoras de exige_mfa() são todas do RDO e
--    todas SECURITY DEFINER.
--
--    exige_mfa() exposta era o caso mais chato da lista: qualquer um podia
--    chamá-la direto por /rest/v1/rpc/exige_mfa e usar a mensagem de erro como
--    oráculo -- "sessão inválida" x "confirme o código" diz se um token é
--    válido e se já passou pelo 2FA. Não dá acesso a nada, mas é informação de
--    graça pra quem estiver sondando.
--
--    normalizar_texto_cadastro(text) hoje não é usada por NADA -- não aparece
--    em corpo de função, trigger, índice, constraint nem default (conferido).
--    Está aqui só para não ficar uma porta aberta sem dono. Não é removida:
--    função morta não some deste projeto sem pedido explícito (CLAUDE.md §1.1).
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION exige_mfa() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION normalizar_texto_cadastro(text) FROM PUBLIC, anon, authenticated;

-- ----------------------------------------------------------------------------
--    As DUAS FUNÇÕES DE TRIGGER ficam de fora. O advisor do Supabase acusa
--    remove_other_unverified_mfa_factors_trigger como "executável por anon",
--    mas é falso positivo: o PostgREST não expõe função que retorna `trigger`,
--    então não existe /rest/v1/rpc/ pra ela. Não há o que fechar.
--
--    E revogar teria risco de verdade do outro lado. Este banco hospeda mais
--    de um app; remove_other_unverified_mfa_factors_trigger está em
--    auth.mfa_factors, que é do Supabase Auth e serve a TODOS eles -- se o
--    Postgres checasse EXECUTE no disparo do trigger, o cadastro de 2FA
--    quebraria pra todo mundo, não só pro painel do RDO.
--
--    Risco não-zero em troca de ganho zero: não se mexe.
--
-- trg_atualizar_timestamp() -- só é usada por cadastros, regras_negocio e
--    relatorios (conferido em pg_trigger), todas do RDO. Mesma lógica.

-- ----------------------------------------------------------------------------
-- 5. sincronizar_relatorio_rdo(jsonb) -- NÃO ESTÁ NESTE ARQUIVO DE PROPÓSITO.
--
--    É a função mais exposta do banco: chamável por anon e sem nenhuma
--    verificação de sessão no corpo (não chama exige_mfa nem auth.uid()).
--    Qualquer um com a chave anon grava relatório no banco.
--
--    Mas revogar anon aqui derruba a sincronização do PWA que está em campo,
--    porque a versão publicada sincroniza anonimamente -- o login por Supabase
--    Auth só existe em commit local, ainda não publicado. Travar antes de
--    publicar o PWA novo = operador termina o RDO e a sincronização falha,
--    com o dado preso no aparelho.
--
--    A ordem segura é: publicar o PWA com login -> confirmar que o campo
--    atualizou -> só então rodar o bloco abaixo, junto com o
--    corte_sincronizacao_com_login.sql.
--
--    Descomente quando for a hora (note o `, anon` -- sem ele não trava nada):
--
-- REVOKE ALL ON FUNCTION sincronizar_relatorio_rdo(jsonb) FROM PUBLIC, anon;
-- GRANT EXECUTE ON FUNCTION sincronizar_relatorio_rdo(jsonb) TO authenticated;

-- ============================================================================
-- CONFERÊNCIA -- rode depois e leia o resultado, não só o "Success".
-- Deve devolver só listar_cadastros, listar_regras, sincronizar_relatorio_rdo
-- (esta até o bloco 5 ser descomentado) e as duas funções de trigger, que são
-- inalcançáveis pelo PostgREST.
-- ============================================================================
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args,
       p.prorettype::regtype AS retorno
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND has_function_privilege('anon', p.oid, 'EXECUTE')
ORDER BY p.proname;
