# PIPE Jornada Tecnológica — Proposta Simplificada (rascunho)

_Rascunho para os 5 campos obrigatórios da aba "Campos adicionais" no SAGe,
dentro dos limites de caracteres da Chamada. Escrito para revisão — não
enviar sem sua checagem, especialmente os pontos marcados **[VERIFICAR]**.
Chamada: PIPE Jornada Tecnológica 1ª Rodada 2026 – Fase 1. Prazo: 29/07/2026._

**Prêmissa do rascunho**: o desafio tecnológico apresentado é a costura de
wraparound do Ciclo de Krebs (topologia cíclica), não o simulador de
replicação em si — a replicação já é um "conceito demonstrado" e, pelo
item 8.5(a) da Chamada, projetos de conceito já demonstrado não são
financiáveis. O rascunho segue rigorosamente o enquadramento já discutido
no TODO.md: o spike deve permanecer *teste preliminar*, nunca *conceito já
demonstrado* — evitar qualquer redação que soe "resolvido" demais.

---

## Campo 1 — O Problema e o "Pulo do Gato" (O Desafio Tecnológico)
_Limite: 1.500 caracteres · Rascunho: ~1.390_

> A Dor (Problema de Mercado): Simulações educacionais de biologia molecular
> tratam processos dinâmicos — replicação, ciclos metabólicos — como
> animações lineares de sentido único. Professores e alunos não conseguem
> retroceder, pausar em qualquer instante ou revisitar um estado
> intermediário sem quebrar a coerência visual. Essa limitação é
> especialmente grave em processos cíclicos (ex: Ciclo de Krebs), onde o
> próprio conceito pedagógico central — a natureza cíclica, sem início ou
> fim fixos — exige que o aluno possa entrar na simulação em qualquer ponto
> do ciclo e navegar livremente para frente e para trás, algo que
> ferramentas de animação convencionais (sentido único, baseadas em tempo
> real) não suportam estruturalmente.
>
> O Diferencial: O MolSim (Zymosim) já implementa, para a replicação do DNA
> (processo linear), uma arquitetura "scrub-safe" — qualquer estado da
> simulação é alcançado instantaneamente, para frente ou para trás, sem
> estados intermediários inválidos. Não há evidência, na literatura ou em
> produtos concorrentes, de que essa arquitetura generalize para processos
> de topologia cíclica, onde a costura de "wraparound" (o ponto em que o
> ciclo se fecha sobre si mesmo) introduz um problema estrutural ausente em
> processos lineares. Não identificamos concorrentes ou patentes que
> resolvam esse problema especificamente.

