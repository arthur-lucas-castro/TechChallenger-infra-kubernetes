# ADR-003 — Integração do API Gateway com a API no EKS

- **Status:** Aceito
- **Data:** 2026-10-27
- **Repositórios afetados:** `TechChallenger-infra-kubernetes`, `TechChallenger-Api`

## Contexto

O requisito de **Autenticação e API Gateway** pede um API Gateway na frente da aplicação. O [ADR-002](https://github.com/arthur-lucas-castro/TechChallenger-severless/blob/main/docs/adr/ADR-002-localizacao-terraform-lambda-api-gateway.md) decidiu que o gateway é um **HTTP API** (API Gateway v2) gerenciado por este repositório, e o fluxo de autenticação definiu que a integração com o EKS é **privada, via VPC Link** para um load balancer interno.

Hoje a API é exposta por um Service `type: LoadBalancer` (`k8s/aws/service.yaml` do TechChallenger-Api), que cria um **NLB público** fora do state do Terraform. Isso tem dois problemas para o gateway:

1. a integração `VPC_LINK` do HTTP API precisa do **ARN do listener** do NLB/ALB, e um NLB criado pelo Kubernetes só existe depois do deploy da aplicação, fora do plan do Terraform;
2. com o NLB público, a API continua acessível **sem passar pelo gateway**, o que anula throttling, access logs e (no futuro) o Lambda Authorizer.

Restrição do ambiente: o AWS Academy Learner Lab não permite criar IAM roles, então não dá para instalar o **AWS Load Balancer Controller** com IRSA.

## Alternativas consideradas

### Opção A — NLB interno criado pelo Kubernetes (`aws-load-balancer-internal`) + lookup por tag

O Service passa a ser interno e o Terraform encontra o NLB com `data "aws_lb"` por tag.

- **Prós:** nenhuma mudança de modelo no Kubernetes.
- **Contras:** o data source falha se o NLB ainda não existir, então o primeiro apply depende do deploy da aplicação (ciclo `infra → app → infra`). Recriar o Service troca o NLB e quebra o gateway até um novo apply.

### Opção B — AWS Load Balancer Controller + `TargetGroupBinding`

- **Prós:** padrão de mercado; target type `ip` direto nos pods.
- **Contras:** exige IAM role própria para o controller (indisponível no Learner Lab) ou dar permissões de ELB à `LabRole` dos nodes. Mais um componente para instalar e manter.

### Opção C — NLB interno no Terraform + NodePort fixo (escolhida)

O Terraform cria NLB interno, target group (`instance`, porta NodePort), listener e anexa o **Auto Scaling Group do node group** ao target group. A aplicação expõe o Service como `NodePort` em uma porta fixa.

- **Prós:** tudo que o gateway precisa está no mesmo state e é conhecido no plan. Ordem de provisionamento continua linear. Nodes novos do scaling entram no NLB automaticamente. Sem IAM extra. A API deixa de ter endereço público fora do gateway.
- **Contras:** acopla os dois repositórios por um número de porta (`api_node_port`, default `30080`). Há um salto extra (node → kube-proxy → pod), irrelevante nesta escala.

## Decisão

**Opção C.** Fluxo de uma requisição:

```
Cliente ──HTTPS──► API Gateway (HTTP API, stage $default)
                     │  throttling, access log JSON, x-correlation-id
                     ▼
                  VPC Link (ENIs nas subnets privadas)
                     ▼
                  NLB interno :80 ──► nodes EKS :30080 (NodePort) ──► pods techchallenger-api :8080
```

- Rota `ANY /{proxy+}` → integração `HTTP_PROXY` com o listener do NLB.
- O gateway injeta `x-correlation-id = $context.requestId`, o mesmo id dos access logs, para correlacionar logs do gateway e da API.
- O Lambda Authorizer e as rotas `POST /auth*` serão adicionados neste mesmo HTTP API quando a infraestrutura das Lambdas for criada (ADR-002). Rotas mais específicas (`POST /auth`) têm prioridade sobre `/{proxy+}`.

## Consequências

- **TechChallenger-Api:** o `k8s/aws/service.yaml` passa a ser:

  ```yaml
  spec:
    type: NodePort
    selector:
      app: techchallenger-api
    ports:
      - port: 8080
        targetPort: 8080
        nodePort: 30080   # output api_node_port deste repositório
        protocol: TCP
  ```

  A anotação `service.beta.kubernetes.io/aws-load-balancer-type` deixa de ser necessária. O endereço público da API passa a ser o output `api_gateway_endpoint`.
- O SG primário do cluster ganha uma regra de entrada na porta `api_node_port` a partir do CIDR da VPC (VPC Link e health checks do NLB).
- O `null_resource.cleanup_k8s_load_balancers` continua útil para qualquer Service `LoadBalancer` criado fora do Terraform, mas deixa de ser necessário para a API.
- Trocar `api_node_port` exige mudar os dois repositórios: primeiro o Service da aplicação, depois o apply deste repositório.
