-- ============================================================================
-- GTM RDO — RPCs do fluxo de revisão (validar / devolver / notificar)
-- ============================================================================
-- Reescrito do zero em 2026-09-08, junto com o
-- revisao_schema_identidade_estavel.sql -- RODE AQUELE ANTES DESTE, senão
-- estas funções referenciam colunas que ainda não existem.
--
-- Nada aqui é chamado pelo PWA nem pelo Painel que estão publicados hoje:
-- validar/devolver só existem no commit local do Painel, e as duas do PWA
-- dependem do login, que também não foi publicado. Ou seja, aplicar este
-- arquivo NÃO muda o comportamento de nada que esteja em campo. A única
-- função que já está em uso é listar_relatorios_painel, e a mudança nela é
-- só acrescentar campos ao JSON -- o painel antigo ignora o que não conhece.
--
-- A troca que corta o PWA antigo (sincronizar_relatorio_rdo exigindo login)
-- está separada, no corte_sincronizacao_com_login.sql.
--
-- Toda função abaixo termina com REVOKE ALL ... FROM PUBLIC, anon + GRANT
-- EXECUTE explícito -- ver BOAS_PRATICAS.md §2.
--
-- O `, anon` no REVOKE não é redundância: descoberto ao aplicar este arquivo
-- em 2026-09-08. O Supabase instala um ALTER DEFAULT PRIVILEGES no schema
-- public que dá EXECUTE a anon, authenticated e service_role em toda função
-- nova -- de forma EXPLÍCITA, não herdada de PUBLIC. A primeira versão deste
-- arquivo revogava só de PUBLIC; as 5 funções foram criadas, o script disse
-- "Success", e has_function_privilege('anon', ...) continuou true em todas.
-- Revogar de um dos dois não basta: tem que ser dos dois.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- validar_atividade_rdo — o revisor aprova uma atividade
-- ----------------------------------------------------------------------------
-- Painel/index.html:976. Recebe atividades.id (o uuid do banco, que é o que
-- listar_relatorios_painel devolve), não o uuid do dispositivo.
CREATE OR REPLACE FUNCTION validar_atividade_rdo(p_atividade_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM exige_mfa();

  UPDATE atividades
     SET status_revisao   = 'validado',
         -- some o motivo antigo: se estava devolvida e agora foi aprovada,
         -- manter o texto da devolução só confunde quem olhar depois
         motivo_devolucao = NULL,
         revisado_por     = auth.uid(),
         revisado_em      = now()
   WHERE id = p_atividade_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Atividade não encontrada.';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION validar_atividade_rdo(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION validar_atividade_rdo(uuid) TO authenticated;

-- ----------------------------------------------------------------------------
-- devolver_atividade_rdo — o revisor manda a atividade de volta pro campo
-- ----------------------------------------------------------------------------
-- Painel/index.html:993. Devolve o usuario_id do dono do relatório porque o
-- painel usa esse valor pra chamar a Edge Function enviar-push logo em
-- seguida (linha 997). Pode vir NULL -- relatório sincronizado antes do
-- login não tem dono, e aí não há pra quem notificar; o painel já trata isso
-- com `if (usuarioId)`.
CREATE OR REPLACE FUNCTION devolver_atividade_rdo(p_atividade_id uuid, p_motivo text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_relatorio_id uuid;
  v_usuario_id   uuid;
BEGIN
  PERFORM exige_mfa();

  -- Devolver sem dizer o porquê não ajuda ninguém no campo.
  IF trim(coalesce(p_motivo, '')) = '' THEN
    RAISE EXCEPTION 'Descreva o motivo da devolução.';
  END IF;

  UPDATE atividades
     SET status_revisao   = 'devolvido',
         motivo_devolucao = trim(p_motivo),
         revisado_por     = auth.uid(),
         revisado_em      = now()
   WHERE id = p_atividade_id
  RETURNING relatorio_id INTO v_relatorio_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Atividade não encontrada.';
  END IF;

  SELECT criado_por INTO v_usuario_id FROM relatorios WHERE id = v_relatorio_id;

  RETURN jsonb_build_object('usuario_id', v_usuario_id);
END;
$$;
REVOKE ALL ON FUNCTION devolver_atividade_rdo(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION devolver_atividade_rdo(uuid, text) TO authenticated;

-- ----------------------------------------------------------------------------
-- verificar_atividades_devolvidas — o PWA pergunta "tem algo pra eu corrigir?"
-- ----------------------------------------------------------------------------
-- PWA/index.html:554. Não recebe parâmetro nenhum de propósito: usa auth.uid()
-- por dentro. Se recebesse um id, qualquer um poderia mandar o id de outra
-- pessoa e ler as devoluções dela.
--
-- Devolve uuid_atividade_dispositivo como 'atividade_id' -- é esse o id que o
-- PWA conhece (index.html:1610 casa `d.atividade_id === a.id`, onde `a.id` é
-- o id local no IndexedDB). Mandar atividades.id daqui não casaria com nada.
CREATE OR REPLACE FUNCTION verificar_atividades_devolvidas()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'relatorio_uuid_dispositivo', r.uuid_dispositivo,
    'fazenda',                    r.fazenda,
    'data_relatorio',             r.data_relatorio,
    'atividade_id',               a.uuid_atividade_dispositivo,
    'tipo_atividade',             a.tipo_atividade,
    'motivo_devolucao',           a.motivo_devolucao,
    'revisado_em',                a.revisado_em
  ) ORDER BY a.revisado_em DESC), '[]'::jsonb)
  FROM atividades a
  JOIN relatorios r ON r.id = a.relatorio_id
  WHERE r.criado_por = auth.uid()
    AND a.status_revisao = 'devolvido';
