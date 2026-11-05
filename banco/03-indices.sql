-- Extensao para busca textual por trigramas (ILIKE '%termo%')
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- 1. Busca de clientes por e-mail case-insensitive (GET /clientes?email=)
CREATE INDEX idx_clientes_email_lower ON clientes (lower(email), id);

-- 2. Pedidos de um cliente ordenados do mais recente para o mais antigo (GET /clientes/:id/pedidos)
CREATE INDEX idx_pedidos_cliente_criado ON pedidos (cliente_id, criado_em DESC, id DESC) INCLUDE (status);

-- 3. Paginacao e contagem de pedidos por status (GET /pedidos?status=&pagina=)
CREATE INDEX idx_pedidos_status_criado ON pedidos (status, criado_em DESC, id DESC) INCLUDE (cliente_id);

-- 4. Filtro de pedidos nao cancelados por data para relatorios (GET /relatorios/vendas-por-dia e top-produtos)
CREATE INDEX idx_pedidos_ativos_data ON pedidos ((criado_em::date), id) WHERE status <> 'cancelado';

-- 5. Itens de um pedido (GET /clientes/:id/pedidos e JOINs de relatorios)
CREATE INDEX idx_itens_pedido_pedido_id ON itens_pedido (pedido_id, id) INCLUDE (produto_id, quantidade, preco_unitario_centavos);

-- 6. Busca textual de produtos por substring (GET /produtos/busca?q=)
CREATE INDEX idx_produtos_nome_trgm ON produtos USING gin (nome gin_trgm_ops);

ANALYZE;
