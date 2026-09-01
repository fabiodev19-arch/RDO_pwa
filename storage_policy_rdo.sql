-- ============================================================================
-- GTM RDO — política de Storage do bucket evidencias_rdo
-- ============================================================================
-- Criar o bucket pelo painel do Supabase não libera acesso nenhum a ele —
-- toda tabela do Storage (storage.objects) também é protegida por RLS,
-- então sem isso o upload do PWA falha com "permissão negada".
--
-- Rode isso no SQL Editor depois de já ter criado o bucket "evidencias_rdo"
-- pelo painel (Storage → New bucket → marcar como privado, sem "public").
-- ============================================================================

-- PWA de campo (sem login) pode ENVIAR fotos, mas não listar nem apagar o
-- bucket inteiro — só consegue gravar dentro de evidencias_rdo.
CREATE POLICY "anon envia evidencias rdo"
ON storage.objects
FOR INSERT
TO anon, authenticated
WITH CHECK (bucket_id = 'evidencias_rdo');

-- Painel (com login) vai precisar ENXERGAR as fotos pra exibir na revisão
-- dos relatórios — preparando já pra quando chegarmos nessa tela.
CREATE POLICY "authenticated ve evidencias rdo"
ON storage.objects
FOR SELECT
TO authenticated
USING (bucket_id = 'evidencias_rdo');
