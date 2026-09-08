-- ============================================================================
-- GTM RDO — só usuário logado envia foto de evidência
-- ============================================================================
-- Arquivo 9 da leva. Achado na auditoria de segurança de 2026-09-08.
--
-- O QUE ESTAVA ABERTO:
--
-- O bucket evidencias_rdo tinha duas policies dando INSERT e UPDATE para
-- `anon`. Como a chave anon é pública por design e está nos dois index.html,
-- qualquer pessoa podia:
--
--   - enviar arquivos para o bucket (encher o storage), e
--   - SOBRESCREVER uma evidência existente, bastando saber o caminho.
--
-- O segundo é o grave. Foto de evidência embasa medição faturável; poder
-- trocar a imagem de um apontamento sem deixar rastro é pior do que poder
-- lê-la. E o caminho não é segredo: ele aparece no painel, em qualquer URL
-- que alguém encaminhe.
--
-- POR QUE ESTAVA ASSIM, E POR QUE DÁ PARA FECHAR AGORA:
--
-- As policies são da época em que o PWA sincronizava ANONIMAMENTE -- sem
-- login, não havia outro papel para conceder. Isso mudou hoje: o
-- corte_sincronizacao_com_login.sql passou a exigir auth.uid(), e o upload das
-- fotos acontece dentro do mesmo fluxo, já autenticado. Tirar `anon` daqui não
-- quebra nada em campo.
--
-- ALTER em vez de DROP+CREATE de propósito: preserva USING e WITH CHECK como
-- estão, mudando só quem pode. Menos chance de eu reescrever errado uma regra
-- que já funciona, e nada é removido (CLAUDE.md §1.1).
--
-- O QUE ESTE ARQUIVO **NÃO** FAZ:
--
-- A leitura continua pública. O bucket é `public`, então
-- /storage/v1/object/public/... serve as fotos sem credencial nenhuma --
-- verificado com curl, HTTP 200. Fechar isso exige bucket privado e URL
-- assinada no painel, que é outra mudança, com deploy junto. Decisão do Fábio
-- (08/09): fechar a escrita primeiro, a leitura fica registrada como pendência.
-- ============================================================================

-- Envio: só quem está logado.
ALTER POLICY "anon envia evidencias rdo"
  ON storage.objects
  TO authenticated;

-- Sobrescrita: idem. O PWA usa upsert:false e não depende desta policy
-- (comentário no index.html, na chamada de upload), mas ela fica -- restrita --
-- em vez de ser removida: se algum caminho de reenvio precisar dela, continua
-- funcionando para usuário logado.
ALTER POLICY "anon atualiza evidencias rdo (upsert)"
  ON storage.objects
  TO authenticated;

-- ============================================================================
-- CONFERÊNCIA -- esperado: nenhuma das duas com `anon` na lista de papéis.
-- ============================================================================
-- SELECT policyname, cmd, roles FROM pg_policies
--  WHERE schemaname='storage' AND tablename='objects'
--  ORDER BY policyname;
--
-- E, do lado de fora, um POST no endpoint de upload com a chave anon deve
-- passar a responder 403 em vez de aceitar o arquivo.
-- ============================================================================
