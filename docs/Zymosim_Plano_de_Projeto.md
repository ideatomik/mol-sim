# Zymosim (ex-MolSim) — Plano de Projeto e Financiamento

*Documento de trabalho — Embaúba*
*Última atualização: 10 de julho de 2026*

---

## 1. Direção do Produto

**Mudança de escopo:** de um simulador focado exclusivamente em replicação do DNA para uma arquitetura de simulação generalizável — "estado derivado de um regente único" — aplicável a múltiplos processos da biologia molecular.

- **Insight arquitetural:** a arquitetura já validada (posição do helicase como fonte única de verdade, da qual todo o resto deriva de forma determinística, sem relógios independentes) não é exclusiva da replicação do DNA. Ela generaliza bem para processos que são fundamentalmente **máquinas de estado ordenadas** (vias cíclicas, abertura/fechamento de canais, replicação linear), mas exige variantes para processos **ramificados ou difusos** (cascatas de sinalização, tráfego vesicular).
- **Carro-chefe do lançamento:** Ciclo de Krebs — identificado como o conceito mais difícil de entender pelo público testado, e o de maior "efeito uau" potencial.
- **"Entrega extra" do lançamento:** replicação do DNA — já construída e estável (v75+), servindo como prova de que o produto já entrega mais do que promete no lançamento.
- **Ordem de implementação já definida antes desta expansão de escopo:** primase → ligase → telomerase → Pol I → PCR (mantida como está; Krebs entra como uma segunda frente, não substitui a fila da replicação).

### Lista de processos-alvo (ordenados por dificuldade conceitual)

Ver documento de referência completo (gerado em conversa anterior) para a lista de 28 processos candidatos, classificados por dificuldade pedagógica e por encaixe arquitetural (🟢 trilha única / 🟡 máquina de estados cíclica ou discreta / 🟠 ramificado ou parcialmente estocástico / 🔴 mal encaixado). Destaques:

- **Nível 1-2 (bom encaixe, prioridade):** transcrição, tradução, glicólise, ciclo de Krebs, bomba Na+/K+, mitose
- **Nível 3 (encaixe médio, alvo de expansão):** cadeia transportadora de elétrons, fotossíntese, PCR, telomerase
- **Nível 4 (desafio arquitetural real, ambição de longo prazo):** cascatas GPCR, apoptose, neurotransmissão

---

## 2. Prova de Conceito — Ciclo de Krebs (spike técnico)

**Sequenciamento:** após a finalização do ciclo de replicação do DNA (Pol I concluído), antes da finalização da Proposta Simplificada do PIPE.

**Escopo deliberadamente mínimo** — para permanecer como "teste preliminar" e não como "conceito já demonstrado" (o que desqualificaria o projeto nos critérios do PIPE):

1. **Citrato sintase** — testa um **evento de fusão** (acetil-CoA + oxaloacetato → citrato), algo que a replicação do DNA nunca exigiu (que só testou divisões/cópias, nunca a fusão de duas entradas independentes em um único estado rastreado).
2. **Malato desidrogenase** — testa a **regeneração do oxaloacetato**, fechando o ciclo.
3. **Verificação de scrub-safety na costura de fechamento do ciclo** (virada da 8ª etapa de volta à 1ª etapa do turno seguinte) — o teste arquitetural mais valioso, já que é algo que a replicação linear estruturalmente não pode testar.

Etapas intermediárias (isocitrato desidrogenase etc.) ficam de fora do spike — arquiteturalmente seriam "mais do mesmo" uma vez provados a fusão e a transformação de trilha única.

---

## 3. Nome do Produto

**Zymosim** — candidato sobrevivente após uma primeira triagem de conflitos:

| Nome | Veredito | Conflito encontrado |
|---|---|---|
| Zimula | ❌ Rejeitado | Plataforma de software "Zimula" ativa (zimula.cloud) + família tipográfica homônima |
| Simbiota | ❌ Rejeitado | SIMBIoTA (ferramenta de segurança IoT open-source) + Simbiota Consultoria Ambiental (empresa brasileira ativa) |
| Zymbio | ⚠️ Risco moderado | zymbio.cl — consultoria de distribuição de marcas na América Latina |
| **Zymosim** | ✅ Mais limpo | Nenhuma colisão direta encontrada; vizinhos mais próximos ("Zymosoft", ferramentas "Zsim") são grafias diferentes em áreas não relacionadas |

**Pendência:** checagem formal de disponibilidade de marca (INPI — Brasil) e domínio/trademark internacional (WIPO/USPTO) antes de qualquer investimento em logo, domínio ou lançamento de campanha.

---

## 4. Financiamento — Trilha Brasileira

| Iniciativa | Status / Prazo | Observações |
|---|---|---|
| **PIPE Jornada Tecnológica — Chamada 33/2026 (Geral)** | Pré-proposta até **29/07/2026** | Sem restrição temática; enquadramento via Proposta Simplificada, proposta completa (se enquadrada) até 28/09/2026 |
| Esclarecimento com FAPESP sobre elegibilidade de graduando como Pesquisador Principal | E-mail a enviar para pipe-jornada@fapesp.br | O texto da chamada só exclui explicitamente mestrandos/doutorandos do papel de Pesquisador Principal — graduação não é mencionada como impeditivo |
| **PIPE Jornada Tecnológica — 7ª Chamada, Educação** | Lançamento previsto: 13/10/2026 | Alinhamento temático direto com o produto; acompanhar publicação |
| **Programa DNA (USP/Ipen, via Cietec)** | Inscrições do lote atual encerradas | Acompanhar próximo lote (historicamente dez/jan) |
| Agência UNESP de Inovação (AUIN) / NIT | Não explorado ainda | Vale contato direto dado o vínculo institucional já existente via incubadora do campus |

