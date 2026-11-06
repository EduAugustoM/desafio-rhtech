# Relatório de Status e Auditoria Técnica — Tech for Humans

**Data:** 06 de novembro de 2026  
**Papel:** Senior Software Engineer & Tech Lead  
**Repositório:** `desafio-rhtech` (`origin/main`)  
**Commit Base Auditado:** `954c0a2` (*docs: preenche artigo tecnico, tabela de experimentos, README e diagnostico final*)

---

## 1. Status Geral do Projeto

| Indicador | Situação Atual | Meta / Requisito do Edital | Status |
| :--- | :--- | :--- | :---: |
| **Integridade da Régua de Testes** | Intacta (`carga/`, `scripts/`, `banco/01*`, `banco/02*` inalterados) | Nenhuma alteração permitida | ✅ Conforme |
| **Preservação de Contrato da API** | 42/42 casos idênticos em todas as 18 baterias de medição | "Contrato mantido" obrigatório | ✅ Conforme |
| **Metodologia de Medição** | 3 execuções por mudança, mesma semente (`42`), mediana reportada | Mínimo 3 medições, mediana | ✅ Conforme |
| **Limites de Hardware** | `0,5 CPU / 256 MB` (API) e `1,0 CPU / 512 MB` (PostgreSQL) mantidos | Custo zero de infraestrutura | ✅ Conforme |
| **Redução do Tempo de Resposta (p95)** | **`14.721,2 ms` → `61,4 ms` (-99,58%)** | Reduzir latência sob carga | ✅ Conforme |
| **Aumento de Throughput (Vazão)** | **`4,34 req/s` → `1.513,43 req/s` (348,7x)** | Tornar a aplicação mais rápida | ✅ Conforme |
| **Uso de Recursos no Banco** | CPU: `98,0%` → `70,1%` \| RAM: `450,3 MiB` → `205,2 MiB` | Mais barata / eficiente de rodar | ✅ Conforme |
| **Consistência do Git** | 100% linear, commits atômicos, medições sem sujeira (`uncommitted: 0`) | 1 commit por mudança + 1 commit de medição | ✅ Conforme |
| **Extensão do Artigo Técnico** | **1.421 palavras** no corpo (Seções 1 a 7) | Faixa obrigatória: 800 a 1.500 palavras | ✅ Conforme |
| **Apoio Visual (Opcional do Edital)** | Gráfico PNG técnico de p95 e vazão em `artigo/img/p95-por-mudanca.png` | `artigo/img/` referenciado no artigo | ✅ Conforme |

---

## 2. Percentual de Conclusão por Marco

```
[████████████████████] 98% Conclusão Geral do Desafio
```

| Marco / Entrega | Status | % Concluído | Evidência Principal |
| :--- | :---: | :---: | :--- |
| **1. Linha de Base e Contrato Gravado** | Concluído | 100% | `contrato/base.json` e 3 pastas `resultados/*-00-linha-de-base` |
| **2. Diagnóstico Técnico Documentado** | Concluído | 100% | `diagnostico/01-estatisticas-banco-baseline.txt` e `02-explain-analyze-baseline.txt` |
| **3. Ciclos de Otimização e Medição (01 a 05)** | Concluído | 100% | 15 pastas de medição em `resultados/` e `experimentos.md` |
| **4. Fichas de Testes Futuros** | Concluído | 100% | `proximos-testes.md` (3 fichas completas com fontes) |
| **5. Artigo Técnico no Template** | Concluído | 100% | `artigo/artigo.md` (todas as 9 seções, 1.421 palavras, com gráfico) |
| **6. Atualização do README** | Concluído | 100% | `README.md` (instruções preservadas + resultados consolidados) |
| **7. Revisão Técnica e Visual (P1 e P2)** | Concluído | 100% | Gráfico em `artigo/img/p95-por-mudanca.png` e calibragem de texto |
| **8. Publicação e Entrega** | Pronto p/ envio | 90% | Branch `main` pronta, pendente apenas commit dos novos artefatos |

---

## 3. Tasks Recentes Concluídas

### Task P2: Geração e Inserção do Gráfico de Desempenho
- **Artefato gerado:** `artigo/img/p95-por-mudanca.png` (dimensões 1200x680, design limpo, renderizado com .NET GDI+ nativo sem dependências externas).
- **Conteúdo do gráfico:**
  - Painel Esquerdo: Evolução da latência p95 geral (ms) de `14.721 ms` para `61,4 ms` (-99,58%).
  - Painel Direito: Evolução da vazão (req/s) de `4,34 req/s` para `1.513,43 req/s` (348,7x).
  - Destaques metodológicos e rodapé apontando para `resultados/`.
- **Inserção no Artigo:** Adicionada a tag markdown conforme o template do edital (página 11): `![p95 antes e depois de cada mudança](img/p95-por-mudanca.png)` na Seção 6 de `artigo/artigo.md`.

### Task P1: Calibração Textual do Artigo (`artigo/artigo.md`)
- **Contagem por Seção:**
  - Título + Resumo (Seção 1): 113 palavras (26 + 87).
  - Contexto e diagnóstico (Seção 2): 212 palavras (faixa: 150 a 250).
  - Estado da arte (Seção 3): 272 palavras (faixa: 200 a 350; 10 referências preservadas).
  - Alternativas consideradas (Seção 4): 148 palavras (faixa: tabela + 100 a 200).
  - Solução escolhida (Seção 5): 138 palavras (faixa: 100 a 200).
  - Experimento e resultado (Seção 6): 363 palavras (faixa: tabela + 100 a 200 + gráfico).
  - Limites e testes futuros (Seção 7): 140 palavras (faixa: 100 a 200).
- **Total do Corpo (Seções 1 a 7):** **1.421 palavras**.
- **Segurança de Conformidade:** 100% dentro da faixa estipulada pelo edital (800 a 1.500 palavras), com folga de 79 palavras contra o limite máximo.

---

## 4. Pendências Restantes

| Prioridade | Tarefa | Impacto / Motivo | Status |
| :---: | :--- | :--- | :---: |
| **P3** | **Commit e Push dos Novos Artefatos** | Commitar `artigo/artigo.md`, `artigo/img/p95-por-mudanca.png`, `analise/` e sincronizar com o GitHub remoto. | Aguardando autorização do usuário |
| **P4** | **Checklist Final de Entrega** | Conferir renderização visual no GitHub Web e validar que o repositório está público sem restrição de acesso. | Pré-entrega |

---

## 5. Próxima Ação Recomendada

Solicitar a autorização do usuário para registrar o commit dos novos artefatos (`artigo/artigo.md`, `artigo/img/p95-por-mudanca.png`, `analise/status-do-projeto.md` e script gerador) e, caso desejado, realizar o push para a branch `main` no GitHub.
