# De 14,7 s para 61,4 ms no p95 (e de 4,34 para 1.513,43 req/s): otimização de API Node.js e PostgreSQL 16 sem aumento de infraestrutura

## 1. Resumo
A API da loja fictícia apresentava severa degradação sob carga de 20 usuários virtuais (`4,34 req/s` e `p95` geral de `14.721,2 ms`), saturando a CPU do PostgreSQL em `98,0%`. Diagnosticamos ausência de *connection pooling*, log síncrono bloqueante na API, consultas `N+1` e ausência de índices secundários para 500 mil pedidos e 1,5 milhão de itens. Aplicamos *pooling* de conexões, índices B-Tree compostos (*Index-Only Scan*), índice GIN (`pg_trgm`), reescrita SQL e *Materialized Views*, reduzindo o `p95` geral para **`61,4 ms` (-99,58%)**, elevando a vazão para **`1.513,43 req/s` (348,7x)** e reduzindo CPU (`70,1%`) e memória (`205,2 MiB`) do banco sem custo adicional de infraestrutura.

## 2. Contexto e diagnóstico
A aplicação compõe-se de uma API Node.js 20 (`Express` e `pg`), limitada a `0,5 CPU` e `256 MB` de RAM, e um banco PostgreSQL 16.4 limitado a `1,0 CPU` e `512 MB` de RAM, com `100.000` clientes, `20.000` produtos, `500.000` pedidos e `1.500.000` itens de pedido. Na linha de base ([resumo 1](../resultados/20261105-171535-00-linha-de-base/resumo.txt), [resumo 2](../resultados/20261105-171710-00-linha-de-base/resumo.txt), [resumo 3](../resultados/20261105-171841-00-linha-de-base/resumo.txt)), a mediana registrou `4,34 req/s`, mediana de `900,6 ms` e `p95` de `14.721,2 ms`, com o banco em `98,0%` de CPU média e `450,3 MiB` de memória máxima ([recursos.txt](../resultados/20261105-171841-00-linha-de-base/recursos.txt)).

Coletamos estatísticas de `pg_stat_user_tables` ([01-estatisticas-banco-baseline.txt](../diagnostico/01-estatisticas-banco-baseline.txt)), planos de execução com `EXPLAIN (ANALYZE, BUFFERS)` ([02-explain-analyze-baseline.txt](../diagnostico/02-explain-analyze-baseline.txt)) e auditamos `api/src/`. A tabela `itens_pedido` sofreu `5.415` varreduras sequenciais (*Sequential Scans*), lendo `3.922.500.000` de tuplas com `0` leituras por índice (`idx_scan = 0`), pois `banco/01-estrutura.sql` declarava apenas chaves primárias.

Hipótese de causa:
- **Conexão por consulta e log bloqueante:** `api/src/db.js` abre e fecha `new Client()` a cada query, e `api/src/server.js` executa `console.log(JSON.stringify)` síncrono do corpo inteiro da resposta em toda requisição.
- **Varreduras sequenciais ($O(N)$) por falta de índices:** filtros por `lower(email)`, `cliente_id`, `status`, `pedido_id` e `ILIKE '%termo%'` forçam *Parallel Seq Scans*.
- **Consultas `N+1` e transferência excessiva (`SELECT *`):** `/clientes/:id/pedidos` executa queries em laço por pedido e item; `/pedidos` e `/relatorios/vendas-por-dia` trafegam a coluna longa `observacoes` e agregam dados em JavaScript.
- **Recomputação analítica sob demanda:** os relatórios varrem e agregam 1,5 milhão de itens repetidamente sobre dados estáticos.

## 3. Estado da arte

### Indexação B-Tree, Covering Indexes e Índices Invertidos (GIN / Trigramas)
Selinger et al. [1] demonstraram no otimizador do System R que a seleção do caminho de acesso entre varreduras sequenciais e índices B-Tree define ordens de grandeza no custo de CPU e I/O. Graefe [2] e Winand [3] mostram que índices B-Tree compostos reduzem buscas e ordenações de $O(N \log N)$ para $O(\log N)$, evitando *Sort* quando o índice segue a cláusula `ORDER BY`. Segundo a documentação do PostgreSQL 16 sobre *Index-Only Scans* [4], a cláusula `INCLUDE` adiciona colunas às folhas do índice, respondendo consultas sem ler a tabela (*heap fetches = 0*) quando `SELECT *` é evitado. Para buscas com coringa inicial (`ILIKE '%termo%'`), onde B-Trees falham por dependerem de prefixo [3], a documentação do módulo `pg_trgm` [5] recomenda índices invertidos (GIN) com `gin_trgm_ops`, dividindo strings em trigramas de 3 caracteres.

