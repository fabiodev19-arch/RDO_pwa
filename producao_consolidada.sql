-- producao_consolidada.sql
--
-- Traz para o banco a fórmula que hoje mora na coluna Z da planilha
-- "PRODUTIVIDADE ENC MAIKON", e faz listar_relatorios_painel devolver as
-- PRODUÇÕES já montadas, em vez de o painel remontá-las no navegador.
--
-- Por que no servidor: produção consolidada é o número que vira faturamento.
-- BOAS_PRATICAS §2 -- "qualquer número que vira dinheiro tem que ser
-- recalculado no servidor, nunca aceito como veio no payload". Calcular no
-- painel também obrigaria a baixar o catálogo de tarifas inteiro só para
-- descobrir a unidade de cada linha.
--
-- ---------------------------------------------------------------------------
-- A granularidade: uma linha por PRODUÇÃO, não por apontamento
-- ---------------------------------------------------------------------------
-- Um apontamento pode valer uma produção ou várias, e quem decide é o
-- formulário (regras_negocio, tipo_regra = 'formulario_atividade'):
--
--   padrão de obra      -> as medidas ficam na atividade      -> 1 produção
--   máquinas detalhado  -> cada máquina tem medidas próprias  -> N produções
--   hora máquina        -> cada máquina tem suas horas        -> N produções
--
-- Não é escolha de layout: é como o dado existe. No detalhado, cada máquina
-- guarda up, trecho, comprimento, largura, profundidade, quantidade e horas em
-- atividade_maquinas.dados -- é um apontamento completo. E é também a forma da
-- planilha, onde cada linha tem um ID MÁQUINA com as medidas dele.
--
-- Consequência que importa: a DESCRIÇÃO (e portanto a tarifa e a unidade)
-- acompanha a produção, não a atividade. Num apontamento detalhado a
-- escavadeira pode estar em M³ e o caminhão em HT, no mesmo serviço. Por isso a
-- descrição da máquina é lida de dados->>'descricao', enquanto o padrão de obra
-- usa atividades.descricao_atividade.
--
-- A descrição por máquina não precisou de DDL: 'dados' é jsonb livre e já
-- recebe o que o PWA mandar, do mesmo jeito que quantidade e hora_inicial.

-- ---------------------------------------------------------------------------
-- 1. A fórmula
-- ---------------------------------------------------------------------------
-- Cópia fiel da coluna Z da planilha:
--
--   =IFERROR(IF(E<>"", E, IF(AND(E="", W="HT"), (J-I), (G*F))), "SEM DADOS")
--
--   E = QTD. UND.   W = U.M. TARIFA   I/J = hora inicial/final   F/G = compr./larg.
--
-- IMMUTABLE porque só depende dos argumentos -- deixa o Postgres reaproveitar o
-- resultado e permite usar em índice, se um dia precisar.
--
-- PENDÊNCIA CONHECIDA, e é da planilha, não da tradução: só 'HT' consolida por
-- horas. O catálogo também tem 'HD' (9 itens) e 'DIÁRIA' (11), que não são
-- área e mesmo assim caem em largura × comprimento. Pode ser que essas linhas
-- sempre venham com quantidade preenchida, e aí nunca chegam nesse ramo -- ou
-- pode ser um furo que ninguém notou. Perguntado ao Fábio em 09/09, sem
-- resposta ainda. Mantido idêntico ao Excel de propósito: divergir aqui faria o
-- painel discordar do número que o escritório usa hoje, e um relatório que
-- discorda do outro é pior que um relatório com um furo conhecido.
CREATE OR REPLACE FUNCTION public.producao_consolidada(
  p_quantidade    numeric,
  p_unidade       text,
  p_hora_inicial  numeric,
  p_hora_final    numeric,
  p_comprimento_m numeric,
  p_largura_m     numeric
) RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_quantidade IS NOT NULL THEN p_quantidade
    WHEN p_unidade = 'HT' THEN
      CASE WHEN p_hora_final IS NULL OR p_hora_inicial IS NULL THEN NULL
           ELSE p_hora_final - p_hora_inicial END
    ELSE
      CASE WHEN p_comprimento_m IS NULL OR p_largura_m IS NULL THEN NULL
           ELSE p_comprimento_m * p_largura_m END
  END;
$$;

COMMENT ON FUNCTION public.producao_consolidada(numeric,text,numeric,numeric,numeric,numeric) IS
  'Produção consolidada de uma linha de apontamento, igual à coluna Z da planilha de produtividade: quantidade, senão horas quando a unidade é HT, senão largura x comprimento.';

