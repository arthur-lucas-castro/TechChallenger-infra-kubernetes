# ADR-004 — Observabilidade com Datadog sem a integração AWS

- **Status:** Aceito
- **Data:** 2026-11-02
- **Repositórios afetados:** `TechChallenger-infra-kubernetes`, `TechChallenger-Api`, `TechChallenger-severless`

## Contexto

O requisito de **Monitoramento e Observabilidade** pede integração com Datadog ou New Relic para acompanhar latência das APIs, CPU e memória do Kubernetes, healthchecks, alertas de falha no processamento de ordens de serviço, logs estruturados com correlação entre requisições e dashboards de volume de OS, tempo por status e falhas nas integrações.

O sistema tem quatro pontos a observar: a API .NET no EKS, a Lambda de autenticação, o RDS e o API Gateway.

Restrição do ambiente: o AWS Academy Learner Lab não permite criar IAM roles. A integração AWS nativa do Datadog depende de uma role que o Datadog assume para ler métricas e logs do CloudWatch, e o Datadog Forwarder também é distribuído com uma role própria.

## Alternativas consideradas

### Opção A — New Relic

- **Prós:** plano gratuito permanente, sem trial de 14 dias.
- **Contras:** a coleta de Lambda em VPC também depende de layer e de chave em segredo, e a integração AWS tem a mesma exigência de role. Não resolve a restrição e a equipe tem mais material de referência do Datadog para EKS.

### Opção B — Datadog com a integração AWS (CloudWatch)

- **Prós:** métricas de API Gateway, Lambda e RDS sem código, num único lugar.
- **Contras:** inviável no Learner Lab, por exigir IAM role. Usar chaves de acesso no lugar da role não funciona por muito tempo: as credenciais do lab expiram a cada sessão.

### Opção C — Datadog coletando de dentro de cada componente

- **EKS:** agente pelo chart Helm `datadog/datadog` (DaemonSet + Cluster Agent), instalado pelo workflow `datadog.yml` deste repositório.
- **API .NET:** tracer injetado pelo admission controller do Cluster Agent, logs JSON lidos pelo agente e métricas de negócio por DogStatsD.
- **Lambda:** layers `Datadog-Extension` e `Datadog-Node20-x`. A extensão roda junto da função e envia logs, métricas e traces direto ao Datadog, sem passar pelo CloudWatch.
- **Prós:** nenhuma IAM role nova; a API key fica só no SSM; logs, traces e métricas de todos os serviços correlacionados pelo `service` e pelo trace id.
- **Contras:** os access logs do API Gateway e as métricas do RDS ficam fora do Datadog. A extensão aumenta o cold start da Lambda.

## Decisão

**Opção C.**

| Componente | Como chega ao Datadog | O que cobre |
|---|---|---|
| Nodes e pods do EKS | Agente (kubelet + kube-state-metrics) | CPU, memória, réplicas do HPA, restarts |
| API .NET | Tracer injetado + logs do container + DogStatsD | Latência e erros por rota (APM), queries no RDS, logs com `CorrelationId` e trace id, métricas `oficina.*` |
| Lambda de autenticação | Datadog Lambda Extension + `datadog-lambda-js` | Invocações, erros, duração, cold start, traces com as queries no RDS, logs, `oficina.integracao.falha` |
| Healthcheck e uptime | Synthetic test no `/health` pelo API Gateway | Disponibilidade vista de fora da AWS |

As métricas próprias usam o prefixo `oficina.`. Falhas de integração (SMTP na API, banco e SSM na Lambda) usam a mesma métrica, `oficina.integracao.falha`, como **distribution**: é o único tipo que a biblioteca da Lambda envia, e uma métrica precisa ter um só tipo no Datadog.

A latência das APIs vem do APM da própria API, e não do API Gateway. O `x-correlation-id` que o gateway injeta (o `requestId` dos access logs) é gravado nos logs e nos spans da API, então um access log do CloudWatch ainda pode ser cruzado com o Datadog quando preciso.

Dashboard, monitores e teste de uptime são **código**, no módulo `observability/` deste repositório (provider `DataDog/datadog`, state próprio), aplicados pelo workflow `observability.yml`. Criados à mão na interface, eles se perderiam a cada conta de trial nova e não ficariam versionados nem revisáveis em PR.

## Consequências

- Os nodes precisam ser `t3.small`: no `t3.micro` cada node aceita só 4 pods, e o DaemonSet do agente não cabe.
- A API key é publicada uma vez no SSM (`/techchallenger/datadog/api-key`) e lida pelo workflow do agente e pela extensão da Lambda. Ela não passa pelo tfstate nem pelos repositórios.
- O pacote da Lambda deixa o `pg` fora do bundle do esbuild e o envia em `node_modules`, para o tracer conseguir instrumentá-lo.
- Trocar de conta Datadog é mudar a API key no SSM e o secret `DATADOG_APP_KEY`, e rodar de novo `infra-apply.yml`, `datadog.yml` e `observability.yml` com o site novo. O dashboard e os alertas voltam iguais.
- Mudanças no dashboard feitas pela interface são sobrescritas no próximo apply; o caminho é editar `observability/dashboard.tf`.
- As queries do dashboard e dos monitores dependem dos nomes de service, deployment, função e métricas dos outros repositórios. Renomear algo lá exige ajustar `observability/variables.tf`.
- Se o ambiente sair do Learner Lab, a integração AWS (Opção B) pode ser somada a esta, trazendo API Gateway e RDS sem mudar o que já existe.
