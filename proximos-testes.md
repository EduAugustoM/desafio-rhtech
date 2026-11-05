# Próximos Testes (Ideias Pesquisadas para Teste Futuro)

Este documento reúne as hipóteses e abordagens levantadas durante a etapa de pesquisa (literatura e mercado) que **não foram aplicadas** no escopo atual — seja por relação custo-benefício desfavorável frente aos limites originais dos containers (`0,5 CPU / 256 MB` na API e `1 CPU / 512 MB` no banco), seja por exigirem mudanças de arquitetura para cenários de escrita intensa.

---

## Ficha 01 — Cache Distribuído com Redis (`Cache-Aside`)

- **Status:** Pesquisada, teste futuro
- **Fonte:**
  - [AWS Architecture — Database Caching Strategies Using Redis](https://docs.aws.amazon.com/whitepapers/latest/database-caching-strategies-using-redis/caching-patterns.html)
  - [Redis Official Documentation — Client-side caching & LRU eviction](https://redis.io/docs/latest/develop/reference/eviction/)
- **O que acreditamos que ganharia:**
  - Redução da latência (p95 e p99) das rotas de leitura frequente (`GET /clientes/:id`, `GET /produtos/busca` e relatórios) para menos de `1 ms` em caso de *cache hit*, além de aliviar o consumo de CPU do PostgreSQL em cenários de escalonamento horizontal com múltiplas instâncias da API Node.js.
- **Como testaríamos:**
  1. Adicionar um serviço `redis:7-alpine` no `docker-compose.yml` com limite de `128 MB` de memória e política `allkeys-lru`.
  2. Implementar o padrão *Cache-Aside* na API com TTL de 60 segundos nas rotas de leitura e relatórios.
  3. Validar o contrato com `scripts/verificar-contrato.sh comparar` e rodar 3 baterias do `scripts/medir.sh` comparando o ganho de RPS/p95 contra o aumento de consumo total de RAM e CPU dos 3 containers registrados em `recursos.txt`.
- **O que precisaria para testar / Por que ficou para depois:**
  - Como temos apenas **1 instância da API** e o banco otimizado com índices adequados já responde em poucos milissegundos dentro dos limites originais de `512 MB`, adicionar um container Redis aumentaria o custo de infraestrutura (memória e CPU extras medidas pelo `medir.sh`) e introduziria risco de dados defasados (*cache staleness*) caso a aplicação passe a receber rotas de escrita (`POST`/`PUT`).

---

## Ficha 02 — Paginação por Cursor (*Keyset Pagination*) em `GET /pedidos`

- **Status:** Pesquisada, teste futuro
- **Fonte:**
  - [Markus Winand — Use The Index, Luke: No OFFSET (Keyset Pagination)](https://use-the-index-luke.com/no-offset)
  - [PostgreSQL 16 Documentation — Queries: LIMIT and OFFSET](https://www.postgresql.org/docs/16/queries-limit.html)
- **O que acreditamos que ganharia:**
  - Tempo de resposta constante $O(\log N)$ independentemente da profundidade da página solicitada, eliminando a necessidade de o PostgreSQL varrer e descartar milhares de tuplas em páginas altas (como `pagina=15000`, que exige `OFFSET 299980`), além de eliminar o custo do `COUNT(*)` exato a cada requisição.
- **Como testaríamos:**
  1. Alterar o contrato do endpoint `GET /pedidos` para receber `?status=pago&apos_criado_em=...&apos_id=...` em vez de `pagina=`.
  2. Substituir a cláusula `OFFSET` por `WHERE status = $1 AND (criado_em, id) < ($2, $3) ORDER BY criado_em DESC, id DESC LIMIT 20`.
  3. Medir o p95 específico da rota `pedidos-por-status` sorteando páginas profundas no k6.
- **O que precisaria para testar / Por que ficou para depois:**
  - Exige alteração no contrato da API (parâmetros de entrada e formato de resposta sem o campo `total`), o que é **proibido pelas regras deste desafio** (`scripts/verificar-contrato.sh`). Em um produto real na Tech for Humans, seria negociado junto ao time de Frontend.

---

## Ficha 03 — Pooler Externo de Conexões (PgBouncer em *Transaction Pooling*)

- **Status:** Pesquisada, teste futuro
- **Fonte:**
  - [PgBouncer Official Documentation — Features & Transaction Pooling](https://www.pgbouncer.org/features.html)
  - [PostgreSQL 16 Documentation — Connections and Authentication](https://www.postgresql.org/docs/16/runtime-config-connection.html)
- **O que acreditamos que ganharia:**
  - Multiplexação de centenas ou milhares de conexões de múltiplos containers da API sobre um número reduzido de processos backend do PostgreSQL (ex.: 10 a 20 conexões reais), reduzindo o consumo de memória por conexão no banco e evitando contenção de troca de contexto em cargas acima de 100 VUs.
- **Como testaríamos:**
  1. Incluir a imagem `edoburu/pgbouncer` no `docker-compose.yml` entre o serviço `api` e o serviço `banco` em modo `pool_mode = transaction`.
  2. Executar `VUS=100 DURACAO=60s scripts/medir.sh` comparando o `pg.Pool` nativo do Node.js contra o `pg.Pool + PgBouncer`.
- **O que precisaria para testar / Por que ficou para depois:**
  - Para a topologia atual (1 container de API com `0,5 CPU` e carga padrão de `20 VUs`), o pool interno do `node-postgres` (`pg.Pool`) na própria API já mantém um número fixo e controlado de conexões abertas com custo zero de rede extra. O PgBouncer só se paga quando há dezenas de réplicas da API ou funções *serverless* conectando simultaneamente ao PostgreSQL.
