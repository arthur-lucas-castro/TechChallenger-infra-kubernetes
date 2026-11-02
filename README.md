# TechChallenger-infra-kubernetes

Infraestrutura de plataforma e borda da oficina mecânica na AWS, provisionada com **Terraform**: **VPC**, cluster **EKS**, node group, repositório **ECR**, componentes do cluster (**metrics-server**), a **Lambda de autenticação** e o **API Gateway** (HTTP API) que é a porta de entrada da aplicação.

O projeto roda em uma conta **AWS Academy Learner Lab**. Isso impõe restrições que aparecem em várias decisões abaixo: não é possível criar IAM roles novas, as cotas de EC2/vCPU são baixas e as credenciais são temporárias.

## Repositórios do projeto

| Repositório | Responsabilidade |
|---|---|
| **TechChallenger-infra-kubernetes** (este) | VPC, EKS, node group, ECR, metrics-server, bucket do state, **API Gateway** e infraestrutura da Lambda de autenticação |
| [TechChallenger-infra-database](https://github.com/arthur-lucas-castro/TechChallenger-infra-database) | RDS PostgreSQL |
| [TechChallenger-severless](https://github.com/arthur-lucas-castro/TechChallenger-severless) | Código das Lambdas de autenticação por CPF (o Terraform delas fica aqui, ver ADR-002) |
| [TechChallenger-Api](https://github.com/arthur-lucas-castro/TechChallenger-Api) | API da oficina e manifestos Kubernetes da aplicação (Service `NodePort` atrás do gateway) |

**Ordem de provisionamento:** **1. infra-kubernetes** → 2. infra-database → 3. severless / Api.
**Ordem de destruição:** a inversa. O workflow de destroy deste repo bloqueia a execução enquanto o state do infra-database ainda tiver recursos.

## Arquitetura

```
                                   AWS (us-east-1)
  Cliente ──HTTPS──► API Gateway (HTTP API, stage $default)
                       │ throttling · access logs JSON · x-correlation-id
                       │ POST /auth* → Lambda de autenticação (subnets privadas)
                       │ (em breve: Lambda Authorizer)
                       │ ANY /{proxy+}
┌──────────────────────┼───────────────────────────────────────────────────┐
│  VPC (10.0.0.0/16)   ▼                                                     │
│                                                                            │
│  ┌─── Subnets públicas ───┐   ┌─── Subnets privadas ───────────────────┐  │
│  │  Internet Gateway      │   │  VPC Link (ENIs)                        │  │
│  │  NAT Gateway ◄─────────┼───┤     │                                   │  │
│  └────────────────────────┘   │     ▼                                   │  │
│                               │  NLB interno :80                        │  │
│                               │     │                                   │  │
│                               │     ▼                                   │  │
│                               │  EKS Node Group :30080 (NodePort)       │  │
│                               │  (t3.micro, 1-3 nodes) → pods da API    │  │
│                               │                                         │  │
│                               │  RDS ◄── infra-database                 │  │
│                               └─────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────┘

  ECR (imagem Docker da API) ── consumido pelo EKS
  CloudWatch Logs ── access logs do gateway, logs do control plane do EKS
```

## Estrutura

| Caminho | Conteúdo |
|---|---|
| `bootstrap/` | Bucket S3 + tabela DynamoDB do state remoto, compartilhados por todos os repositórios (aplicado uma única vez) |
| `backend.tf` | Backend S3, `key = infra-kubernetes/terraform.tfstate` |
| `vpc.tf` | VPC, subnets, IGW, NAT |
| `eks.tf` | Cluster, node group, cleanup de load balancers no destroy |
| `ecr.tf` | Repositório da imagem da API |
| `api-gateway.tf` | HTTP API, stage `$default`, access logs, VPC Link, integração e rotas |
| `nlb.tf` | NLB interno da API, target group no NodePort, anexo ao ASG dos nodes, regra no SG dos nodes |
| `lambda.tf` | Lambda de autenticação, SG, log group, integração, rotas `POST /auth*` e permissão de invocação |
| `addons/metrics-server.yaml` | metrics-server v0.9.0 (pré-requisito do HPA da API) |
| `addons/datadog-values.yaml` | Values do chart Helm do agente Datadog, aplicado pelo `datadog.yml` |
| `outputs.tf` | Valores consumidos pelos outros repositórios |
| `scripts/migrar-state-monorepo.sh` | Separação do state do antigo monorepo (uso único) |
| `docs/adr/` | Decisões de arquitetura |

## Outputs consumidos por outros repositórios

| Output | Consumidor |
|---|---|
| `vpc_id`, `private_subnet_ids`, `eks_cluster_security_group_id` | infra-database e severless, via `terraform_remote_state` |
| `ecr_repository_url`, `eks_cluster_name` | Workflows do TechChallenger-Api, sem secrets: os nomes (`techchallenger-fase1`) ficam fixos no `env` dos workflows e a URL do ECR é descoberta com `aws ecr describe-repositories`. Mudar `cluster_name` ou `ecr_repository_name` aqui exige mudar lá também |
| `api_node_port` | `nodePort` do Service em `k8s/aws/service.yaml` do TechChallenger-Api |
| `api_gateway_endpoint` | URL pública da API (documentação, Postman, testes de ponta a ponta) |
| `lambda_auth_function_name` | `LAMBDA_AUTH_FUNCTION_NAME` do `deploy.yml` do severless. O padrão `techchallenger-fase1-auth` já coincide |
| `rds_client_security_group_id` | infra-database, para liberar a porta do RDS a partir do SG da Lambda |

## Como usar

### 1. Backend remoto (uma única vez por conta AWS)

```bash
cd bootstrap
terraform init && terraform apply
```

### 2. Infraestrutura

Via GitHub Actions (recomendado): workflow **Terraform Apply - VPC / EKS / ECR / API Gateway** (`infra-apply.yml`). Ele roda `plan` + `apply`, instala o metrics-server no cluster e exibe o endpoint do gateway.

Localmente:

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
aws eks update-kubeconfig --name "$(terraform output -raw eks_cluster_name)" --region us-east-1
kubectl apply -f addons/metrics-server.yaml
```

### 3. Destruir

Primeiro destrua o **infra-database**. Depois rode o workflow **Terraform Destroy - VPC / EKS / ECR / API Gateway** (`infra-destroy.yml`), que exige usuário autorizado (`vars.MEU_USUARIO_GITHUB`), dupla confirmação e aprovação manual.

### Pipelines

| Workflow | Gatilho | O que faz |
|---|---|---|
| `terraform-ci.yml` | Pull request | `fmt -check` + `validate` (sem credenciais) |
| `infra-apply.yml` | Manual, com o tipo de instância dos nodes e o site do Datadog | `plan` → `apply` → metrics-server |
| `infra-destroy.yml` | Manual | trava do banco → `plan -destroy` → aprovação → `destroy` |
| `ssm-parameters.yml` | Manual, com os valores informados no disparo | Publica `/techchallenger/db/*`, `/techchallenger/jwt/secret`, `/techchallenger/email/*` e `/techchallenger/datadog/api-key` no SSM |
| `datadog.yml` | Manual, com o site da conta Datadog | Instala, atualiza ou remove o agente Datadog no cluster (Helm) |

Secrets do environment `aws-deploy`: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`. Variable: `MEU_USUARIO_GITHUB`.

No `ssm-parameters.yml`, campo em branco mantém o valor atual, então dá para trocar um parâmetro só. O `db_host` é o output `rds_address` do infra-database, sem a porta, e o `jwt_secret` precisa ter no mínimo 32 bytes. A API lê todos esses parâmetros no deploy, e os `email_*` são obrigatórios para ele passar. Rode esse workflow depois do `infra-apply.yml` do infra-database e, depois de recriar o RDS, informe o host de novo, porque ele pode mudar. Se a senha do banco mudar no secret `DB_PASSWORD` do infra-database, publique a nova aqui também. Valores já carregados pela Lambda ficam em cache até um novo cold start, e a API só os recebe no próximo deploy.

Os inputs de `workflow_dispatch` não têm a proteção de um secret: a pipeline mascara as senhas e o segredo do JWT no log, mas o GitHub guarda os inputs no evento da execução. Quem tiver acesso ao repositório com permissão de disparar workflows também pode gravar nesses parâmetros.

## Migração do state do monorepo

Até a separação em repositórios, todo o Terraform usava um único state (`techchallenger-fase1/terraform.tfstate`). O script `scripts/migrar-state-monorepo.sh` faz a separação **sem recriar recursos**:

1. baixa o state antigo (que continua no bucket, intacto, como backup);
2. gera dois states com `terraform state rm`: um sem os recursos do banco, outro só com eles;
3. faz `terraform state push` para `infra-kubernetes/terraform.tfstate` e `infra-database/terraform.tfstate`;
4. roda `plan` nos dois repositórios para conferência.

Se a infraestrutura estiver destruída (state vazio), o script só avisa e encerra: basta aplicar cada repositório na ordem. Depois da migração, **não rode mais os workflows de infra do monorepo**.

```bash
# com credenciais válidas do Learner Lab; o infra-database precisa estar em ../TechChallenger-infra-database
bash scripts/migrar-state-monorepo.sh
```

## Decisões de design

### Backend remoto do state (`backend.tf`, `bootstrap/`)

O bloco `backend` não aceita variáveis, por isso os valores (que vêm dos outputs de `bootstrap/`) estão fixos no arquivo. Cada repositório usa o mesmo bucket e a mesma tabela de lock, cada um com sua própria `key`.

`bootstrap/` é a única pasta sem backend remoto: ela cria o próprio bucket e a tabela, então o state dela é local. O bucket tem versionamento, criptografia SSE-AES256 e bloqueio de acesso público.

- **Nome com o ID da conta** (`techchallenger-fase1-terraform-state-<account_id>`): nomes de bucket são globais, e o nome de um bucket apagado num lab anterior pode ficar indisponível por horas.
- **Bucket criado pela CLI** (`terraform_data` + `aws s3api create-bucket`), e não por `aws_s3_bucket`: o provider lê a configuração de Object Lock a cada refresh, e a SCP do Learner Lab nega `s3:GetBucketObjectLockConfiguration`. Versionamento, criptografia e bloqueio de acesso público continuam no Terraform. O `destroy` do bootstrap não apaga o bucket, que guarda o state de todos os repositórios.

### VPC (`vpc.tf`)

Usa o módulo oficial `terraform-aws-modules/vpc/aws`. As tags `kubernetes.io/cluster/<nome>`, `kubernetes.io/role/elb` e `kubernetes.io/role/internal-elb` são exigidas pelo EKS para descobrir em quais subnets criar load balancers públicos e internos. As subnets privadas também abrigam o RDS e a Lambda.

### EKS (`eks.tf`)

- **`LabRole`**: o control plane e o node group reaproveitam a role existente na conta AWS Academy, já que não é possível criar IAM roles novas.
- **Recursos diretos em vez do módulo `terraform-aws-modules/eks/aws`**: o módulo (versões 19 a 21) declara um data source `aws_iam_session_context` incondicional. Ele chama `iam:GetRole` na role `voclabs`, que tem *deny* explícito no Learner Lab, e não há flag para desabilitá-lo.
- **Endpoints**: o público permite `kubectl` local e acesso pela pipeline; o privado deixa os nodes acessarem a API sem sair pela internet.
- **Node group**: `t3.micro`, de 1 a 3 nodes (desired 2), para caber nas cotas do Learner Lab (máx. 9 instâncias / 32 vCPUs por região). Não usa launch template customizado, então os nodes sobem com o SG primário do cluster, que é o SG liberado no RDS pelo infra-database.
- **`null_resource.cleanup_k8s_load_balancers`**: o Service `type: LoadBalancer` da API é aplicado por `kubectl` (repositório TechChallenger-Api) e cria um NLB fora do state do Terraform. Sem limpeza, o `destroy` falha com `DependencyViolation` ao apagar as subnets. Este recurso roda só no destroy: remove **todos** os Services `type=LoadBalancer` do cluster, para não depender do nome usado pela aplicação, e espera os NLBs sumirem da VPC. Os `triggers` foram mantidos iguais aos do monorepo para não forçar um *replace* (que dispararia o provisioner num cluster vivo).

### ECR (`ecr.tf`)

Scan na publicação e lifecycle mantendo as últimas 2 imagens. `force_delete = true` evita `RepositoryNotEmptyException` no destroy. Fica neste repositório, e não no da API, porque a API não tem Terraform próprio (ver ADR-001).

### API Gateway (`api-gateway.tf`, `nlb.tf`)

Detalhes e alternativas em [ADR-003](docs/adr/ADR-003-integracao-api-gateway-eks.md).

- **HTTP API** (API Gateway v2), e não REST API: mais barato, menor latência e com VPC Link para NLB; nenhum recurso exclusivo do REST API é necessário (comparação no [fluxo de autenticação](https://github.com/arthur-lucas-castro/TechChallenger-severless/blob/main/docs/auth-flow.md)).
- **Stage `$default` com `auto_deploy`**: a URL não tem prefixo de stage e toda mudança de rota é publicada no apply.
- **Integração privada**: `ANY /{proxy+}` → VPC Link → **NLB interno** → NodePort `30080` nos nodes. O NLB é criado pelo Terraform (e não pelo Kubernetes) para que o ARN do listener exista no plan; o ASG do node group é anexado ao target group, então nodes criados pelo scaling entram sozinhos. Não há AWS Load Balancer Controller porque ele exige uma IAM role própria, indisponível no Learner Lab.
- **Sem acesso público direto à API**: o Service da aplicação passa a ser `NodePort`; só o gateway alcança o cluster.
- **Observabilidade**: access logs em JSON no CloudWatch (`/aws/apigateway/<cluster>-gateway`) com latência do gateway e da integração, e métricas detalhadas por rota. O header `x-correlation-id` enviado à API é o `requestId` do gateway, o mesmo dos access logs.
- **Throttling** global por stage (`api_gateway_throttling_rate_limit` / `_burst_limit`). As rotas `POST /auth*` têm limites próprios mais baixos (`auth_throttling_rate_limit` / `_burst_limit`) contra enumeração de CPF e força bruta de senha. O limite soma todos os clientes da rota, então um ataque também pode bloquear logins legítimos.
- **Autenticação (próximo passo)**: o Lambda Authorizer em `/{proxy+}` será adicionado quando o código dele existir no severless (ADR-002). Até lá, as rotas protegidas dependem só do middleware JWT da API.

### Lambda de autenticação (`lambda.tf`)

- **Só infraestrutura**: runtime, memória, rede, variáveis e rotas ficam aqui. O código é publicado pelo `deploy.yml` do severless, e `ignore_changes` impede o Terraform de sobrescrevê-lo. O primeiro `apply` cria a função com um placeholder que responde `503`.
- **Rede**: roda nas subnets privadas e sai pelo NAT Gateway para ler o SSM. O SG libera só a porta do banco dentro da VPC e HTTPS para fora.
- **Acesso ao RDS**: o SG da função precisa estar liberado no SG do RDS, regra que pertence ao infra-database. Sem ela, a função responde `503`.
- **Segredos**: a função recebe só os nomes dos parâmetros SSM. Os valores são publicados pelo workflow `ssm-parameters.yml` deste repositório, então não passam pelo tfstate.
- **`LabRole`**: precisa de `ssm:GetParameters`. No Learner Lab não é possível criar uma role própria.
- **Runtime**: `nodejs20.x`, depreciado pela AWS desde 30/04/2026 e sem novos patches de segurança. A AWS bloqueia a criação de funções nele em 29/07/2027 e a atualização em 31/08/2027.
- **Destroy**: o SG pode levar dezenas de minutos para ser apagado, enquanto a AWS libera as ENIs da Lambda.
- **Datadog** ([ADR-004](docs/adr/ADR-004-observabilidade-datadog.md)): com `lambda_datadog_enabled = true` (padrão), a função recebe os layers `Datadog-Extension` (`datadog_extension_layer_version`) e `Datadog-Node20-x` (`datadog_node_layer_version`), publicados pela conta da Datadog. O handler passa a ser o wrapper `/opt/nodejs/node_modules/datadog-lambda-js/handler.handler`, que inicia o tracer e chama o `index.handler` indicado em `DD_LAMBDA_HANDLER`. A extensão lê a API key do SSM pelo ARN em `DD_API_KEY_SSM_ARN` e envia logs, traces e métricas direto ao Datadog, pela mesma saída HTTPS usada para o SSM. `DD_CAPTURE_LAMBDA_PAYLOAD=false` mantém CPF, senha e tokens fora dos traces. O site (`datadog_site`) vem do input do `infra-apply.yml` e precisa ser o mesmo do `datadog.yml`. Publique a key no SSM antes deste apply: sem ela a extensão não tem como enviar nada. Para tirar os layers (fim do trial, por exemplo), aplique com `lambda_datadog_enabled = false`.

### metrics-server (`addons/`)

É pré-requisito do HPA da API e não vem instalado no EKS. O manifesto oficial é vendorizado na `v0.9.0` (em vez de `latest`) para manter a reprodutibilidade, e o workflow de apply o instala logo após o `terraform apply`. Ele saiu do pipeline da aplicação por ser um componente do cluster ([ADR-001](docs/adr/ADR-001-localizacao-manifestos-kubernetes.md)).

### Datadog (`addons/datadog-values.yaml`, `datadog.yml`)

Agente de monitoramento do cluster, instalado pelo chart Helm `datadog/datadog` com versão fixa (`DATADOG_CHART_VERSION` no workflow). Como o metrics-server, é componente do cluster, então fica neste repositório ([ADR-001](docs/adr/ADR-001-localizacao-manifestos-kubernetes.md)). Coleta:

- **CPU, memória e estado** de nodes, pods, deployments e HPA (kubelet + kube-state-metrics);
- **logs** de todos os containers, menos `kube-system` e `datadog`;
- **traces (APM)** pelo hostPort 8126. O Cluster Agent injeta o tracer .NET só nos pods com o label `admission.datadoghq.com/enabled: "true"`, que fica no `deployment.yaml` do TechChallenger-Api;
- **métricas customizadas (DogStatsD)** pelo hostPort UDP 8125.

Ordem de uso:

1. Rode o `infra-apply.yml` com `node_instance_type=t3.small`. No `t3.micro` cada node aceita só 4 pods, e o agente não tem onde rodar. O workflow do Datadog confere isso e falha antes de instalar.
2. Publique a API key em `/techchallenger/datadog/api-key` pelo `ssm-parameters.yml` (campo `datadog_api_key`).
3. Rode o `datadog.yml` com `action=install` e o site da conta. O site aparece na URL do app, ex.: `us5.datadoghq.com`. O workflow valida a key nesse site antes de instalar.

A key nunca entra no tfstate nem no repositório: o workflow lê do SSM e cria o Secret `datadog-secret` no namespace `datadog`. Para encerrar a coleta, por exemplo no fim do trial, rode com `action=uninstall`. O `infra-destroy.yml` não precisa desse passo, porque o agente some junto com o cluster.

Sem IAM role própria no Learner Lab, a integração AWS nativa do Datadog (leitura do CloudWatch) não é usada. A Lambda é coberta pela extensão Datadog (seção anterior), e a latência das APIs vem do APM da API. Os access logs do API Gateway continuam só no CloudWatch. Detalhes e alternativas em [ADR-004](docs/adr/ADR-004-observabilidade-datadog.md).

### Variáveis

- `kubernetes_version = null`: o EKS usa a versão padrão do momento, o que evita erro com versão descontinuada.
- `node_instance_types` (default `t3.micro`) pode ser trocado para `t3.small` pelo input do workflow de apply.
- `node_disk_size` default 20GB: é o mínimo da AMI `AL2023_x86_64_STANDARD`.
