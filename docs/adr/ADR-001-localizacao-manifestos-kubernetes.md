# ADR-001 — Localização dos manifestos Kubernetes

- **Status:** Aceito
- **Data:** 2026-10-22
- **Repositórios afetados:** `app-principal`, `infra-kubernetes`
- **Nomes reais dos repositórios:** `lambda-auth` = TechChallenger-severless · `app-principal` = TechChallenger-Api · `infra-kubernetes` = TechChallenger-infra-kubernetes · `infra-database` = TechChallenger-infra-database

## Contexto

O projeto da oficina mecânica foi dividido em quatro repositórios: `lambda-auth`, `infra-kubernetes`, `infra-database` e `app-principal`. Antes, um único repositório guardava o código da API .NET, o Terraform de VPC/EKS/node group/RDS/ECR, os manifestos Kubernetes (`/k8s`) e o pipeline de CI/CD.

O pipeline atual (`ci-cd.yml`) faz o seguinte a cada release (`release/X.Y.Z`):

1. compila e testa a aplicação;
2. gera a imagem Docker com a tag da versão e a envia ao ECR;
3. troca `IMAGE_PLACEHOLDER` no `deployment.yaml` pela imagem recém-publicada;
4. aplica com `kubectl apply` o ConfigMap, o Secret, o Deployment, o Service, o metrics-server e o HPA;
5. espera o rollout e abre o PR de merge para a branch principal.

O manifesto, portanto, é aplicado **a cada deploy da aplicação** e depende da **tag da imagem** gerada no mesmo pipeline.

Entre os manifestos atuais há dois tipos de recurso:

| Recurso | Escopo | Ciclo de vida |
|---|---|---|
| `deployment.yaml`, `service.yaml`, `hpa.yaml`, `configmap.yaml`, Secret da API | Aplicação | Muda a cada release |
| `metrics-server.yaml` | Cluster (usado por qualquer HPA) | Muda raramente, junto com o cluster |

## Alternativas consideradas

### Opção A — Manifestos em `app-principal`

**Prós**
- O deploy é atômico: código, imagem e manifesto saem do mesmo commit e da mesma release. A versão `1.0.6` sempre sobe com o manifesto da `1.0.6`.
- O pipeline continua simples, sem checkout de outro repositório, PAT entre repositórios ou `repository_dispatch`. É o fluxo que já funciona hoje.
- Uma mudança que precisa de nova variável de ambiente, probe ou limite de recurso vai em **um único PR**, junto com o código que depende dela.
- O rollback é previsível: rodar o pipeline da release anterior volta a imagem e o manifesto juntos.
- O `infra-kubernetes` não precisa saber nada sobre a aplicação e pode ser recriado de forma independente.

**Contras**
- O pipeline da aplicação precisa de credenciais com acesso ao cluster (`aws eks update-kubeconfig`). Ele já tem hoje.
- Existe o risco de recursos do cluster (metrics-server, ingress controller, namespaces compartilhados) acabarem no repositório da aplicação se não houver uma regra clara.
- O nome do cluster e a URL do ECR vêm de outro repositório (outputs do `infra-kubernetes`) e precisam ser cadastrados como secrets/variables do `app-principal`.

### Opção B — Manifestos em `infra-kubernetes`

**Prós**
- Tudo que roda no cluster fica em um só lugar, revisado por quem é dono da plataforma.
- Os manifestos podem ser aplicados pelo próprio Terraform (provider `kubernetes`/`helm`), com plan e state.

**Contras**
- Cada deploy da aplicação passa a depender de outro repositório. A tag da imagem precisa ir do `app-principal` ao `infra-kubernetes` (dispatch, PAT, commit automático), o que aumenta a superfície de falha.
- O versionamento fica dessincronizado: o código está em uma release e o manifesto em um commit de outro repositório. Rollback e rastreabilidade ficam mais difíceis.
- Uma variável de ambiente nova exige **dois PRs coordenados**, em dois repositórios.
- Mistura ciclos de vida diferentes: a infraestrutura muda raramente, a aplicação muda a cada release. O `terraform plan` do cluster passaria a rodar a cada deploy.
- Se aplicados via Terraform, surge drift com o que o próprio Kubernetes altera (por exemplo, o HPA ajustando `replicas`), e é preciso usar `ignore_changes`.

## Decisão

**Os manifestos da aplicação ficam em `app-principal/k8s/`.** O pipeline da aplicação continua aplicando esses manifestos a cada deploy.

**Os componentes do cluster ficam em `infra-kubernetes`.** O `metrics-server` sai do pipeline da aplicação e passa a ser instalado pelo `infra-kubernetes`, via Terraform (`helm_release`) ou por um passo `kubectl apply` no workflow de apply da infraestrutura.

Regra para casos futuros:

> Se o recurso só existe porque a API existe e muda junto com ela, fica em `app-principal`. Se ele serve o cluster como um todo ou outras cargas, fica em `infra-kubernetes`.

Estrutura resultante no `app-principal`:

```
k8s/
├── aws/        # EKS: configmap, deployment, service, hpa
└── local/      # Docker Desktop/minikube: banco, mailpit, deployment local
```

## Consequências

- O `ci-cd.yml` do `app-principal` mantém o fluxo atual, sem o passo do metrics-server.
- O `app-principal` precisa destes secrets/variables, vindos dos outputs do `infra-kubernetes` e do `infra-database`: `EKS_CLUSTER_NAME`, `ECR_REPOSITORY_URL`, `K8S_SECRET_ENV` (com o host do RDS) e as credenciais AWS.
- **Ordem de provisionamento:** `infra-kubernetes` → `infra-database` → `app-principal`. O primeiro deploy da aplicação falha se o cluster ainda não existir.
- **Acoplamento remanescente:** o `null_resource.cleanup_k8s_load_balancers` do `infra-kubernetes` remove o Service `techchallenger-api` pelo nome antes do destroy. Ele deve ser generalizado para remover todos os Services `type=LoadBalancer` do cluster, para que a infraestrutura não dependa do nome usado pela aplicação.
- Se o projeto passar a ter vários serviços ou ambientes, vale avaliar Kustomize (base + overlays) ou GitOps (Argo CD lendo `app-principal/k8s`). Isso não muda esta decisão: os manifestos continuam junto da aplicação.
