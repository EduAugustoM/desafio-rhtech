# 🧠 Brainstorm Estratégico e Diagnóstico Preliminar — Desafio Tech for Humans (2026)

> **Documento de Processo e Arquitetura de Decisões**
> **Objetivo:** Deixar a aplicação de e-commerce fictícia (Node.js 20 + PostgreSQL 16) mais rápida e mais barata de rodar, mantendo 100% do contrato das 7 rotas de leitura e provando cientificamente cada melhoria.

---

## 1. Visão Geral do Desafio e Critérios de Avaliação

O processo seletivo de **Estágio em Pesquisa e Inovação (Tech for Humans — 2026)** avalia a capacidade de investigar gargalos de desempenho, fundamentar decisões na literatura científica/técnica e executar experimentos controlados.

### Pesos da Avaliação Oficial
| Critério | Peso | O que a banca avalia |
| :--- | :---: | :--- |
| **Pesquisa e Fontes** | **30%** | Fontes confiáveis e variadas (mínimo 6, sendo pelo menos 2 acadêmicas ou técnicas primárias), separando fato de opinião. |
| **Raciocínio** | **30%** | Alternativas comparadas, descarte justificado, experimento coerente com a hipótese, testes futuros bem descritos e o que refutaria a conclusão. |
| **Solução e Aplicabilidade** | **20%** | Faz sentido para uma empresa como a T4H, com limites honestos e atenção ao custo computacional. |
| **Comunicação** | **20%** | Artigo claro em `artigo/artigo.md` (800 a 1.500 palavras), seguindo o template obrigatório e explicando os *porquês*. |

### Restrições de Recursos Originais ("O Custo de Hoje")
- **API (`api` - Node.js 20 / Express):** `0.5 CPU` e `256 MB` de memória RAM.
- **Banco (`banco` - PostgreSQL 16.4):** `1.0 CPU` e `512 MB` de memória RAM (`shm_size: 256mb`).
- **Volume de Dados Sintéticos:** `100.000` clientes, `20.000` produtos, `500.000` pedidos e `~1.500.000` itens de pedido.

---

## 2. Mapeamento de Skills e Agentes do Repositório (`.agents`)

Para conduzir o desafio com rigor técnico, selecionamos as seguintes skills e especialistas:

| Agente / Skill | Aplicação Direta no Desafio |
| :--- | :--- |
| **`@[project-planner]`** + **`@[brainstorming]`** | Planejamento das etapas, árvore de decisões, avaliação de trade-offs (Custo × Desempenho × Risco × Esforço) e controle do fluxo de trabalho. |
| **`@[backend-specialist]`** + **`@[nodejs-best-practices]`** | Otimização do runtime Node.js 20 com restrição severa de CPU (`0.5 core`): gerenciamento de pool de conexões (`pg.Pool`), eliminação de I/O bloqueante (serialização + `console.log` síncrono por request) e uso eficiente de memória. |
| **`@[database-design]`** (`indexing.md`, `optimization.md`) | Análise de planos de execução com `EXPLAIN (ANALYZE, BUFFERS)`, desenho de índices B-Tree funcionais, compostos e *covering indexes* (`INCLUDE`), índices GIN com trigramas (`pg_trgm`) e reescrita de queries SQL. |
| **`@[systematic-debugging]`** | Aplicação do método científico em 4 fases: *Reproduzir (Linha de Base) → Isolar (Evidência em `diagnostico/`) → Entender (Hipótese de Causa) → Corrigir e Verificar (Contrato + 3 medições no k6)*. |
| **`@[performance-profiling]`** + **`@[verify-changes]`** | Garantia de que nenhuma alteração seja validada no "achismo": comparação estrita pela **mediana de 3 execuções** do `scripts/medir.sh` e validação de 42 casos de teste via `scripts/verificar-contrato.sh`. |
| **`@[documentation-templates]`** | Estruturação do artigo científico/técnico em `artigo/artigo.md`, matriz de experimentos em `experimentos.md` e fichas técnicas em `proximos-testes.md`. |

---

## 3. Auditoria Estática do Código Original (Gargalos Reais Identificados)

Após inspecionar o código-fonte original da aplicação (`api/src/` e `banco/`), identificamos **8 gargalos estruturais críticos** que explicam a lentidão sob carga de 20 usuários virtuais (k6):

