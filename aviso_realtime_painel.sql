-- ============================================================================
-- GTM RDO — aviso em tempo real para o painel quando o campo sincroniza
-- ============================================================================
-- Arquivo 7 da leva. Pedido do Fábio (08/09): "quando o usuário do PWA enviar
-- uma correção ou apontamento, o usuário do painel poderia ser notificado --
-- assim ele não ficaria no escuro".
--
-- POR QUE BROADCAST, E NÃO POSTGRES CHANGES:
--
-- Postgres Changes entrega ao cliente as linhas que ele poderia ler direto da
-- tabela, respeitando RLS. Neste projeto NENHUMA tabela tem policy: o RLS está
-- ligado e fechado, e todo acesso passa por função SECURITY DEFINER. Ligar
-- Postgres Changes exigiria criar policy de SELECT em relatorios/atividades --
-- abrindo leitura direta e furando o padrão que sustenta a segurança daqui.
--
-- Broadcast não tem esse problema: o banco manda um recado por um canal, sem
-- expor tabela nenhuma.
--
-- O QUE VAI NO RECADO -- e por que quase nada:
--
-- Só um sinal: "houve sincronização, recarregue". Sem fazenda, sem cliente,
-- sem id de relatório.
--
-- O motivo é concreto: `authenticated` neste projeto Supabase inclui os
-- usuários dos OUTROS apps do Fábio que dividem este banco. A policy abaixo
-- restringe o canal por tópico, mas qualquer pessoa autenticada no projeto
-- poderia assinar 'rdo-painel'. Com payload vazio de conteúdo, o pior caso é
-- alguém saber QUE houve uma sincronização -- não o que tem nela. Quem quiser
-- os dados continua tendo que passar por listar_relatorios_painel, que exige
-- aal2.
--
-- Custo: o plano Free cobre 2 milhões de mensagens/mês e 200 conexões de pico.
-- Aqui é uma mensagem por sincronização de RDO e 1-2 painéis abertos.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Quem pode escutar
-- ----------------------------------------------------------------------------
-- ATENÇÃO -- realtime.messages é do schema `realtime`, COMPARTILHADO com os
-- outros apps deste banco (CLAUDE.md §1.6). Antes desta policy a tabela tinha
-- RLS ligada e ZERO policies, ou seja, ninguém recebia broadcast nenhum.
--
-- Esta policy é aditiva e restrita a UM tópico: não muda nada para os outros
-- apps, e não abre os canais deles. O exemplo da documentação usa
-- `using (true)`, que liberaria qualquer tópico do projeto inteiro -- é
-- justamente o que não fazemos aqui.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'realtime' AND tablename = 'messages'
       AND policyname = 'rdo_painel_recebe_aviso_sincronizacao'
  ) THEN
    CREATE POLICY rdo_painel_recebe_aviso_sincronizacao
      ON realtime.messages
      FOR SELECT
      TO authenticated
      USING (realtime.topic() = 'rdo-painel');
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 2. O gatilho que avisa
-- ----------------------------------------------------------------------------
-- Dispara no upsert de relatorios, que é o que toda sincronização faz -- uma
-- mensagem por RDO sincronizado, e não uma por atividade. Um RDO com 10
-- apontamentos geraria 10 avisos se o gatilho estivesse em `atividades`, e o
-- painel recarregaria 10 vezes a mesma coisa.
CREATE OR REPLACE FUNCTION avisar_painel_sincronizacao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- O aviso NUNCA pode derrubar a sincronização. Se o Realtime estiver fora
  -- do ar, ou a função mudar de assinatura numa atualização do Supabase, o
  -- RDO do operador tem que ser gravado do mesmo jeito -- ele é o dado que
  -- não tem outra cópia; o aviso é conveniência. Daí o bloco com EXCEPTION.
  BEGIN
    PERFORM realtime.send(
      jsonb_build_object('em', now()),  -- payload sem dado de negócio, de propósito
      'sincronizou',                    -- evento
      'rdo-painel',                     -- tópico (o mesmo da policy acima)
      true                              -- canal privado: exige a policy
    );
  EXCEPTION WHEN OTHERS THEN
    -- Não relança: só registra. Aparece no log do Postgres se alguém procurar.
    RAISE WARNING 'aviso de sincronização não enviado: %', SQLERRM;
  END;
  RETURN NULL;  -- AFTER trigger: o retorno é ignorado
END;
$$;

DROP TRIGGER IF EXISTS relatorios_avisa_painel ON relatorios;
CREATE TRIGGER relatorios_avisa_painel
  AFTER INSERT OR UPDATE OF sincronizado_em ON relatorios
  FOR EACH ROW
  EXECUTE FUNCTION avisar_painel_sincronizacao();

-- A função é chamada pelo gatilho, não por cliente nenhum. Ninguém de fora
-- precisa de EXECUTE nela -- mesma regra das outras utilitárias.
REVOKE ALL ON FUNCTION avisar_painel_sincronizacao() FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- CONFERÊNCIA
-- ============================================================================
-- 1) A policy existe e está restrita ao tópico do RDO:
--
-- SELECT policyname, roles, qual FROM pg_policies
--  WHERE schemaname='realtime' AND tablename='messages';
--
-- 2) O gatilho está na tabela certa e só no que interessa:
--
-- SELECT tgname, pg_get_triggerdef(oid) FROM pg_trigger
--  WHERE tgrelid='relatorios'::regclass AND NOT tgisinternal;
--
-- 3) Sincronizar um RDO grava uma linha em realtime.messages com topic
--    'rdo-painel' (roda em transação; o ROLLBACK desfaz).
-- ============================================================================
