# TechChallenger-infra-kubernetes

Infraestrutura base da oficina mecânica na AWS, provisionada com **Terraform**: **VPC**, cluster **EKS**, node group, repositório **ECR** e componentes do cluster (**metrics-server**).

O projeto roda em uma conta **AWS Academy Learner Lab**. Isso impõe restrições que aparecem em várias decisões abaixo: não é possível criar IAM roles novas, as cotas de EC2/vCPU são baixas e as credenciais são temporárias.

## Repositórios do projeto

| Repositório | Responsabilidade |
|---|---|
| **TechChallenger-infra-kubernetes** (este) | VPC, EKS, node group, ECR, metrics-server, bucket do state |
| [TechChallenger-infra-database](https://github.com/arthur-lucas-castro/TechChallenger-infra-database) | RDS PostgreSQL |
| [TechChallenger-severless](https://github.com/arthur-lucas-castro/TechChallenger-severless) | Lambda de autenticação por CPF + API Gateway |
| [TechChallenger-Api](https://github.com/arthur-lucas-castro/TechChallenger-Api) | API da oficina e manifestos Kubernetes da aplicação |

**Ordem de provisionamento:** **1. infra-kubernetes** → 2. infra-database → 3. severless / Api.
**Ordem de destruição:** a inversa. O workflow de destroy deste repo bloqueia a execução enquanto o state do infra-database ainda tiver recursos.

## Arquitetura

```
                        AWS (us-east-1)
┌──────────────────────────────────────────────────────────────────┐
│  VPC (10.0.0.0/16)                                                 │
│                                                                      │
│  ┌─── Subnets públicas ───┐        ┌─── Subnets privadas ───┐      │
│  │  Internet Gateway       │        │                          │      │
│  │  NAT Gateway             │◄──────┤  EKS Node Group          │      │
│  │  Network Load Balancer   │       │  (t3.micro, 1-3 nodes)   │      │
│  │       ▲                  │        │                          │      │
│  └───────┼──────────────────┘        │  RDS ◄── infra-database  │      │
│          │                            │  Lambda ◄── severless    │      │
│  Internet │                            └──────────────────────────┘      │
└──────────┼──────────────────────────────────────────────────────────┘
           │
     Usuário / kubectl / pipeline CI-CD

  ECR (imagem Docker da API) ── consumido pelo EKS
```

## Estrutura

| Caminho | Conteúdo |
|---|---|
| `bootstrap/` | Bucket S3 + tabela DynamoDB do state remoto, compartilhados por todos os repositórios (aplicado uma única vez) |
| `backend.tf` | Backend S3, `key = infra-kubernetes/terraform.tfstate` |
| `vpc.tf` | VPC, subnets, IGW, NAT |
| `eks.tf` | Cluster, node group, cleanup de load balancers no destroy |
| `ecr.tf` | Repositório da imagem da API |
| `addons/metrics-server.yaml` | metrics-server v0.9.0 (pré-requisito do HPA da API) |
| `outputs.tf` | Valores consumidos pelos outros repositórios |
| `scripts/migrar-state-monorepo.sh` | Separação do state do antigo monorepo (uso único) |
| `docs/adr/` | Decisões de arquitetura |

## Outputs consumidos por outros repositórios

| Output | Consumidor |
|---|---|
| `vpc_id`, `private_subnet_ids`, `eks_cluster_security_group_id` | infra-database e severless, via `terraform_remote_state` |
| `ecr_repository_url` | Secret `ECR_REPOSITORY_URL` do TechChallenger-Api |
| `eks_cluster_name` | Secret `EKS_CLUSTER_NAME` do TechChallenger-Api |

## Como usar

### 1. Backend remoto (uma única vez por conta AWS)

```bash
cd bootstrap
terraform init && terraform apply
```

### 2. Infraestrutura

Via GitHub Actions (recomendado): workflow **Terraform Apply - VPC / EKS / ECR** (`infra-apply.yml`). Ele roda `plan` + `apply` e depois instala o metrics-server no cluster.

Localmente:

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
aws eks update-kubeconfig --name "$(terraform output -raw eks_cluster_name)" --region us-east-1
kubectl apply -f addons/metrics-server.yaml
```

### 3. Destruir

Primeiro destrua o **infra-database**. Depois rode o workflow **Terraform Destroy - VPC / EKS / ECR** (`infra-destroy.yml`), que exige usuário autorizado (`vars.MEU_USUARIO_GITHUB`), dupla confirmação e aprovação manual.

### Pipelines

| Workflow | Gatilho | O que faz |
|---|---|---|
| `terraform-ci.yml` | Pull request | `fmt -check` + `validate` (sem credenciais) |
| `infra-apply.yml` | Manual | `plan` → `apply` → metrics-server |
| `infra-destroy.yml` | Manual | trava do banco → `plan -destroy` → aprovação → `destroy` |

Secrets do environment `aws-deploy`: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`. Variable: `MEU_USUARIO_GITHUB`.

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

`bootstrap/` é a única pasta sem backend remoto: ela cria o próprio bucket e a tabela, então o state dela é local. O bucket tem `prevent_destroy = true`, versionamento, criptografia SSE-AES256 e bloqueio de acesso público.

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

### metrics-server (`addons/`)

É pré-requisito do HPA da API e não vem instalado no EKS. O manifesto oficial é vendorizado na `v0.9.0` (em vez de `latest`) para manter a reprodutibilidade, e o workflow de apply o instala logo após o `terraform apply`. Ele saiu do pipeline da aplicação por ser um componente do cluster ([ADR-001](docs/adr/ADR-001-localizacao-manifestos-kubernetes.md)).

### Variáveis

- `kubernetes_version = null`: o EKS usa a versão padrão do momento, o que evita erro com versão descontinuada.
- `node_instance_types` (default `t3.micro`) pode ser trocado para `t3.small` pelo input do workflow de apply.
- `node_disk_size` default 20GB: é o mínimo da AMI `AL2023_x86_64_STANDARD`.