$$;
REVOKE ALL ON FUNCTION verificar_atividades_devolvidas() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION verificar_atividades_devolvidas() TO authenticated;

-- ----------------------------------------------------------------------------
-- salvar_push_subscription — o PWA registra o aparelho pra receber push
-- ----------------------------------------------------------------------------
-- PWA/index.html:594. Mesma ideia: o usuário vem de auth.uid(), não do
-- parâmetro. O ON CONFLICT existe porque o navegador pode renovar as chaves
-- de um endpoint que já está cadastrado -- é atualização, não inscrição nova.
CREATE OR REPLACE FUNCTION salvar_push_subscription(
  p_endpoint text,
  p_p256dh   text,
  p_auth     text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'É preciso estar logado.';
  END IF;
  IF p_endpoint IS NULL OR p_p256dh IS NULL OR p_auth IS NULL THEN
    RAISE EXCEPTION 'Dados de inscrição incompletos.';
  END IF;

  INSERT INTO push_subscriptions (usuario_id, endpoint, p256dh, auth)
  VALUES (auth.uid(), p_endpoint, p_p256dh, p_auth)
  ON CONFLICT (usuario_id, endpoint) DO UPDATE SET
    p256dh = EXCLUDED.p256dh,
    auth   = EXCLUDED.auth;
END;
$$;
REVOKE ALL ON FUNCTION salvar_push_subscription(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION salvar_push_subscription(text, text, text) TO authenticated;

-- ----------------------------------------------------------------------------
-- listar_relatorios_painel — acrescenta o status de revisão de cada atividade
-- ----------------------------------------------------------------------------
-- Única mudança em relação ao que está no banco hoje: os campos
-- status_revisao, motivo_devolucao e revisado_em dentro de cada atividade.
-- O Painel lê o primeiro em index.html:952 pra escolher o badge, e o segundo
-- em :960 pra mostrar o motivo. Sem isso o painel novo mostra tudo como
-- "Pendente de revisão", porque `a.status_revisao || "pendente"` cai sempre
-- no lado direito do ||.
-- Os DEFAULT abaixo não são enfeite: a versão que JÁ está no banco tem todos
-- os cinco parâmetros com default, e o CREATE OR REPLACE sobrescreve isso.
-- Sem eles, uma chamada por PostgREST que omitisse qualquer parâmetro deixaria
-- de resolver a função ("could not find function"). O Painel manda os cinco
-- (index.html:471-473), então hoje não quebraria nada -- mas tirar um default
-- que existe é remover capacidade sem ninguém ter pedido.
CREATE OR REPLACE FUNCTION listar_relatorios_painel(
  p_data_inicio date    DEFAULT NULL,
  p_data_fim    date    DEFAULT NULL,
  p_cliente     text    DEFAULT NULL,
  p_fazenda     text    DEFAULT NULL,
  p_limite      integer DEFAULT 200
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
          'tipo_atividade', a.tipo_atividade,
          'up', a.up,
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
          'equipamentos', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('equipamento', e.equipamento, 'operador', e.operador)), '[]'::jsonb)
            FROM atividade_equipamentos e WHERE e.atividade_id = a.id
          ),
          'maquinas', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('equipamento', m.equipamento, 'operador', m.operador, 'dados', m.dados)), '[]'::jsonb)
            FROM atividade_maquinas m WHERE m.atividade_id = a.id
          ),
          'fotos', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('storage_path', f.storage_path)), '[]'::jsonb)
            FROM evidencias_fotos f WHERE f.atividade_id = a.id
          )
        ) ORDER BY a.ordem), '[]'::jsonb)
        FROM atividades a WHERE a.relatorio_id = rel.id
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
$$;
REVOKE ALL ON FUNCTION listar_relatorios_painel(date, date, text, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION listar_relatorios_painel(date, date, text, text, integer) TO authenticated;

-- ============================================================================
-- CONFERÊNCIA
-- ============================================================================
-- 1) As 5 funções existem e nenhuma sobrou liberada pra anon.
--    Esperado: 5 linhas, todas com anon_pode = false.
SELECT p.proname,
       has_function_privilege('anon', p.oid, 'EXECUTE')          AS anon_pode,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_pode
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('validar_atividade_rdo','devolver_atividade_rdo',
                     'verificar_atividades_devolvidas','salvar_push_subscription',
                     'listar_relatorios_painel')
 ORDER BY p.proname;

-- 2) Teste de negativa -- as duas do painel devem FALHAR aqui.
--    No SQL Editor você é postgres, sem JWT nenhum, então auth.uid() é NULL e
--    o exige_mfa() para já no primeiro IF: a mensagem esperada é
--    "Sessão inválida — faça login para continuar." (e NÃO a de 2FA, que só
--    aparece pra quem tem sessão válida mas ainda não confirmou o código).
--    Qualquer uma das duas serve como prova; o que não pode é executar.
--    Se passar, o exige_mfa() não está fazendo efeito -- pare e investigue.
--
-- SELECT validar_atividade_rdo('00000000-0000-0000-0000-000000000000');
-- SELECT devolver_atividade_rdo('00000000-0000-0000-0000-000000000000', 'teste');