### Gerenciamento de Conexões e Event Loop em Node.js
A documentação do PostgreSQL 16 [6] detalha sua arquitetura *process-per-connection*, na qual cada conexão cria um processo backend no sistema operacional. Por isso, a documentação do `node-postgres` [7] alerta que instanciar `pg.Client` por consulta degrada a vazão sob concorrência, recomendando `pg.Pool`. Já o guia oficial do Node.js sobre o *Event Loop* [8] explica que serializações `JSON.stringify` de grandes payloads aliadas a `console.log` síncrono bloqueiam a *thread* única de eventos, efeito agravado sob limite de `0,5 CPU`.

### Eliminação de `N+1` e Pré-computação com Materialized Views
O antipadrão `N+1` multiplica latência de rede e planejamento; substituí-lo por `JOIN` reduz a comunicação a uma única viagem ao banco [3]. Já para consultas analíticas (*OLAP*) concorrendo com tráfego transacional (*OLTP*), Kleppmann [9] e a documentação do PostgreSQL 16 [10] fundamentam o uso de *Materialized Views* indexadas para pré-computar agregações estáticas ou periódicas, trocando varreduras de milhões de linhas por leituras de poucos kilobytes.

## 4. Alternativas consideradas
| Alternativa | Custo | Desempenho | Risco | Esforço |
|---|---|---|---|---|
| **[A] Otimização In-Place: Pool + Índices B-Tree/GIN + Reescrita SQL + Materialized Views** | **Zero** (mantém `0,5 CPU / 256 MB` na API e `1 CPU / 512 MB` no banco) | **Muito Alto** (`1.513,43 req/s` e `p95` de `61,4 ms`) | **Baixo** (exige `REFRESH` se houver escrita futura) | **Médio** (2 scripts `.sql` e ajustes na API) |
| **[B] Cache Distribuído Externo (`Redis` em padrão *Cache-Aside*)** | **Médio/Alto** (novo container consumindo RAM e CPU adicionais) | **Alto em *cache hits***, mas não resolve *cache misses* em 100k clientes | **Médio** (invalidação de cache e dados obsoletos) | **Médio/Alto** (novo serviço e cliente Redis) |
| **[C] Escalonamento Vertical + Tuning Isolado de Memória do SGBD** | **Alto** (mais CPU/RAM contratadas) | **Baixo** (sem índices, `p95` segue `> 14 s` por *Seq Scans*) | **Baixo** (apenas configuração) | **Baixo** (ajuste no `docker-compose.yml`) |

## 5. Solução escolhida e por quê
Escolhemos a **Alternativa [A]** porque corrige a complexidade algorítmica dos gargalos na origem sem aumentar o custo de infraestrutura. Enquanto a aplicação original consumia `98,0%` da CPU do banco varrendo `3,92 bilhões` de tuplas e abrindo conexões TCP por consulta, a combinação de `pg.Pool`, índices compostos/GIN, reescrita SQL e *Materialized Views* converte operações lineares $O(N)$ em buscas indexadas $O(\log N)$ dentro dos mesmos `512 MB` do banco e `256 MB` da API.

Descartamos a **Alternativa [C]** isolada porque nosso Experimento 01 provou que ajustar memória no PostgreSQL sem índices reduz o `p95` em apenas `3,8%`. Descartamos a **Alternativa [B] (Redis)** porque há apenas uma instância da API e o sorteio uniforme entre `100.000` clientes geraria alto índice de *cache miss*; adicionar um container extra aumentaria o consumo de recursos medido pelo `medir.sh` sem resolver a lentidão estrutural do banco.

## 6. Experimento e resultado
Todas as medições usaram `VUS=20`, `DURACAO=60s`, `AQUECIMENTO=15s` e `SEMENTE=42`, comparando a **mediana de 3 execuções** contra a linha de base (`00-linha-de-base`: `p95` `14.721,2 ms`, `4,34 req/s`, CPU média `98,0%` banco / `7,7%` API, RAM máx `450,3 MiB` banco / `43,0 MiB` API) e contra a mudança anterior (ver [experimentos.md](../experimentos.md)).