---

## 5. Financiamento — Trilha Internacional

| Iniciativa | Encaixe | Observações |
|---|---|---|
| **IDB Lab (BID Lab)** | 🟢 Forte | Braço de inovação/venture do BID; já financiou programas de edtech no Brasil (ex: Impulsionar, com Fundação Lemann e Imaginable Futures). Sem chamada aberta identificada no momento — acompanhar bidlab.org / iadb.org |
| **MIT Solve** | 🟢 Bom | Desafio global aberto por nacionalidade, sem exigência de faturamento. Ciclo mais recente encerrado (21/05/2026) — acompanhar próximo ciclo anual |
| **Global EdTech Startup Awards** | 🟡 Reconhecimento, não financiamento direto | Baseado em indicação, prazo 15/09/2026 — baixo custo de aplicação, bom para credibilidade |
| **National Geographic Society (grants)** | 🟡 A verificar | Financia educação/divulgação científica globalmente; checar categorias vigentes |
| **Wellcome Trust** | 🟡 A verificar | Financia engajamento científico globalmente, foco mais voltado à área de saúde — checar se o enquadramento do Krebs (bioenergética) se encaixa |
| **Google for Startups Brasil** | 🟡 Credencial, não caixa | Mentoria + créditos de nuvem, não é financiamento direto |
| **BrazilLAB** | 🟡 Complementar | Não é financiamento estrangeiro, mas ponte B2G relevante para venda a redes públicas de ensino — combina bem com o modelo do IDB Lab |

**Inelegíveis (verificados e descartados):**
- Mastercard Foundation EdTech Fellowship — restrito a Gana
- US Dept. of Education / IES SBIR — restrito a empresas registradas nos EUA
- Digital Europe Programme / EIT Health — restrito a entidades da UE
- Spencer Foundation — tipo de financiamento incompatível (pesquisa acadêmica, não desenvolvimento de produto)

---

## 6. Crowdfunding

### Plataformas
- **apoia.se** (público brasileiro) — modalidade Contínua: taxa fixa de 13%; modalidade Pontual: taxa escolhida entre 6-15%
- **Buy Me a Coffee** (público internacional) — taxa de 5% + processamento Stripe (~2,9% + $0,30); **pendência: confirmar suporte de repasse via Stripe Connect para o Brasil antes de divulgar amplamente**

### Tiers públicos (baseados em valor)

**apoia.se (mensal):**
| Tier | Preço sugerido | Recompensa |
|---|---|---|
| Apoiador | R$5-10/mês | Nome nos créditos, cargo no Discord, devlogs antecipados |
| Colaborador | R$20-25/mês | + Acesso antecipado a builds, voto no próximo processo biológico da fila |
| Mantenedor | R$40-50/mês | + Nome em tela de "fundadores" no app, Q&A mensal em texto |
| Instituição/Professor | R$80-100/mês | + Licença antecipada gratuita para a própria turma, prioridade em feedback pedagógico |

**Buy Me a Coffee (avulso/tip):**
| Tier | Preço sugerido | Recompensa |
|---|---|---|
| Coffee | $3 | Agradecimento público |
| Supporter | $10 | + Créditos no app, cargo no Discord |
| Founding Backer | $25 | + Acesso antecipado, voto no roadmap |
| Champion | $50+ | + Nome permanente na tela de fundadores, menção em trailer/devlog |

### Recompensas privadas — amigos pessoais (fora da página pública de campanha)

- **Founding Friend** — selo privado para apoiadores pessoais anteriores ao lançamento; tela de créditos separada da pública, acesso a conteúdo de bastidores (bloopers, protótipos feios, bugs engraçados), agradecimento pessoal direto. Threshold de elegibilidade a definir de forma privada, não atrelado a valor.
- **Name an Enzyme** — modo "divertido" oculto (mesmo padrão do toggle de debug de locale já existente) que troca rótulos científicos por apelidos escolhidos por apoiadores. Rótulos científicos continuam sendo o padrão real sempre — aditivo, nunca substitui o conteúdo educacional. Número de "vagas" cresce naturalmente conforme mais enzimas são implementadas (4 hoje, crescendo com Krebs). **Aprovação silenciosa dos nomes antes de publicar, dado o uso em sala de aula.**

---

## 7. Pendências Abertas

- [ ] Redação final da Proposta Simplificada (PIPE, prazo 29/07/2026), incorporando o enquadramento ampliado (Krebs + DNA) e o spike de prova de conceito
- [ ] Envio do e-mail de esclarecimento para pipe-jornada@fapesp.br sobre elegibilidade como Pesquisador Principal
- [ ] Spike técnico do Ciclo de Krebs (citrato sintase + malato desidrogenase + verificação de scrub na costura do ciclo) — após conclusão da Pol I
- [ ] Checagem de disponibilidade de marca/domínio para "Zymosim" (INPI + WIPO/USPTO)
- [ ] Confirmar suporte de repasse Stripe Connect para o Brasil (Buy Me a Coffee)
- [ ] Redação de copy de campanha em PT-BR e EN
- [ ] Estrutura de dados do modo "fun mode" / Name an Enzyme
- [ ] Definir threshold privado para o tier Founding Friend
- [ ] Estabelecer cadência de monitoramento para chamadas do IDB Lab e ciclos do MIT Solve
- [ ] Contato com AUIN/NIT da Unesp

---

*Este documento consolida decisões e discussões até 10/07/2026. Deve ser atualizado conforme o plano evolui.*