-- As duas linhas de sempre (BOAS_PRATICAS §2). É função de cálculo puro, sem
-- acesso a tabela, mas a regra não abre exceção -- e anon não tem por que
-- alcançá-la.
REVOKE ALL ON FUNCTION public.producao_consolidada(numeric,text,numeric,numeric,numeric,numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.producao_consolidada(numeric,text,numeric,numeric,numeric,numeric) TO authenticated;


-- ---------------------------------------------------------------------------
-- 2. listar_relatorios_painel devolve 'producoes'
-- ---------------------------------------------------------------------------
-- Cada apontamento passa a trazer, além dos campos de sempre, um array
-- 'producoes' com uma entrada por linha de produção -- já com descrição,
-- código, unidade e o número consolidado. O painel só desenha.
--
-- Como se decide se são N produções ou uma: pela presença de máquinas com
-- 'dados' preenchido, e NÃO pelo cadastro de formulário. O cadastro
-- 'formulario_atividade' tem regra para 5 atividades apenas; as demais caem no
-- padrão por omissão. Se a decisão dependesse dele, um apontamento detalhado de
-- atividade sem regra cadastrada perderia as produções das máquinas em
-- silêncio. O dado gravado é a fonte mais confiável aqui do que o cadastro.
CREATE OR REPLACE FUNCTION public.listar_relatorios_painel(
  p_data_inicio date DEFAULT NULL::date,
  p_data_fim date DEFAULT NULL::date,
  p_cliente text DEFAULT NULL::text,
  p_fazenda text DEFAULT NULL::text,
  p_limite integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
          'numero', a.numero,
          'tipo_atividade', a.tipo_atividade,
          'descricao_atividade', a.descricao_atividade,
          'codigo_tarifa', tar.valor->>'codigo',
          'unidade_tarifa', tar.valor->>'unidade',
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
          'excluido_em', a.excluido_em,
          'status_anterior_exclusao',
            CASE WHEN a.excluido_em IS NOT NULL THEN a.status_revisao ELSE NULL END,

          -- ----- as linhas de produção -----
          'producoes', COALESCE(
            -- caminho 1: máquinas com medidas próprias (detalhado / hora máquina)
            (
              SELECT jsonb_agg(jsonb_build_object(
                'origem', 'maquina',
                'equipamento', m.equipamento,
                'operador', m.operador,
                'descricao_atividade', coalesce(m.dados->>'descricao', a.descricao_atividade),
                'codigo_tarifa',  tm.valor->>'codigo',
                'unidade_tarifa', tm.valor->>'unidade',
                'up',            coalesce(m.dados->>'up', a.up),
                'trecho',        coalesce(m.dados->>'trecho', a.trecho),
                'quantidade',      (m.dados->>'quantidade')::numeric,
                'hora_inicial',    (m.dados->>'hora_inicial')::numeric,
                'hora_final',      (m.dados->>'hora_final')::numeric,
                'comprimento_m',   (m.dados->>'comprimento_m')::numeric,
                'largura_m',       (m.dados->>'largura_m')::numeric,
                'profundidade_cm', (m.dados->>'profundidade_cm')::numeric,
                'observacao',      m.dados->>'observacao',
                'producao', producao_consolidada(
                  (m.dados->>'quantidade')::numeric,
                  tm.valor->>'unidade',
                  (m.dados->>'hora_inicial')::numeric,
                  (m.dados->>'hora_final')::numeric,
                  (m.dados->>'comprimento_m')::numeric,
                  (m.dados->>'largura_m')::numeric
                )
              ) ORDER BY m.id)
              FROM atividade_maquinas m
              LEFT JOIN regras_negocio tm
                     ON tm.tipo_regra = 'tarifa_descricao'
                    AND tm.chave = coalesce(m.dados->>'descricao', a.descricao_atividade)
                    AND tm.ativo
             WHERE m.atividade_id = a.id
               AND m.dados IS NOT NULL
               AND m.dados <> '{}'::jsonb
            ),
            -- caminho 2: padrão de obra -- as medidas são do apontamento, e as
            -- máquinas/equipamentos apenas participaram dele. Uma produção só.
            jsonb_build_array(jsonb_build_object(
              'origem', 'atividade',
              'equipamento', NULL,
              'operador', NULL,
              'descricao_atividade', a.descricao_atividade,
              'codigo_tarifa',  tar.valor->>'codigo',
              'unidade_tarifa', tar.valor->>'unidade',
              'up', a.up,
              'trecho', a.trecho,
              'quantidade', NULL,
              'hora_inicial', NULL,
              'hora_final', NULL,
              'comprimento_m', a.comprimento_m,
              'largura_m', a.largura_m,
              'profundidade_cm', a.profundidade_cm,
              'observacao', a.observacao,
              'producao', producao_consolidada(
                NULL, tar.valor->>'unidade', NULL, NULL, a.comprimento_m, a.largura_m
              )
            ))
          ),

          'equipamentos', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('equipamento', e.equipamento, 'operador', e.operador)), '[]'::jsonb)
            FROM atividade_equipamentos e WHERE e.atividade_id = a.id
          ),
          'maquinas', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('equipamento', m2.equipamento, 'operador', m2.operador, 'dados', m2.dados)), '[]'::jsonb)
            FROM atividade_maquinas m2 WHERE m2.atividade_id = a.id
          ),
          'fotos', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('storage_path', f.storage_path)), '[]'::jsonb)
            FROM evidencias_fotos f WHERE f.atividade_id = a.id
          )
        ) ORDER BY (a.excluido_em IS NOT NULL), a.ordem), '[]'::jsonb)
        FROM atividades a
        -- LEFT: apontamento sem descrição (o campo é opcional) continua
        -- aparecendo, só que sem código nem unidade. Um JOIN comum sumiria com
        -- ele da tela do revisor, que é justamente quem precisa cobrar.
        LEFT JOIN regras_negocio tar
               ON tar.tipo_regra = 'tarifa_descricao'
              AND tar.chave = a.descricao_atividade
              AND tar.ativo
        WHERE a.relatorio_id = rel.id
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
$function$;

REVOKE ALL ON FUNCTION public.listar_relatorios_painel(date,date,text,text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.listar_relatorios_painel(date,date,text,text,integer) TO authenticated;
