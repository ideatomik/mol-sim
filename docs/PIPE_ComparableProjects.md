# PIPE — Levantamento de Projetos Comparáveis

*Documento de trabalho — Embaúba*
*Compilado em: 20 de julho de 2026*

## Propósito

Busca exploratória na base de dados pública da FAPESP (exports CSV da Biblioteca Virtual, via bv.fapesp.br) por projetos PIPE comparáveis ao Zymulador — em arquitetura de simulação/ferramenta interativa, composição de equipe (solo vs. time) e vocabulário de enquadramento. Serve como referência para a Proposta Simplificada (prazo 29/07/2026) e para calibrar expectativas realistas sobre o processo.

**Nota metodológica:** os exports CSV da BV FAPESP têm um bug de formatação conhecido — um campo extra sem cabeçalho desloca as colunas em uma posição. Corrigido reconstituindo o índice (Número de Processo) e realinhando os 32 rótulos restantes. Linhas de rodapé do export (">>> Biblioteca Virtual <<<", timestamp, URL) também precisam ser descartadas antes da análise.

**Limitação importante:** a BV FAPESP publica apenas o registro referencial (título, resumo, área, equipe, datas) — nunca o Projeto de Pesquisa completo, a metodologia detalhada ou o orçamento. Não é possível reconstruir como um proponente redigiu seu desafio tecnológico ou justificou itens de custeio a partir dos dados públicos.

## Palavras-chave testadas

| Palavra-chave | Total de resultados | Resultados PIPE |
|---|---|---|
| (lote geral recente, não filtrado) | 62 | 62 (100%, lote já era só PIPE) |
| ensino | 313 | 3 |
| simulador | 23 | 2 |
| treinamento | 12 | 0 |
| (keyword não especificada — educação/aprendizagem) | 12 | 0 |
| divulgação científica | 16 | 0 |
| material didático | 54 | 4 |

## Melhores achados

| Processo | Título | Beneficiário | Solo/Time | Área | Palavra-chave | Por que é relevante |
|---|---|---|---|---|---|---|
| 14/50573-0 | Ferramenta de criação de objetos virtuais interativos multiplataformas para aplicação em método inovador de ensino na educação formal | Luiz Edmundo Lopes Mizutani | Solo | Educação | material didático | **Analógico mais próximo.** Ferramenta/engine para objetos de aprendizagem interativos, feita para educadores sem background em software poderem explorar um método pedagógico inovador — mesma lógica de "arquitetura como ponte" do Zymulador |
| 25/17812-5 | Desenvolvimento e Validação da Viabilidade Técnica de Estação Interativa para Ensino de Ressuscitação Cardíaca... através de manequim ajustável e gamificação | João Henrique do Prado (empresa Soumedical S/A) | Solo | Engenharia Biomédica | ensino, simulador, treinamento, gamificação | Estação interativa gamificada para ensino técnico, teste de viabilidade (Fase 1). Empresa está atualmente contratando Bolsas TT (mecânica, eletrônica, software) — bom exemplo real de estrutura de equipe TT |
| 24/03358-8 | Desenvolvimento de bibliotecas digitais de deformação de tecidos virtuais para treinamento cirúrgico utilizando realidade virtual e resposta robótica háptica | Elen Collaço de Oliveira (empresa Virtual Cirurgia) | Solo | Engenharia Biomédica | simulador | Desafio tecnológico é um problema de física/computação (modelo de deformação em tempo real), não de conteúdo — mesma estrutura do "problema arquitetural" do Zymulador. Fase 2, validação em um único caso (gastrectomia), parceria institucional (LEPIC/HC-USP) |
| 26/04169-0 | Desenvolvimento da Sistema de Q&A (Perguntas e Respostas)... | Roberta Elaine dos Santos Lotto | Solo (com Bolsa PE própria) | Ciência da Computação | (lote geral) | Caso de "software simples que recebeu financiamento" — escopo definido e honesto (etapa 1 é só a base de dados estruturada; a camada de IA fica para depois). Exemplo de como não superprometer no Fase 1 |
| 24/13300-7 | Metodologia para Predição do Nível de Sonolência e Atenção de Motoristas Através da IA — Waker App | Patrick Neri de Oliveira (PP: Elaine Cristina Marqueze) | **Time** (PR + PP) | Ciência da Computação | simulador | Único exemplo de equipe com PP na amostra. Fase 2 após Fase 1 aprovada — mostra o pipeline Fase 1→Fase 2 na prática. PP provavelmente traz domínio complementar (saúde ocupacional/sono) |
| 25/18257-5 | Desenvolvimento de Jogos e Robótica para Recuperação Funcional pós-AVC | Daniel Seiei Uehara Tamashiro | Solo | Engenharia Biomédica | (lote geral) | Jogo + robótica para reabilitação — outro exemplo de gamificação aplicada a um problema técnico sério |

### Achados fora do PIPE (referência, não comparáveis diretos)

- **25/02262-0** — "Tópicos de física das radiações para o ensino médio" (Neilo Marcos Trindade, USP) — Auxílio Regular, não PIPE. Projeto acadêmico com 4 Bolsas IC vinculadas, metodologia "Ensino por Investigação" + "Cultura Maker", alinhado à BNCC. Rota de financiamento diferente (exige PI acadêmico, não empresa) — anotado como possível trilha futura separada, não para esta submissão.
- **23/03176-4** — "Tecnologia e Educação: o jogo digital como ferramenta de aprendizagem sobre Roma Arcaica" — Auxílio Regular, não PIPE. Jogo educacional, mas via financiamento acadêmico.

## Lições aprendidas

1. **Fundadores solo são comuns e aprovados no PIPE.** Cinco dos seis melhores achados são PR único, sem Pesquisador Principal. Isso não confirma nem refuta a leitura do consultor sobre viés institucional, mas é evidência direta de que perfil solo não é, por si só, impeditivo nesta chamada.
2. **"Material didático" tem histórico real de décadas no PIPE** (achados de 1999 a 2016); **"ensino" sozinho quase não aparece** mesmo em projetos claramente educacionais. Vocabulário de enquadramento nos campos 1/2/4 deveria priorizar "material didático interativo", "treinamento", "simulador" sobre "ensino".
3. **O desafio tecnológico mais convincente nos achados é sempre um problema técnico/computacional específico**, não uma alegação de dificuldade pedagógica genérica — reforça a decisão já tomada de ancorar a proposta na costura de fechamento de ciclo do Krebs, não em "biologia molecular é difícil de ensinar".
4. **Escopo Fase 1 explicitamente contido** aparece nos dois melhores exemplos (Q&A system, VR surgical training) — nenhum deles promete o produto final na Fase 1, ambos deixam clara a fronteira entre o que está sendo testado agora e o que vem depois.
5. **Falsos positivos são comuns** em busca por palavra-chave — nome de empresa contendo o termo (ex: "Tergos Pesquisa e Ensino S.A." não tinha relação com ensino), ou uso do termo em contexto não relacionado ("treinamento físico aeróbio" em ratos). Sempre verificar o resumo antes de citar como comparável.
6. **BV FAPESP não é fonte para metodologia ou orçamento** — apenas para confirmar que um tipo de proposta (perfil de equipe, área, escopo) foi aprovado. Não há como "ver como a proposta foi escrita" além do resumo público.
7. **Links diretos não são construtíveis a partir do número de processo** — a URL da BV usa um ID interno de banco de dados, não o número de processo. É preciso buscar cada página individualmente.
