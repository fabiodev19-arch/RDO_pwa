-- Retenção local do PWA (18/09) -- Pedido do Fábio: já que dá para corrigir
-- direto pelo painel (editar_atividade_rdo), o aparelho não precisa guardar
-- relatório sincronizado para sempre. Depois de 30 dias sem mudar, o PWA
-- apaga o relatório do IndexedDB local (index.html, podarRelatoriosAntigos)
-- -- mas só se nada nele estiver aguardando correção, senão a devolução
-- chegaria e não haveria mais o que corrigir no aparelho.
--
-- A poda em si é só do lado do cliente (o servidor não tem como apagar
-- IndexedDB de ninguém). O que este arquivo faz é fechar o outro lado do
-- mesmo risco: impedir que o painel DEVOLVA um apontamento velho o
-- suficiente para já ter sido podado. O botão desabilitado no painel é
-- conveniência (evita o clique); quem garante de verdade é esta função --
-- mesmo padrão já usado pela alternância obrigatória de devolução.
--
-- O prazo (30 dias) precisa ficar igual nos três lugares: aqui,
-- PWA/RDO/RDO/index.html (DIAS_RETENCAO_LOCAL) e Painel/index.html
-- (DIAS_RETENCAO_LOCAL). Divergir faria o painel bloquear cedo ou tarde
-- demais em relação ao que o aparelho realmente ainda guarda.

CREATE OR REPLACE FUNCTION public.devolver_atividade_rdo(p_atividade_id uuid, p_motivo text, p_indice_producao integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_relatorio_id    uuid;
  v_usuario_id      uuid;
  v_status_atual    text;
  v_sincronizado_em timestamptz;
BEGIN
  PERFORM exige_mfa();

  IF trim(coalesce(p_motivo, '')) = '' THEN
    RAISE EXCEPTION 'Descreva o motivo da devolução.';
  END IF;

  SELECT status_revisao, relatorio_id INTO v_status_atual, v_relatorio_id
    FROM atividades WHERE id = p_atividade_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Atividade não encontrada.';
  END IF;

  IF v_status_atual = 'devolvido' THEN
    RAISE EXCEPTION 'Esta atividade já foi devolvida e está aguardando a correção do encarregado. Só dá para devolver de novo depois que ela for reenviada do campo.';
  END IF;

  SELECT sincronizado_em INTO v_sincronizado_em FROM relatorios WHERE id = v_relatorio_id;
  IF v_sincronizado_em IS NOT NULL AND v_sincronizado_em < (now() - interval '30 days') THEN
    RAISE EXCEPTION 'Este apontamento foi sincronizado há mais de 30 dias -- o dado local já pode ter sido removido do aparelho do encarregado. Corrija direto pelo painel (Editar) em vez de devolver.';
  END IF;

  UPDATE atividades
     SET status_revisao            = 'devolvido',
         motivo_devolucao          = trim(p_motivo),
         producao_devolvida_indice = p_indice_producao,
         revisado_por              = auth.uid(),
         revisado_em               = now()
   WHERE id = p_atividade_id
  RETURNING relatorio_id INTO v_relatorio_id;

  SELECT criado_por INTO v_usuario_id FROM relatorios WHERE id = v_relatorio_id;

  RETURN jsonb_build_object('usuario_id', v_usuario_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.devolver_atividade_rdo(uuid,text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.devolver_atividade_rdo(uuid,text,integer) TO authenticated;


CREATE OR REPLACE FUNCTION public.devolver_atividade_rdo(p_atividade_id uuid, p_motivo text, p_maquina_uuid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_relatorio_id    uuid;
  v_usuario_id      uuid;
  v_status_atual    text;
  v_sincronizado_em timestamptz;
BEGIN
  PERFORM exige_mfa();

  IF trim(coalesce(p_motivo, '')) = '' THEN
    RAISE EXCEPTION 'Descreva o motivo da devolução.';
  END IF;

  SELECT status_revisao, relatorio_id INTO v_status_atual, v_relatorio_id
    FROM atividades WHERE id = p_atividade_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Atividade não encontrada.';
  END IF;

  IF v_status_atual = 'devolvido' THEN
    RAISE EXCEPTION 'Esta atividade já foi devolvida e está aguardando a correção do encarregado. Só dá para devolver de novo depois que ela for reenviada do campo.';
  END IF;

  SELECT sincronizado_em INTO v_sincronizado_em FROM relatorios WHERE id = v_relatorio_id;
  IF v_sincronizado_em IS NOT NULL AND v_sincronizado_em < (now() - interval '30 days') THEN
    RAISE EXCEPTION 'Este apontamento foi sincronizado há mais de 30 dias -- o dado local já pode ter sido removido do aparelho do encarregado. Corrija direto pelo painel (Editar) em vez de devolver.';
  END IF;

  IF p_maquina_uuid IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM atividade_maquinas
     WHERE atividade_id = p_atividade_id AND uuid_maquina_dispositivo = p_maquina_uuid
  ) THEN
    RAISE EXCEPTION 'Essa produção não pertence a este apontamento.';
  END IF;

  UPDATE atividades
     SET status_revisao                   = 'devolvido',
         motivo_devolucao                 = trim(p_motivo),
         producao_devolvida_maquina_uuid  = p_maquina_uuid,
         producao_devolvida_indice        = NULL,
         revisado_por                     = auth.uid(),
         revisado_em                      = now()
   WHERE id = p_atividade_id
  RETURNING relatorio_id INTO v_relatorio_id;

  SELECT criado_por INTO v_usuario_id FROM relatorios WHERE id = v_relatorio_id;

  RETURN jsonb_build_object('usuario_id', v_usuario_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.devolver_atividade_rdo(uuid,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.devolver_atividade_rdo(uuid,text,uuid) TO authenticated;
