-- trava_validacao_repetida.sql
--
-- Notado pelo Fábio em 10/09: "eu consigo validar a mesma atividade várias
-- vezes sem critério algum... validou uma vez não é necessário validar de
-- novo". Está certo, e a função de fato não olhava o status antes de gravar.
--
-- O que acontecia: cada clique repetido regravava revisado_por e revisado_em.
-- Não corrompia o status (continuava 'validado'), mas apagava a marca de QUEM
-- validou primeiro e QUANDO -- justamente a informação que a coluna existe para
-- guardar. Numa conferência de faturamento, "validado por Fulano às 14h" virava
-- "validado por Sicrano às 17h" porque alguém clicou de novo sem querer.
--
-- É a mesma família da trava_devolucao_alternada.sql: ação que não muda estado
-- nenhum mas deixa rastro, e por isso não pode ser repetível.
--
-- O QUE CONTINUA PERMITIDO, de propósito:
--
--   validar uma PENDENTE   -> é o caminho normal.
--   validar uma DEVOLVIDA  -> o revisor mudou de ideia; já era permitido antes
--                             e continua. O estado anterior não era 'validado'.
--   devolver uma VALIDADA  -> corrige aprovação equivocada (a outra trava já
--                             trata esse caso).
--
-- Ou seja: o que se recusa é APENAS validar o que já está validado.
--
-- O FOR UPDATE não é enfeite. Sem ele, dois cliques quase simultâneos poderiam
-- ler 'pendente' os dois e gravar duas vezes -- que é exatamente o cenário do
-- clique repetido que originou este arquivo. Mesma razão da trava de devolução.

CREATE OR REPLACE FUNCTION public.validar_atividade_rdo(p_atividade_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status text;
BEGIN
  PERFORM exige_mfa();

  SELECT status_revisao INTO v_status
    FROM atividades
   WHERE id = p_atividade_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Atividade não encontrada.';
  END IF;

  IF v_status = 'validado' THEN
    RAISE EXCEPTION 'Este apontamento já foi validado. Para revisar de novo, devolva para correção.';
  END IF;

  UPDATE atividades
     SET status_revisao   = 'validado',
         motivo_devolucao = NULL,
         revisado_por     = auth.uid(),
         revisado_em      = now()
   WHERE id = p_atividade_id;
END;
$function$;

-- As duas linhas de sempre (BOAS_PRATICAS.md §2).
REVOKE ALL ON FUNCTION public.validar_atividade_rdo(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.validar_atividade_rdo(uuid) TO authenticated;
