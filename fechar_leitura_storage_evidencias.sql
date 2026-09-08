-- ============================================================================
-- GTM RDO — evidência deixa de ser baixável por qualquer um
-- ============================================================================
-- Arquivo 10 da leva. Fecha a última pendência da auditoria de 2026-09-08.
--
-- O QUE ESTAVA ABERTO:
--
-- O bucket evidencias_rdo era `public`, então o endpoint
-- /storage/v1/object/public/evidencias_rdo/<caminho> servia qualquer foto SEM
-- CREDENCIAL NENHUMA. Verificado com curl sem chave: HTTP 200, 242 KB de JPEG.
--
-- O caminho tem três UUIDs e não é enumerável por tentativa -- mas isso é
-- obscuridade, não controle de acesso. Link encaminhado num grupo, print de
-- tela, histórico de navegador ou um vazamento do painel davam acesso
-- permanente àquela foto, para sempre e para qualquer um.
--
-- ORDEM DE APLICAÇÃO -- não inverter:
--
--   1. publicar o painel que usa createSignedUrls  <- FEITO (commit c993d03)
--   2. confirmar que as fotos aparecem             <- FEITO (Fábio, 08/09)
--   3. este arquivo
--
-- Fazer o 3 antes do 1 deixaria o painel sem imagem nenhuma até o deploy sair.
-- O PWA não é afetado em nenhum momento: ele exibe as fotos do IndexedDB
-- local, não do Storage.
--
-- O QUE MUDA NA PRÁTICA:
--
--   /object/public/...  -> passa a recusar
--   URL assinada        -> continua funcionando, para quem está autenticado,
--                          e expira em 1 hora (FOTO_URL_VALIDADE_S no painel)
--
-- As policies não mudam: `authenticated ve evidencias rdo` já existia e é ela
-- que autoriza a assinatura. O que muda é o bucket deixar de ter a porta dos
-- fundos aberta.
-- ============================================================================

-- WHERE por id, e não um UPDATE amplo: storage.buckets tem bucket de outro app
-- do Fábio neste mesmo banco (CLAUDE.md §1.6). Só o do RDO é tocado aqui.
UPDATE storage.buckets
   SET public = false
 WHERE id = 'evidencias_rdo';

-- ----------------------------------------------------------------------------
-- Limite de tamanho -- 10 MB
-- ----------------------------------------------------------------------------
-- Não é para economizar espaço: no plano Pro são 100 GB inclusos, e a
-- projeção de uso (180 KB por foto, ~400 MB/mês) levaria mais de 20 anos para
-- chegar lá. O limite existe contra o caso patológico.
--
-- Por que 10 MB e não algo apertado como 2 MB: a compressão do PWA tem
-- fallback -- se o canvas falhar (memória baixa, formato inesperado), ela
-- devolve o arquivo ORIGINAL, sem comprimir. É a decisão certa lá, porque
-- perder a foto seria pior. Mas significa que uma imagem crua de celular pode
-- subir. Com limite apertado, esse upload seria RECUSADO e a evidência do
-- apontamento se perderia -- trocaríamos um problema que não temos (espaço)
-- por um que dói (perder foto de obra).
--
-- 10 MB passa folgado por qualquer foto de celular, mesmo crua, e ainda barra
-- alguém logado tentando subir um arquivo de centenas de MB.
UPDATE storage.buckets
   SET file_size_limit = 10485760   -- 10 * 1024 * 1024
 WHERE id = 'evidencias_rdo';

-- ============================================================================
-- CONFERÊNCIA
-- ============================================================================
-- SELECT id, public, file_size_limit, allowed_mime_types
--   FROM storage.buckets WHERE id = 'evidencias_rdo';
--
-- E de fora: um GET em /storage/v1/object/public/evidencias_rdo/<caminho>
-- deve deixar de devolver 200.
-- ============================================================================