| Mudança | Hipótese | p95 antes → depois | req/s antes → depois | CPU/memória | Pastas de resultados | Conclusão |
|---|---|---|---|---|---|---|
| `01-tuning-postgres-sem-indices` | Ajustar `shared_buffers`, `work_mem`, `effective_cache_size` e `random_page_cost` reduz o `p95` se a causa for paginação de disco. | `14721.2 ms` → `14165.3 ms` | `4.34` → `4.77` | Banco: `98.0%`/`450.3 MiB` → `98.5%`/`345.6 MiB`<br>API: `7.7%`/`43.0 MiB` → `7.8%`/`42.0 MiB` | [b1](../resultados/20261105-171535-00-linha-de-base/resumo.txt), [b2](../resultados/20261105-171710-00-linha-de-base/resumo.txt), [b3](../resultados/20261105-171841-00-linha-de-base/resumo.txt) → [01a](../resultados/20261105-172708-01-tuning-postgres-sem-indices/resumo.txt), [01b](../resultados/20261105-172840-01-tuning-postgres-sem-indices/resumo.txt), [01c](../resultados/20261105-173011-01-tuning-postgres-sem-indices/resumo.txt) | **Sem ganho:** variação menor que o ruído de 30%; *Seq Scans* seguem saturando a CPU. |
| `02-pool-conexoes-e-log` | Usar `pg.Pool` em `db.js` e remover o log síncrono em `server.js` elimina o custo de conexão por query. | `14165.3 ms` → `10349.0 ms` | `4.77` → `5.54` | Banco: `98.5%`/`345.6 MiB` → `98.2%`/`475.1 MiB`<br>API: `7.8%`/`42.0 MiB` → `6.5%`/`51.8 MiB` | [02a](../resultados/20261105-173432-02-pool-conexoes-e-log/resumo.txt), [02b](../resultados/20261105-173603-02-pool-conexoes-e-log/resumo.txt), [02c](../resultados/20261105-173733-02-pool-conexoes-e-log/resumo.txt) | **Com ganho:** mediana de `/clientes/:id` caiu **98,5%** (`201,4 ms` → `3,0 ms`) e `p95` geral caiu **29,7%** vs base. |
| `03-indices-banco` | Criar índices B-Tree compostos/funcionais e GIN (`pg_trgm`) em `banco/03-indices.sql` elimina *Seq Scans* nas buscas. | `10349.0 ms` → `4451.7 ms` | `5.54` → `26.66` | Banco: `98.2%`/`475.1 MiB` → `95.4%`/`474.2 MiB`<br>API: `6.5%`/`51.8 MiB` → `25.0%`/`83.5 MiB` | [03a](../resultados/20261105-180320-03-indices-banco/resumo.txt), [03b](../resultados/20261105-180445-03-indices-banco/resumo.txt), [03c](../resultados/20261105-180612-03-indices-banco/resumo.txt) | **Com ganho:** vazão subiu **6,1x** vs base; `p95` de `pedidos-do-cliente` caiu para `860,6 ms`. |
| `04-reescrita-queries-n1-e-sql` | Eliminar `N+1` com `LEFT JOIN`, remover `SELECT *` e agregar `vendas-por-dia` no SQL reduz CPU/RAM da API e latência OLTP. | `4451.7 ms` → `4617.4 ms`<br>*(`pedidos-por-status`: `8199.4` → `557.4 ms`)* | `26.66` → `30.70` | Banco: `95.4%`/`474.2 MiB` → `98.0%`/`474.5 MiB`<br>API: **`25.0%`/`83.5 MiB` → `3.7%`/`30.0 MiB`** | [04a](../resultados/20261105-180839-04-reescrita-queries-n1-e-sql/resumo.txt), [04b](../resultados/20261105-181005-04-reescrita-queries-n1-e-sql/resumo.txt), [04c](../resultados/20261105-181130-04-reescrita-queries-n1-e-sql/resumo.txt) | **Com ganho:** CPU da API caiu **85,2%**, RAM caiu **64,1%** e `p95` de `pedidos-do-cliente` caiu para `197,6 ms`. |
| `05-materialized-views` | Criar *Materialized Views* indexadas (`banco/04-materialized-views.sql`) elimina a varredura de 1,5M de itens nos relatórios. | `4617.4 ms` → **`61.4 ms`** | `30.70` → **`1513.43`** | Banco: **`98.0%`/`474.5 MiB` → `70.1%`/`205.2 MiB`**<br>API: `3.7%`/`30.0 MiB` → `48.9%`/`31.8 MiB` | [05a](../resultados/20261105-182258-05-materialized-views/resumo.txt), [05b](../resultados/20261105-182419-05-materialized-views/resumo.txt), [05c](../resultados/20261105-182539-05-materialized-views/resumo.txt) | **Com ganho:** vazão **348,7x** maior que a base e `p95` geral **99,58%** menor ([EXPLAIN](../diagnostico/03-explain-analyze-otimizado.txt)). |