**[VERIFICAR]** — "Não identificamos concorrentes ou patentes" é uma
afirmação forte para o item 8.5(a.6) ("não há propriedade intelectual...
que interfiram"). Vale uma checagem mínima antes de enviar, mesmo que
informal.

---

## Campo 2 — A Incerteza Técnica (Objetivos de Pesquisa)
_Limite: 1.500 caracteres · Rascunho: ~1.195_

> O Desafio Científico: a dúvida técnica central é se a arquitetura
> scrub-safe já validada para a replicação (disparo de eventos por índice
> discreto, nunca por tempo real; invariantes de estado recalculáveis a
> qualquer ponto) pode ser estendida a um processo cíclico sem recorrer a
> soluções ad hoc por caso. Especificamente: como representar, de forma
> genérica, a costura onde o ciclo se fecha — o ponto em que o estado final
> de uma volta se torna o estado inicial da próxima — de modo que o
> scrubbing bidirecional permaneça correto e instantâneo através dela? Não
> há garantia a priori de que a mesma disciplina arquitetural se sustente
> quando o grafo de estados deixa de ser uma linha e passa a ser um ciclo.
>
> Onde estamos: a replicação do DNA está implementada, estável e testada
> (helicase, polimerases, maturação de fragmentos de Okazaki, topologia
> linear e circular do cromossomo). Não implementamos, até o momento,
> nenhum processo cíclico. O projeto começa do zero nesse eixo: um teste
> preliminar mínimo, limitado a duas enzimas do Ciclo de Krebs (citrato
> sintase e malato desidrogenase), desenhado para expor — não para evitar —
> o problema da costura.

---

## Campo 3 — Mãos à Obra (Metodologia e Etapas)
_Limite: 2.000 caracteres · Rascunho: ~1.540_

> Fase 1 — Modelagem da topologia cíclica: estender o padrão de "mode-gate"
> já usado no MolSim para a topologia linear/circular do cromossomo a um
> novo eixo — processo linear vs. processo cíclico — definindo como o
> índice de estado, hoje um contador linear, se comporta ao cruzar a
> costura do ciclo.
>
> Fase 2 — Spike mínimo de duas enzimas: implementar citrato sintase
> (fusão, unindo acetil-CoA ao oxaloacetato) e malato desidrogenase (última
> etapa, regenerando o oxaloacetato que fecha o ciclo). A escolha dessas
> duas — primeira e última do ciclo — é deliberada: juntas formam a menor
> unidade de teste que efetivamente atravessa a costura, sem exigir as
> demais seis enzimas intermediárias.
>
> Fase 3 — QCA (validação por scrubbing caótico) agressivo: navegação
> bidirecional exaustiva através da costura, em múltiplas velocidades e a
> partir de múltiplos pontos de entrada, para localizar falhas de
> invariante — o mesmo protocolo que já revelou bugs reais durante o
> desenvolvimento da replicação.
>
> Fase 4 — Generalização ou especialização: com base nos resultados do
> spike, decidir se a arquitetura cíclica exige uma camada compartilhada
> nova ou se cada processo cíclico futuro (ciclo da ureia, fotossíntese)
> exigirá tratamento individual da costura.
>
> Fase 5 — Validação pedagógica: demonstração com docentes de
> genética/bioquímica (já em andamento informalmente) para confirmar que a
> navegação livre pelo ciclo melhora a compreensão do conceito frente à
> animação linear tradicional.

**Há ~460 caracteres de folga aqui** — bom lugar para inserir um cronograma
aproximado (meses 1–3 Fase 1–2, 4–8 Fase 3, 9–12 Fase 4–5) se quiser algo
mais concreto para o item 8.5(a.5), "o prazo proposto... é adequado".

---

## Campo 4 — Oportunidade de Mercado (Viabilidade Comercial)
_Limite: 1.500 caracteres · Rascunho: ~895_

> O Produto: um módulo de simulação do Ciclo de Krebs, com a mesma
> navegação bidirecional instantânea já disponível para a replicação do
> DNA, integrado ao simulador MolSim/Zymosim. O motor de simulação
> (engine) é disponibilizado como software de código aberto, auditável e
> autoinstalável por qualquer professor ou instituição, sem custo.
>
> Quem Paga: o modelo de negócio da Embaúba é "open-core" — o motor
> educacional é gratuito e aberto; a receita vem de uma camada de
> plataforma comercial vendida a instituições de ensino: hospedagem sem
> instalação, painel do professor com acompanhamento de turma, integração
> com sistemas de gestão escolar (LMS) e suporte prioritário. Esse modelo
> evita que o acesso ao conteúdo educacional dependa de pagamento, ao mesmo
> tempo em que sustenta financeiramente o desenvolvimento contínuo via
> contratos institucionais recorrentes.

**[DECISÃO PENDENTE]** — Este campo assume o **Modelo A (Híbrido)** do
`FinancingModels.md`, por ser a narrativa mais direta para um avaliador
PIPE (item 8.5.c pede explicitamente "como a empresa pretende
desenvolver, comercializar ou negociar os resultados"). Se você decidir
pelo Modelo B (open source total, à la Kurzgesagt) antes do envio, este
campo precisa ser reescrito — tenho ~600 caracteres de folga para isso,
mas a narrativa muda de "venda institucional" para "patrocínio/doação
recorrente com fila de desenvolvimento priorizável", o que é uma resposta
menos convencional para um avaliador de fomento a produto. Vale decidir
isso antes de mexer neste campo, não depois.

---

## Campo 5 — Quem Vai Fazer Acontecer (Equipe e Complementaridade)
_Limite: 1.500 caracteres · Rascunho: ~965_

> O Time: Henrique **[SOBRENOME]**, fundador e Pesquisador Responsável,
> graduando em **[CURSO]** na UNESP, com experiência prática em
> desenvolvimento de software (Godot/GDScript) e conhecimento de biologia
> molecular obtido através de validação contínua com docentes de genética
> da própria universidade. Detém as competências técnicas críticas para a
> execução do projeto — arquitetura de simulação, engenharia de software e
> design pedagógico — dispensando a indicação de um Pesquisador Principal
> adicional.
>
> A Empresa: a Embaúba (CNPJ sob o regime Inova Simples) já desenvolveu e
> mantém o MolSim/Zymosim — simulador de replicação de DNA funcional,
> testado e validado informalmente com docentes da área — demonstrando
> capacidade de execução técnica ponta a ponta, da arquitetura ao produto
> utilizável em sala de aula. Para suprir a equipe complementar prevista
> pelo PIPE, o orçamento inclui a solicitação de Bolsa de Treinamento
> Técnico.

**[VERIFICAR]** — preencher sobrenome e curso. Se a demo de hoje com o
professor de genética render uma frase de endosso citável ("já testado
informalmente com docentes"), isso reforça diretamente o critério 8.5(f.2)
sobre capacidade da equipe — vale registrar como foi recebida.

---

## Itens fora dos 5 campos, mas necessários para a Proposta Simplificada

Pelo item 6.1 da Chamada, além destes 5 campos você também precisa, antes
do fechamento:
- Súmula Curricular sua (modelo em fapesp.br/sumula)
- Orçamento na aba R$/US$ (capital, custeio, bolsas) — a Bolsa de
  Treinamento Técnico mencionada no Campo 5 precisa aparecer aqui também,
  com justificativa e plano de atividades
- Confirmação de que a empresa já está cadastrada no SAGe (se não, o
  cadastro tem que ser pedido com **2 dias úteis de antecedência** do
  fechamento — isso é urgente dado o prazo de 29/07)

Nenhum desses depende do e-mail para pipe-jornada@fapesp.br que você vai
mandar amanhã — pode preparar em paralelo.
