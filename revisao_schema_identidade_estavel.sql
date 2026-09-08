-- ============================================================================
-- GTM RDO — schema do fluxo de revisão + identidade estável de atividade
-- ============================================================================
-- Reescrito do zero em 2026-09-08. O arquivo original se perdeu, e a auditoria
-- pelo MCP mostrou que ele NUNCA chegou a ser aplicado neste banco -- não há
-- nada lá de onde reconstituir. O conteúdo abaixo foi derivado de quem
-- consome estas colunas: Painel/index.html (badge de status, motivo da
-- devolução), PWA/index.html (banner de devolvidas), a Edge Function
-- enviar-push e o pwa_login_identidade_usuario.sql.
--
-- DECISÃO IMPORTANTE -- por que este arquivo já nasce no formato final:
--
-- A sequência histórica era: este schema criava push_subscriptions com
-- dispositivo_fisico, e depois o pwa_login_identidade_usuario.sql renomeava a
-- coluna pra usuario_id e trocava as funções. Reproduzir isso agora seria
-- escrever colunas para sobrescrever dois minutos depois -- migração histórica
-- só importa quando já foi aplicada em algum lugar, e esta não foi (o banco
-- tem ZERO migrações registradas).
--
-- Então aqui já vai o estado final: identidade por auth.uid(), não por
-- aparelho. Consequência: o pwa_login_identidade_usuario.sql fica OBSOLETO --
-- o que ele fazia está incorporado aqui e no revisao_rpcs.sql. Não apaguei
-- aquele arquivo (não apago nada sem você pedir), mas NÃO o rode: ele quebra
-- na linha 16, num RENAME de coluna que aqui já nasce com o nome certo.
--
-- Ordem de aplicação:
--   1. este arquivo
--   2. revisao_rpcs.sql
--   3. travar_permissoes_rpc_estado_atual.sql
--   4. corte_sincronizacao_com_login.sql  <- só junto com o deploy do PWA novo
--
-- Tudo aqui é aditivo (ADD COLUMN / CREATE TABLE / CREATE INDEX) e
-- idempotente: rodar duas vezes não faz mal e não perde dado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. relatorios.criado_por — de quem é o RDO
-- ----------------------------------------------------------------------------
-- Sem isso não dá pra saber pra QUEM notificar uma devolução. Fica NULL nos
-- relatórios que já existem (foram sincronizados anonimamente, antes do
-- login) -- e é justamente por isso que não dá pra pôr NOT NULL aqui.
ALTER TABLE relatorios
  ADD COLUMN IF NOT EXISTS criado_por uuid REFERENCES auth.users(id);

CREATE INDEX IF NOT EXISTS idx_relatorios_criado_por ON relatorios (criado_por);

COMMENT ON COLUMN relatorios.criado_por IS
  'auth.uid() de quem sincronizou. NULL nos relatórios anteriores ao login por Supabase Auth -- esses não têm dono e não geram notificação de devolução.';

-- ----------------------------------------------------------------------------
-- 2. atividades.uuid_atividade_dispositivo — a identidade estável
-- ----------------------------------------------------------------------------
-- Este é o coração do arquivo. Hoje sincronizar_relatorio_rdo apaga todas as
-- atividades do relatório e recria: cada sincronização gera ids novos. Com o
-- fluxo de revisão isso é fatal -- o painel devolve a atividade X, o operador
-- reenvia o relatório, a atividade X deixa de existir e nasce uma Y sem
-- status nenhum. A devolução some.
--
-- A correção é o PWA mandar o id que ELE já usa no IndexedDB, e o banco fazer
-- upsert por (relatorio_id, uuid_atividade_dispositivo). Ver, no PWA,
-- index.html:1610 -- ele casa a devolução com `d.atividade_id === a.id`,
-- onde `a.id` é exatamente esse uuid local.
ALTER TABLE atividades
  ADD COLUMN IF NOT EXISTS uuid_atividade_dispositivo uuid;

-- Backfill das linhas que já existem. São 3 atividades, todas de teste
-- (mesmo cliente/fazenda/data, sincronizadas em sequência em 02/09/2026).
-- Elas nunca tiveram id de dispositivo, e não há de onde recuperar -- um uuid
-- novo só serve pra dar a elas uma identidade a partir daqui. Se algum desses
-- relatórios for reenviado pelo PWA, as linhas antigas são substituídas pelas
-- do aparelho, que é a fonte da verdade. Sem WHERE amplo: só toca no que
-- está NULL, então rodar de novo não mexe em nada.
UPDATE atividades
   SET uuid_atividade_dispositivo = gen_random_uuid()
 WHERE uuid_atividade_dispositivo IS NULL;

ALTER TABLE atividades
  ALTER COLUMN uuid_atividade_dispositivo SET NOT NULL;

-- O DEFAULT não é enfeite -- sem ele este arquivo QUEBRA O PWA QUE ESTÁ EM
-- CAMPO, e foi o que aconteceu ao aplicar em 2026-09-08.
--
-- A sincronizar_relatorio_rdo publicada é anterior ao fluxo de revisão: o
-- INSERT INTO atividades dela não tem esta coluna na lista (conferido com
-- pg_get_functiondef no banco). Com NOT NULL e sem default, a primeira
-- sincronização de um operador falharia com violação de not-null -- o RDO do
-- dia preso no aparelho, que é exatamente o cenário que o arquivo 4 evita ser
-- aplicado cedo demais. "Aditivo" no papel não é o mesmo que inofensivo:
-- adicionar NOT NULL a uma coluna que o caminho de escrita vigente não
-- preenche é uma mudança destrutiva disfarçada.
--
-- O uuid gerado aqui não é identidade estável de verdade: o caminho antigo
-- ainda apaga-e-recria as atividades a cada sync, então ele muda a cada envio.
-- Mas isso é o comportamento que JÁ existia -- o default só evita a quebra.
-- Quando o corte_sincronizacao_com_login.sql entrar, o INSERT passa a mandar o
-- uuid do aparelho explicitamente e este default vira rede de proteção.
ALTER TABLE atividades
  ALTER COLUMN uuid_atividade_dispositivo SET DEFAULT gen_random_uuid();