## 7. Limites e testes futuros
A principal limitação está nas *Materialized Views* (`mv_vendas_por_dia`, `mv_top_produtos` e `mv_contagem_pedidos_status`) e nos índices adicionais (`~130 MB` em disco). Como o teste realiza apenas leituras em dados estáticos, não há defasagem. Porém, sob escrita contínua (`INSERT`/`UPDATE`), a necessidade de consistência imediata (*read-your-writes*) refutaria o uso de visões estáticas, pois `REFRESH MATERIALIZED VIEW CONCURRENTLY` exige CPU e I/O periódicos. Também não testamos milhões de linhas por status, onde `OFFSET` alto voltaria a degradar.

Em [proximos-testes.md](../proximos-testes.md), registramos três evoluções:
1. **Cache Redis (*Cache-Aside*):** para múltiplas réplicas da API.
2. **Paginação por cursor (*Keyset*):** trocando `OFFSET` por `WHERE (criado_em, id) < ...` se o contrato mudar.
3. **Pooler externo (*PgBouncer*):** para dezenas de instâncias da API.

## 8. Referências
1. SELINGER, P. G. et al. Access Path Selection in a Relational Database Management System. *Proceedings of the 1979 ACM SIGMOD International Conference on Management of Data*, p. 23–34, 1979. Link: https://doi.org/10.1145/582095.582099. Data de acesso: 05 nov. 2026.
2. GRAEFE, G. Modern B-Tree Techniques. *Foundations and Trends in Databases*, v. 3, n. 4, p. 203–402, 2011. Link: https://doi.org/10.1561/1900000028. Data de acesso: 05 nov. 2026.
3. WINAND, M. *Use The Index, Luke! A Guide to Database Performance for Developers*. Link: https://use-the-index-luke.com/. Data de acesso: 05 nov. 2026.
4. POSTGRESQL GLOBAL DEVELOPMENT GROUP. *PostgreSQL 16 Documentation — Chapter 11.9: Index-Only Scans and Covering Indexes*. Link: https://www.postgresql.org/docs/16/indexes-index-only-scans.html. Data de acesso: 05 nov. 2026.
5. POSTGRESQL GLOBAL DEVELOPMENT GROUP. *PostgreSQL 16 Documentation — Appendix F.35: pg_trgm — Support for similarity of text using trigram matching*. Link: https://www.postgresql.org/docs/16/pgtrgm.html. Data de acesso: 05 nov. 2026.
6. POSTGRESQL GLOBAL DEVELOPMENT GROUP. *PostgreSQL 16 Documentation — Chapter 20.4: Resource Consumption*. Link: https://www.postgresql.org/docs/16/runtime-config-resource.html. Data de acesso: 05 nov. 2026.
7. CARLSON, B. *node-postgres Documentation — Pooling*. Link: https://node-postgres.com/features/pooling. Data de acesso: 05 nov. 2026.
8. OPENJS FOUNDATION. *Node.js Documentation — Don't Block the Event Loop (or the Worker Pool)*. Link: https://nodejs.org/en/learn/asynchronous-work/dont-block-the-event-loop. Data de acesso: 05 nov. 2026.
9. KLEPPMANN, M. *Designing Data-Intensive Applications: The Big Ideas Behind Reliable, Scalable, and Maintainable Systems*. Sebastopol: O'Reilly Media, 2017. Link: https://dataintensive.net/. Data de acesso: 05 nov. 2026.
10. POSTGRESQL GLOBAL DEVELOPMENT GROUP. *PostgreSQL 16 Documentation — Chapter 41.3: Materialized Views*. Link: https://www.postgresql.org/docs/16/rules-materializedviews.html. Data de acesso: 05 nov. 2026.

## 9. Uso de IA
Utilizamos agente de IA (Google Antigravity) em *pair programming* para estruturar o brainstorm, automatizar a coleta de planos `EXPLAIN ANALYZE` e revisar a formatação do texto. Todas as hipóteses, consultas SQL, fontes bibliográficas verificadas, validações de contrato (`42/42` casos) e todos os números reportados foram extraídos sem edição manual dos arquivos gerados por `scripts/medir.sh` em `resultados/`.
