-- ============================================================================
-- GTM RDO — devolver exige que o campo tenha respondido antes
-- ============================================================================
-- Arquivo 6 da leva. Rodar depois do exclusao_marcada_atividade.sql.
--
-- A REGRA (definida pelo Fábio em 2026-09-08):
--
--   painel devolve -> encarregado edita e reenvia -> painel pode devolver de
--   novo, se vier errado outra vez.
--
-- Cada um faz a sua parte, e um lado não age duas vezes seguidas.
--
-- O QUE ACONTECIA ANTES:
--
-- Depois de devolver, o botão "Devolver" continuava habilitado. Clicar de novo
-- funcionava: regravava o motivo, atualizava revisado_em e -- o que importa --
-- disparava OUTRA notificação push para o operador. Como a atividade já estava
-- devolvida, nada mudava de estado; só chegava mais um aviso do mesmo pedido.
--
-- Em campo isso é ruim de duas formas: o operador recebe avisos repetidos de
-- algo que já sabe, e o revisor não tem sinal de que a primeira devolução foi
-- registrada -- o que convida a clicar mais uma vez.
--
-- A trava mora AQUI, no servidor, e não só no botão do painel. Botão
-- desabilitado é conveniência; quem garante a regra é o banco (BOAS_PRATICAS
-- §2: se o cliente pode mentir sobre um valor e isso importa, o servidor
-- decide).
--
-- O QUE CONTINUA PERMITIDO, de propósito:
--
-- - Validar uma atividade devolvida. É o revisor mudando de ideia ("olhei de
--   novo, está certo"), não uma ação repetida. E validar não notifica ninguém,
--   então não gera o incômodo que esta trava existe para evitar.
-- - Devolver uma atividade validada. É corrigir uma aprovação equivocada, e o
--   estado anterior não era "devolvido" -- a alternância continua respeitada.
-- ============================================================================

CREATE OR REPLACE FUNCTION devolver_atividade_rdo(p_atividade_id uuid, p_motivo text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_relatorio_id uuid;
  v_usuario_id   uuid;
  v_status_atual text;
BEGIN
  PERFORM exige_mfa();

  IF trim(coalesce(p_motivo, '')) = '' THEN
    RAISE EXCEPTION 'Descreva o motivo da devolução.';
  END IF;

  -- Lê o estado ANTES de escrever. O FOR UPDATE segura a linha até o fim da
  -- transação: sem ele, dois cliques quase simultâneos (ou dois revisores)
  -- poderiam ler 'pendente' os dois e devolver duas vezes, que é exatamente
  -- o que este arquivo evita.
  SELECT status_revisao INTO v_status_atual
    FROM atividades WHERE id = p_atividade_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Atividade não encontrada.';
  END IF;

  IF v_status_atual = 'devolvido' THEN
    RAISE EXCEPTION 'Esta atividade já foi devolvida e está aguardando a correção do encarregado. Só dá para devolver de novo depois que ela for reenviada do campo.';
  END IF;

  UPDATE atividades
     SET status_revisao   = 'devolvido',
         motivo_devolucao = trim(p_motivo),
         revisado_por     = auth.uid(),
         revisado_em      = now()
   WHERE id = p_atividade_id
  RETURNING relatorio_id INTO v_relatorio_id;

  SELECT criado_por INTO v_usuario_id FROM relatorios WHERE id = v_relatorio_id;

  RETURN jsonb_build_object('usuario_id', v_usuario_id);
END;
$$;
REVOKE ALL ON FUNCTION devolver_atividade_rdo(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION devolver_atividade_rdo(uuid, text) TO authenticated;

-- ============================================================================
-- CONFERÊNCIA -- esperado: 'devolvido' recusa, 'pendente' e 'validado' passam.
-- Roda em transação e desfaz tudo no fim.
-- ============================================================================
-- BEGIN;
--   -- crie uma atividade de teste, devolva uma vez, e tente devolver de novo:
--   -- a segunda chamada tem que levantar exceção com a mensagem acima.
-- ROLLBACK;