COMMENT ON COLUMN atividades.uuid_atividade_dispositivo IS
  'UUID da atividade no IndexedDB do PWA. É a chave do upsert junto com relatorio_id -- o que faz o status de revisão sobreviver a um reenvio.';

-- O Postgres não tem ADD CONSTRAINT IF NOT EXISTS; daí o bloco.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'atividades'::regclass
      AND conname  = 'atividades_relatorio_uuid_dispositivo_key'
  ) THEN
    ALTER TABLE atividades
      ADD CONSTRAINT atividades_relatorio_uuid_dispositivo_key
      UNIQUE (relatorio_id, uuid_atividade_dispositivo);
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. atividades — as colunas do fluxo de revisão
-- ----------------------------------------------------------------------------
-- Devolução é POR ATIVIDADE, nunca por relatório inteiro (decisão sua, está
-- no CLAUDE.md §3) -- por isso o status mora aqui e não em relatorios.
ALTER TABLE atividades
  ADD COLUMN IF NOT EXISTS status_revisao text NOT NULL DEFAULT 'pendente';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'atividades'::regclass
      AND conname  = 'atividades_status_revisao_check'
  ) THEN
    ALTER TABLE atividades
      ADD CONSTRAINT atividades_status_revisao_check
      CHECK (status_revisao IN ('pendente', 'validado', 'devolvido'));
  END IF;
END $$;

ALTER TABLE atividades
  ADD COLUMN IF NOT EXISTS motivo_devolucao text,
  ADD COLUMN IF NOT EXISTS revisado_por     uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS revisado_em      timestamptz;

COMMENT ON COLUMN atividades.status_revisao IS
  'pendente (padrão ao sincronizar) | validado | devolvido. O painel muda; o PWA lê pelo banner de devolvidas.';
COMMENT ON COLUMN atividades.motivo_devolucao IS
  'Texto escrito pelo revisor no painel. Aparece no card da atividade no PWA. Limpo quando o operador reenvia a atividade corrigida.';

-- Índice parcial: a consulta que importa é "o que está devolvido", que é
-- sempre uma fração pequena da tabela. Indexar só essas linhas mantém o
-- índice miúdo e não pesa no INSERT das atividades normais.
CREATE INDEX IF NOT EXISTS idx_atividades_devolvidas
  ON atividades (relatorio_id)
  WHERE status_revisao = 'devolvido';

-- ----------------------------------------------------------------------------
-- 4. push_subscriptions — inscrições de Web Push, uma por aparelho
-- ----------------------------------------------------------------------------
-- Chaveada por usuario_id (auth.uid()), não por aparelho: a mesma pessoa pode
-- trocar de celular, e um celular pode ser usado por gente diferente. Uma
-- pessoa pode ter várias linhas aqui (uma por aparelho/navegador em que
-- aceitou notificação) -- por isso o UNIQUE é no par, não só no usuário.
CREATE TABLE IF NOT EXISTS push_subscriptions (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id   uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint     text NOT NULL,
  p256dh       text NOT NULL,
  auth         text NOT NULL,
  criado_em    timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT push_subscriptions_usuario_endpoint_key UNIQUE (usuario_id, endpoint)
);

COMMENT ON TABLE push_subscriptions IS
  'Inscrições de Web Push do PWA. Lida pela Edge Function enviar-push com a service role -- que também apaga daqui as que o navegador reportar como expiradas (404/410).';
COMMENT ON COLUMN push_subscriptions.usuario_id IS
  'auth.uid() de quem logou no PWA -- não um id de aparelho. Permite notificar a pessoa certa em qualquer aparelho que ela usar.';

CREATE INDEX IF NOT EXISTS idx_push_subscriptions_usuario
  ON push_subscriptions (usuario_id);

-- RLS ligada e SEM política, de propósito: o padrão do projeto é que nenhuma
-- tabela seja acessada direto. Quem lê é a Edge Function (service role, que
-- ignora RLS) e quem escreve é salvar_push_subscription() (SECURITY DEFINER).
-- Sem política, o acesso direto com a chave anon não devolve nada.
ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- CONFERÊNCIA -- rode junto e leia o resultado, não só o "Success".
-- Esperado: 8 linhas (5 colunas novas + a tabela + a constraint + o índice).
-- ============================================================================
SELECT 'coluna' AS objeto, table_name || '.' || column_name AS nome
  FROM information_schema.columns
 WHERE table_schema = 'public'
   AND (table_name, column_name) IN (
     ('relatorios','criado_por'), ('atividades','uuid_atividade_dispositivo'),
     ('atividades','status_revisao'), ('atividades','motivo_devolucao'),
     ('atividades','revisado_em'))
UNION ALL
SELECT 'tabela', 'push_subscriptions'
  FROM information_schema.tables
 WHERE table_schema = 'public' AND table_name = 'push_subscriptions'
UNION ALL
SELECT 'constraint', conname FROM pg_constraint
 WHERE conname = 'atividades_relatorio_uuid_dispositivo_key'
UNION ALL
SELECT 'indice', indexname FROM pg_indexes
 WHERE schemaname = 'public' AND indexname = 'idx_atividades_devolvidas'
ORDER BY 1, 2;
