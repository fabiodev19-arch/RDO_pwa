-- salvar_descricao_tarifa.sql
--
-- Pedido do Fábio (17/09): "eu subi a tabela justamente para você criar essa
-- guia para podermos ter dinamismo também para quando mudar um valor
-- (tarifa) de uma atividade, podermos gerenciar isso nos cadastros" -- ou
-- seja, ele quer editar código/unidade/valor de uma descrição direto pelo
-- Painel, sem precisar me pedir para rodar SQL a cada mudança.
--
-- Por que NÃO reaproveitar salvar_cadastro (a RPC genérica que toda outra
-- categoria usa): ela passa o texto por normalizar_texto_cadastro(), que
-- TIRA ACENTO ("CONSTRUÇÃO" -> "CONSTRUCAO"). Para as outras 14 categorias
-- isso não importa. Para esta, importa MUITO: o texto da descrição É A
-- CHAVE usada em regras_negocio (tarifa_descricao, formulario_descricao,
-- campos_ocultos_descricao). Se o texto perdesse o acento ao ser salvo, a
-- ligação com as regras já configuradas quebraria -- e o operador passaria
-- a ver "CONSTRUCAO DE ATERRO - M3" no PWA, destoando das outras 111
-- descrições do catálogo, que têm acento. Confirmado testando a função
-- direto no banco antes de escrever esta: o translate() dela não trata "M³"
-- mas trata Ç/Ã/Õ etc., então o efeito é real e silencioso.
--
-- O que esta função faz, numa chamada só (evita duas idas ao servidor do
-- client, e garante que cadastro + tarifa nunca fiquem dessincronizados):
--   1. upsert em cadastros (categoria='descricao_atividade'), SEM normalizar
--      o texto -- só upper(trim()), que mantém o padrão maiúsculo já usado
--      nas 112 descrições, sem tocar em acento.
--   2. upsert em regras_negocio (tipo_regra='tarifa_descricao'), com a MESMA
--      chave, guardando codigo/unidade/valor_unitario no mesmo formato já
--      usado desde 09-10/09 e 17/09.
--
-- Ao EDITAR (p_id preenchido), o texto da descrição NÃO pode ser trocado --
-- ela é ignorada nesse caminho, e o texto já gravado no banco é reusado como
-- chave. Trocar o texto de uma descrição já configurada quebraria
-- formulario_descricao e campos_ocultos_descricao, que apontam pra ela pelo
-- texto antigo -- migrar essas duas regras junto seria possível, mas não foi
-- pedido ("quando mudar um VALOR"), e é risco desnecessário para o que foi
-- pedido agora. Só código, unidade, valor e ativo são editáveis.
--
-- "Desativar" continua usando excluir_cadastro() (a RPC genérica) -- ela só
-- muda `ativo`, nunca toca no texto, então é segura para esta categoria
-- também. "Reativar" passa por AQUI (não por salvar_cadastro), reenviando
-- os dados atuais com p_ativo=true -- é o único jeito de reativar sem correr
-- o risco de re-normalizar o texto no caminho genérico.
--
-- Aditivo (CLAUDE.md §1.1): função nova via CREATE OR REPLACE, nenhuma
-- tabela/coluna alterada.

CREATE OR REPLACE FUNCTION public.salvar_descricao_tarifa(
  p_id uuid DEFAULT NULL,
  p_descricao text DEFAULT NULL,
  p_codigo text DEFAULT NULL,
  p_unidade text DEFAULT NULL,
  p_valor_unitario numeric DEFAULT NULL,
  p_ativo boolean DEFAULT true
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cad_id uuid;
  v_descricao_final text;
BEGIN
  PERFORM exige_mfa();

  IF trim(coalesce(p_codigo, '')) = '' OR trim(coalesce(p_unidade, '')) = ''
     OR p_valor_unitario IS NULL THEN
    RAISE EXCEPTION 'Código, unidade e valor são obrigatórios.';
  END IF;
  IF p_valor_unitario <= 0 THEN
    RAISE EXCEPTION 'O valor precisa ser maior que zero.';
  END IF;

  BEGIN
    IF p_id IS NULL THEN
      -- criar: exige descrição, e normaliza só maiúscula/espaço -- NUNCA
      -- acento (ver comentário do topo).
      IF trim(coalesce(p_descricao, '')) = '' THEN
        RAISE EXCEPTION 'Descrição é obrigatória.';
      END IF;
      v_descricao_final := upper(trim(p_descricao));

      INSERT INTO cadastros (categoria, valor, ativo, ordem)
      VALUES ('descricao_atividade', v_descricao_final, coalesce(p_ativo, true),
              (SELECT coalesce(max(ordem), 0) + 1 FROM cadastros WHERE categoria = 'descricao_atividade'))
      RETURNING id INTO v_cad_id;
    ELSE
      -- editar/reativar: o texto NÃO muda -- vem do que já está gravado,
      -- ignorando p_descricao de propósito (ver comentário do topo).
      UPDATE cadastros
      SET ativo = coalesce(p_ativo, true)
      WHERE id = p_id AND categoria = 'descricao_atividade'
      RETURNING id, valor INTO v_cad_id, v_descricao_final;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Descrição não encontrada.';
      END IF;
    END IF;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Essa descrição já existe no catálogo.';
  END;

  INSERT INTO regras_negocio (tipo_regra, chave, valor, ativo)
  VALUES (
    'tarifa_descricao', v_descricao_final,
    jsonb_build_object('codigo', p_codigo, 'unidade', p_unidade, 'valor_unitario', p_valor_unitario),
    true
  )
  ON CONFLICT (tipo_regra, chave) DO UPDATE SET
    valor = EXCLUDED.valor, ativo = true;

  RETURN jsonb_build_object('id', v_cad_id, 'descricao', v_descricao_final);
END;
$function$;

-- As duas linhas de sempre (BOAS_PRATICAS.md §2).
REVOKE ALL ON FUNCTION public.salvar_descricao_tarifa(uuid, text, text, text, numeric, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.salvar_descricao_tarifa(uuid, text, text, text, numeric, boolean) TO authenticated;
