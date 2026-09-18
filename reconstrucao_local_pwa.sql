-- Reconstrução local do PWA (18/09) -- Pedido do Fábio: já que o aparelho
-- pode perder o IndexedDB por conta própria (cache/dados do site limpos,
-- aparelho trocado -- não só pela poda de 30 dias que já existe), o que já
-- SUBIU pro banco não pode ficar irrecuperável. Rascunho nunca sincronizado
-- continua sem solução possível (nunca existiu aqui) -- decisão do Fábio,
-- aceita: refazer um rascunho é sempre uma opção real, e a chance de perder
-- justamente um rascunho no meio de uma limpeza de dados é baixa.
--
-- Esta função devolve os relatórios do PRÓPRIO usuário logado (criado_por =
-- auth.uid()), no MESMO formato que o PWA já usa localmente -- o app monta
-- de volta sem precisar traduzir nome de campo. O ponto que importa de
-- verdade: cada máquina volta com `id` = uuid_maquina_dispositivo, o MESMO
-- valor que o servidor guarda em producao_devolvida_maquina_uuid. É o que
-- faz a trava de edição (maquinaTravada, 18/09) reconhecer a produção
-- certa depois de uma reconstrução -- sem isso o problema que a falha
-- aberta contorna (nenhuma máquina local bate) voltaria a acontecer, só que
-- por um caminho diferente.
--
-- Atividade excluída no aparelho (excluido_em) NÃO volta -- o operador já
-- tinha decidido tirá-la da tela; reconstruir não é desfazer essa escolha.
--
-- Fotos voltam só com o caminho (storage_path); a URL assinada é gerada
-- pelo PRÓPRIO PWA, client-side, com a policy de leitura que já existe pra
-- authenticated (não precisa de mudança de Storage). Ver comentário no
-- index.html sobre o limite disso: a assinatura tem validade de 1h e não é
-- renovada sozinha depois -- rascunho de segurança suficiente pro que este
-- recurso resolve (não perder o dado, não manter a foto acessível pra
-- sempre sem reabrir).
CREATE OR REPLACE FUNCTION public.listar_meus_relatorios_pwa()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_resultado jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'É preciso estar logado.';
  END IF;

  SELECT coalesce(jsonb_agg(r), '[]'::jsonb) INTO v_resultado
  FROM (
    SELECT jsonb_build_object(
      'id', rel.uuid_dispositivo,
      'empresa', rel.empresa,
      'cliente', rel.cliente, 'contrato', rel.contrato, 'faena', rel.faena,
      'tipo_estrada', rel.tipo_estrada, 'equipe_frente', rel.equipe_frente,
      'fazenda', rel.fazenda, 'data', rel.data_relatorio,
      'encarregado', rel.encarregado, 'supervisor', rel.supervisor,
      'tecnico_arauco', rel.tecnico_arauco, 'supervisor_arauco', rel.supervisor_arauco,
      'gps', CASE WHEN rel.gps_lat IS NULL THEN NULL ELSE jsonb_build_object(
        'lat', rel.gps_lat, 'lng', rel.gps_lng,
        'precisao', rel.gps_precisao, 'capturadoEm', rel.gps_capturado_em
      ) END,
      'status', 'concluido',
      'syncStatus', 'sincronizado',
      'rpcSincronizado', true,
      'criadoEm', rel.criado_em,
      'concluidoEm', rel.concluido_em,
      'sincronizadoEm', rel.sincronizado_em,
      'atividades', (
        SELECT coalesce(jsonb_agg(jsonb_build_object(
          'id', a.uuid_atividade_dispositivo,
          'numero', a.numero,
          'tipo_atividade', a.tipo_atividade,
          'descricao_atividade', a.descricao_atividade,
          'up', a.up,
          'dimensao_m', a.dimensao_m,
          'comprimento_m', a.comprimento_m, 'largura_m', a.largura_m,
          'profundidade_cm', a.profundidade_cm,
          'dmt_km_inicial', a.dmt_km_inicial, 'dmt_km_final', a.dmt_km_final,
          'trecho', a.trecho, 'tipo', a.tipo, 'observacao', a.observacao,
          'data_execucao', a.data_execucao,
          -- Já sincronizada por definição (só está aqui porque um dia subiu) --
          -- enviadaEm é a marca local que trava excluir/editar por cima da
          -- correção pendente (ver "reabri, logo posso apagar", 08/09).
          'enviadaEm', a.criado_em,
          'equipamentos', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
              'equipamento', e.equipamento, 'operador', e.operador
            )), '[]'::jsonb)
            FROM atividade_equipamentos e WHERE e.atividade_id = a.id
          ),
          'maquinas', (
            SELECT coalesce(jsonb_agg(
              jsonb_build_object('id', m.uuid_maquina_dispositivo,
                                  'equipamento', m.equipamento, 'operador', m.operador)
              || coalesce(m.dados, '{}'::jsonb)
              ORDER BY m.id
            ), '[]'::jsonb)
            FROM atividade_maquinas m WHERE m.atividade_id = a.id
          ),
          'fotos', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('storagePath', f.storage_path)), '[]'::jsonb)
            FROM evidencias_fotos f WHERE f.atividade_id = a.id
          )
        ) ORDER BY a.ordem), '[]'::jsonb)
        FROM atividades a
        WHERE a.relatorio_id = rel.id AND a.excluido_em IS NULL
      )
    ) AS r
    FROM relatorios rel
    WHERE rel.criado_por = auth.uid()
  ) sub;

  RETURN v_resultado;
END;
$function$;

REVOKE ALL ON FUNCTION public.listar_meus_relatorios_pwa() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.listar_meus_relatorios_pwa() TO authenticated;