### Gargalo 1: Ausência de Connection Pooling (`api/src/db.js`)
- **O que o código faz:** A função `consultar()` instancia um `new Client(config)`, executa `await cliente.connect()`, roda a query e chama `await cliente.end()` **a cada consulta SQL**.
- **Consequência:** Cada query sofre o *overhead* de handshake TCP + autenticação PostgreSQL + criação de um processo backend (`fork()`) no container do Postgres (limitado a 1 CPU).
- **Solução:** Substituir `Client` por `Pool` (`new Pool(config)`), mantendo conexões persistentes e reutilizáveis.

### Gargalo 2: Logging Síncrono do Corpo Inteiro da Resposta (`api/src/server.js`)
- **O que o código faz:** Um middleware intercepta `res.json` e executa `console.log(JSON.stringify({ ..., resposta: corpo }))` em **100% das requisições**.
- **Consequência:** Em Node.js, `JSON.stringify` duplica o trabalho de serialização (já que `res.json` também serializa) e `console.log` para `stdout` em container Docker gera contenção de I/O e CPU em um container limitado a apenas `0.5 CPU`.
- **Observação de Regra:** O `verificar-contrato.sh` valida apenas o status HTTP e o JSON retornado ao cliente HTTP, não o `stdout` do container. Remover ou enxugar o log da resposta inteira em produção economiza CPU preciosa da API.

### Gargalo 3: Ausência Total de Índices Secundários e em Chaves Estrangeiras (`banco/01-estrutura.sql`)
- **O que o código faz:** As tabelas possuem apenas `PRIMARY KEY (id)`. O PostgreSQL cria índices B-Tree automaticamente para chaves primárias, mas **não cria índices automaticamente para colunas com `REFERENCES` (Foreign Keys)** nem para colunas de filtro (`email`, `status`, `criado_em`, `nome`).
- **Consequência:** Qualquer busca fora do `id` primário força *Sequential Scans* em tabelas de 100k a 1,5M de linhas.

### Gargalo 4: Problema Clássico de Queries `N+1` Aninhadas (`GET /clientes/:id/pedidos` — 20% da carga)
- **O que o código faz (`api/src/rotas.js`, linhas 66–98):**
  1. Faz 1 query para verificar se o cliente existe (`SELECT * FROM clientes WHERE id = $1`).
  2. Faz 1 query para buscar os pedidos do cliente (`SELECT * FROM pedidos WHERE cliente_id = $1`, sem índice em `cliente_id` → *Seq Scan* em 500k linhas!).
  3. Para **cada pedido** (`for (const pedido of pedidos)`), faz 1 query em `itens_pedido` (`WHERE pedido_id = $1`, sem índice em `pedido_id` → *Seq Scan* em 1,5M de linhas!).
  4. Para **cada item** (`for (const item of itens)`), faz 1 query em `produtos` (`WHERE id = $1`).
- **Consequência:** Um único cliente com 5 pedidos e 15 itens dispara **22 conexões e 22 queries sequenciais** ao banco, incluindo múltiplos *Sequential Scans* em 1,5 milhão de linhas!
- **Solução:** Índices em `pedidos(cliente_id, criado_em DESC, id DESC)` e `itens_pedido(pedido_id)` + substituir o loop N+1 por `JOIN` entre `pedidos`, `itens_pedido` e `produtos` em uma única consulta (ou duas consultas enxutas).

### Gargalo 5: Busca Case-Insensitive sem Índice Funcional (`GET /clientes?email=` — 15% da carga)
- **O que o código faz (`api/src/rotas.js`, linha 47):** `SELECT * FROM clientes WHERE lower(email) = lower($1) ORDER BY id`.
- **Consequência:** Sem índice funcional em `lower(email)`, o PostgreSQL aplica a função `lower()` nas 100.000 linhas da tabela `clientes` em toda requisição (*Seq Scan*).
- **Solução:** Criar índice funcional `CREATE INDEX idx_clientes_email_lower ON clientes (lower(email), id);`.

