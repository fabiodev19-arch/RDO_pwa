-- ============================================================================
-- GTM RDO — número visível para rastrear apontamento
-- ============================================================================
-- Arquivo 11 da leva. Pedido do Fábio em 2026-09-09, depois de usar o sistema:
-- "preciso melhorar a forma de rastreio de cada apontamento implantando um ID
-- visual, assim poderemos ver no PWA e no painel o ID de cada apontamento."
--
-- Escolha dele entre as opções: NÚMERO SEQUENCIAL do banco, e não um código
-- derivado do uuid. O motivo é de uso: número curto se lê, se anota num papel
-- e se dita por telefone ("confere o 1247"). Um hex de 8 caracteres não.
--
-- A CONTRAPARTIDA, que é real e precisa estar clara:
--
-- O número nasce no banco, então só existe DEPOIS de sincronizar. Um
-- apontamento criado no aparelho sem sinal fica sem número até subir -- e em
-- campo isso pode durar o dia inteiro. O PWA mostra "sem número ainda" nesse
-- intervalo, em vez de inventar um provisório que depois mudaria: número que
-- muda é pior do que número que ainda não existe.
--
-- POR QUE UMA SEQUENCE E NÃO `GENERATED AS IDENTITY`:
--
-- ADD COLUMN com IDENTITY reescreve a tabela inteira para preencher as linhas
-- que já existem. Aqui são poucas, mas o padrão do projeto é mudança aditiva e
-- previsível -- a sequence deixa cada passo explícito e reversível de ler.
--
-- NOT NULL **com** DEFAULT, na mesma leva: foi exatamente a falta do default
-- em uuid_atividade_dispositivo que derrubou a sincronização do campo em
-- 08/09. Coluna obrigatória que o caminho de escrita não preenche é mudança
-- destrutiva disfarçada de aditiva.
-- ============================================================================

CREATE SEQUENCE IF NOT EXISTS atividades_numero_seq;

ALTER TABLE atividades
  ADD COLUMN IF NOT EXISTS numero bigint;

-- Backfill pela ordem de criação, para os números antigos fazerem sentido
-- cronológico em vez de sair na ordem física da tabela.
--
-- row_number() e NÃO nextval() dentro de um UPDATE ... FROM com ORDER BY:
-- a primeira tentativa usou nextval e os números saíram fora de ordem. O
-- Postgres não promete avaliar a subquery na ordem do ORDER BY -- ele só
-- promete o conjunto de linhas. Aqui é a janela que define a numeração, e daí
-- a ordem é garantida.
WITH ordenadas AS (
  SELECT id, row_number() OVER (ORDER BY criado_em, id) AS n
    FROM atividades
   WHERE numero IS NULL
)
UPDATE atividades a
   SET numero = ordenadas.n
  FROM ordenadas
 WHERE a.id = ordenadas.id;

-- A sequence continua de onde o backfill parou, senão o próximo INSERT
-- colidiria com um número já usado.
SELECT setval('atividades_numero_seq', coalesce((SELECT max(numero) FROM atividades), 1));

ALTER TABLE atividades
  ALTER COLUMN numero SET DEFAULT nextval('atividades_numero_seq');

ALTER TABLE atividades
  ALTER COLUMN numero SET NOT NULL;

-- A sequence passa a pertencer à coluna: se um dia a coluna for embora, a
-- sequence vai junto em vez de ficar órfã.
ALTER SEQUENCE atividades_numero_seq OWNED BY atividades.numero;

-- Busca pelo número é justamente o caso de uso pedido.
CREATE UNIQUE INDEX IF NOT EXISTS idx_atividades_numero ON atividades (numero);

COMMENT ON COLUMN atividades.numero IS
  'Número sequencial visível, para o operador e o revisor citarem o mesmo apontamento. Gerado no banco: só existe depois de sincronizar.';
