-- Pre-computacao com Materialized Views para relatorios analiticos e contagens por status

-- 1. Vendas agregadas por dia (exclui pedidos cancelados)
CREATE MATERIALIZED VIEW mv_vendas_por_dia AS
SELECT p.criado_em::date AS dia_data,
       p.criado_em::date::text AS dia,
       count(DISTINCT p.id)::int AS pedidos,
       sum(i.quantidade)::int AS itens,
       sum(i.quantidade * i.preco_unitario_centavos)::bigint AS receita_centavos
  FROM pedidos p
  JOIN itens_pedido i ON i.pedido_id = p.id
 WHERE p.status <> 'cancelado'
 GROUP BY p.criado_em::date
 ORDER BY p.criado_em::date;

CREATE UNIQUE INDEX idx_mv_vendas_por_dia_data ON mv_vendas_por_dia (dia_data);

-- 2. Receita e unidades agregadas por produto (exclui pedidos cancelados)
CREATE MATERIALIZED VIEW mv_top_produtos AS
SELECT pr.id AS produto_id,
       pr.nome,
       pr.categoria,
       sum(i.quantidade)::bigint AS unidades,
       sum(i.quantidade * i.preco_unitario_centavos)::bigint AS receita_centavos
  FROM itens_pedido i
  JOIN pedidos p ON p.id = i.pedido_id
  JOIN produtos pr ON pr.id = i.produto_id
 WHERE p.status <> 'cancelado'
 GROUP BY pr.id, pr.nome, pr.categoria
 ORDER BY receita_centavos DESC, pr.id;

CREATE INDEX idx_mv_top_produtos_ordem ON mv_top_produtos (receita_centavos DESC, produto_id ASC);

-- 3. Contagem total de pedidos por status para evitar varredura de 150k-300k linhas a cada pagina
CREATE MATERIALIZED VIEW mv_contagem_pedidos_status AS
SELECT status, count(*)::int AS total
  FROM pedidos
 GROUP BY status;

CREATE UNIQUE INDEX idx_mv_contagem_pedidos_status ON mv_contagem_pedidos_status (status);

ANALYZE;