### Gargalo 6: Paginação com `COUNT(*)` e `OFFSET` sem Índice Composto (`GET /pedidos?status=&pagina=` — 15% da carga)
- **O que o código faz (`api/src/rotas.js`, linhas 112–116):**
  1. `SELECT count(*) AS total FROM pedidos WHERE status = $1`
  2. `SELECT id, cliente_id, status, criado_em ... FROM pedidos WHERE status = $1 ORDER BY criado_em DESC, id DESC LIMIT 20 OFFSET $3` (atualmente faz `SELECT *`, trazendo a coluna pesada `observacoes` que é descartada no JavaScript!).
- **Consequência:** Dois *Sequential Scans* na tabela de 500.000 pedidos (que é larga por causa da coluna `observacoes` repetida até 7 vezes), além de *Sort* pesado em memória/disco.
- **Solução:**
  1. Projetar apenas `id, cliente_id, status, criado_em` (evitando ler `observacoes`).
  2. Criar índice composto `(status, criado_em DESC, id DESC) INCLUDE (cliente_id)` que permite **Index-Only Scan** tanto para a paginação quanto para o `COUNT(*)`.

### Gargalo 7: Busca Textual com Coringa Inicial `ILIKE '%termo%'` (`GET /produtos/busca?q=` — 15% da carga)
- **O que o código faz (`api/src/rotas.js`, linha 136):** `SELECT * FROM produtos WHERE nome ILIKE '%' || $1 || '%' ORDER BY nome, id LIMIT 20`.
- **Consequência:** Índices B-Tree tradicionais não suportam prefixo coringa (`%termo%`). O Postgres varre os 20.000 produtos e ordena a cada chamada.
- **Solução:** Habilitar a extensão `pg_trgm` (`CREATE EXTENSION IF NOT EXISTS pg_trgm;`) e criar índice GIN (`CREATE INDEX idx_produtos_nome_trgm ON produtos USING gin (nome gin_trgm_ops);`). Como a rota exige pelo menos 3 caracteres (`termo.length < 3`), o uso de trigramas (3 caracteres) casa com 100% dos casos válidos!

### Gargalo 8: Relatórios Analíticos Fazendo Agregação em Aplicação e Varredura Completa (10% da carga, mas altíssimo peso de CPU/RAM)
- **`GET /relatorios/vendas-por-dia` (8% da carga):**
  - **Problema 1 (Sargability):** Usa `WHERE p.criado_em::date BETWEEN $1 AND $2`. O cast `p.criado_em::date` impede o uso direto de índice simples em `criado_em` se não for reescrito como intervalo de timestamp (`p.criado_em >= $1::timestamp AND p.criado_em < ($2::date + interval '1 day')`) ou índice funcional.
  - **Problema 2 (Transferência Massiva de Dados):** A query faz `SELECT p.id, p.criado_em, p.observacoes, i.quantidade, i.preco_unitario_centavos` sem `GROUP BY` no SQL! Ela transfere dezenas de milhares de linhas cruas (incluindo o texto longo `p.observacoes` que nem é usado!) do Postgres para o Node.js agrupar num `Map` e `Set` em JavaScript, estourando CPU e Garbage Collector dos dois containers!
  - **Solução:** Fazer a agregação (`COUNT(DISTINCT p.id)`, `SUM(i.quantidade)`, `SUM(i.quantidade * i.preco_unitario_centavos)`) diretamente no SQL (ou via tabela/visão materializada pré-agregada por dia, já que os dados são estáticos/históricos).
- **`GET /relatorios/top-produtos` (2% da carga):**
  - **Problema:** Varre todos os 1,5 milhão de `itens_pedido` unidos a 500 mil `pedidos` (`WHERE p.status <> 'cancelado'`) e 20 mil `produtos`, agrupando tudo do zero a cada requisição.
  - **Solução:** Índice/Covering Index ou **Materialized View** criada no script `.sql` de inicialização do banco (ou cache em memória), reduzindo uma query de segundos para `< 1 ms`.

---

## 4. Opções Estratégicas para Enquadrar o Desafio

### Opção A: Otimização Pura In-Place (Banco + Queries + Node.js, Custo Zero)
Resolver todos os gargalos mantendo exatamente os limites originais (`0.5 CPU / 256 MB` na API e `1.0 CPU / 512 MB` no Postgres) e sem adicionar novos containers:
- Connection Pool (`pg.Pool`) + remoção do `console.log(JSON.stringify)` na API.
- Reescrita das queries SQL (eliminar N+1 em pedidos do cliente, eliminar `SELECT *` desnecessário, mover agregação de `vendas-por-dia` do JS para o SQL, tornar filtro de data *sargable*).
- Criação de índices B-Tree compostos/covering e GIN (`pg_trgm`) em `banco/03-indices.sql`.
- Tuning de parâmetros do PostgreSQL 16 para 512MB de RAM (`shared_buffers=128MB`, `effective_cache_size=384MB`, `work_mem=8MB`, `random_page_cost=1.1`) via `docker-compose.yml`.

### Opção B: Otimização In-Place + Pré-computação / Materialized Views / Cache In-Memory (Recomendada)
Tudo da **Opção A**, somado a pré-computação para os relatórios analíticos (`top-produtos` e `vendas-por-dia`) via **Materialized Views** no próprio PostgreSQL (criadas em `banco/04-...sql`) e/ou **Cache em memória (LRU)** na API Node.js:
- **Por que brilha:** Mantém o custo de infraestrutura idêntico (zero containers extras, mesmos limites de CPU e RAM), mas transforma relatórios que varrem 1,5 milhão de linhas em leituras instantâneas, derrubando o consumo de CPU do banco drasticamente.
- **Riqueza para o Artigo:** Permite discutir no artigo o trade-off entre dados em tempo real vs. *eventual consistency* / atualização de Materialized Views (`REFRESH MATERIALIZED VIEW CONCURRENTLY`) quando houver carga de escrita.

### Opção C: Adição de Novos Serviços (Container Redis / PgBouncer) ou Escala Vertical
Adicionar um container Redis no `docker-compose.yml` ou dobrar a CPU/RAM dos containers.
- **Por que descartar como solução principal (e usar na Tabela de Alternativas Consideradas):** O edital alerta que *recurso a mais custa mais*. Adicionar um container Redis consome memória e CPU adicionais que entram na conta do `medir.sh`, sendo desnecessário quando o banco bem indexado e com Materialized Views atende com folga dentro dos 512 MB originais.

---

## 5. Estratégia para Nota Máxima (Os Diferenciais Competitivos)

1. **Incluir 1 Experimento "Aplicada, sem ganho" (ou ganho marginal) documentado:**
   - O edital destaca na página 8 que uma mudança aplicada e medida que não melhorou conta tanto quanto uma que funcionou, desde que você explique o porquê.
   - *Ideia de Experimento Científico:* Testar primeiro um ajuste isolado (ou um índice B-Tree simples para busca textual / ou tuning de Postgres antes dos índices) para demonstrar com dados reais que sem corrigir a complexidade algorítmica ($O(N)$ vs $O(\log N)$), ajustes periféricos não resolvem o gargalo principal.
2. **Rigor Absoluto no Ciclo de Medição (Seção 06 do Edital):**
   - Cada mudança = 1 commit de código (`arquivos alterados sem commit: 0` no `contexto.txt`) → `verificar-contrato.sh comparar` → 3 execuções do `medir.sh` → 1 commit separado das pastas em `resultados/` + registro na tabela do `experimentos.md`.
3. **Evidências de Diagnóstico Salvas em `diagnostico/`:**
   - Antes de aplicar as correções, salvar a saída real de `EXPLAIN (ANALYZE, BUFFERS)` de todas as 7 rotas, estatísticas de `pg_stat_user_tables` (`seq_scan` vs `idx_scan`) e métricas da linha de base em arquivos dentro de `diagnostico/` para referenciar com links relativos no `artigo/artigo.md`.
4. **Literatura Acadêmica e Técnica Primária (Seção 3 do Artigo):**
   - Documentação Oficial do PostgreSQL 16 ( capítulos de *Index Types*, *GIN / pg_trgm*, *Index-Only Scans* e *Resource Consumption*).
   - Documentação Oficial do Node.js (*Don't Block the Event Loop* e *node-postgres Pooling*).
   - Artigos clássicos: Graefe, G. (*Modern B-Tree Techniques*, ACM Computing Surveys) e Selinger et al. (*Access Path Selection in a Relational Database Management System*, ACM SIGMOD).
   - Winand, M. (*SQL Performance Explained / Use The Index, Luke*).
