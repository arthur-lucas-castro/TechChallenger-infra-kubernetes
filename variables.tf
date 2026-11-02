variable "cluster_name" {
  description = "Nome do cluster EKS, usado para nomear e taggear os recursos da VPC."
  type        = string
  default     = "techchallenger-fase1"
}

variable "environment" {
  description = "Nome do ambiente (ex: dev, hml, prod), usado em tags de recursos."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs onde as subnets públicas e privadas serão criadas (uma por subnet, na mesma ordem)."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks das subnets públicas (para o load balancer), uma por AZ."
  type        = list(string)
  default     = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks das subnets privadas (para os nodes do EKS e o RDS), uma por AZ."
  type        = list(string)
  default     = ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20"]
}

variable "single_nat_gateway" {
  description = "Se true, cria um único NAT Gateway compartilhado entre as AZs (mais barato); se false, cria um NAT Gateway por AZ (mais resiliente)."
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes do cluster EKS. Deixe null para o EKS usar a versão padrão disponível no momento da criação (evita fixar uma versão que a AWS pode parar de oferecer para clusters novos com o tempo). Para fixar uma versão específica, rode \"aws eks describe-addon-versions --query 'addons[0].addonVersions[0].compatibilities[].clusterVersion'\" ou veja a doc da AWS para as versões atualmente suportadas."
  type        = string
  default     = null
}

variable "node_instance_types" {
  description = "Tipos de instância EC2 usados pelo node group padrão do EKS. Default t3.micro (2 vCPUs) por conta das cotas do AWS Academy Learner Lab (máx. 9 instâncias / 32 vCPUs por região)."
  type        = list(string)
  default     = ["t3.micro"]
}

variable "node_disk_size" {
  description = "Tamanho do disco (GB) dos nodes do EKS. Default 20GB: é o mínimo exigido pela AMI AL2023_x86_64_STANDARD usada pelos managed node groups do EKS, e ainda fica bem abaixo do limite de 100GB por volume EBS no AWS Academy Learner Lab."
  type        = number
  default     = 20
}

variable "ecr_repository_name" {
  description = "Nome do repositório ECR usado para guardar a imagem Docker da aplicação."
  type        = string
  default     = "techchallenger-fase1"
}

variable "node_group_min_size" {
  description = "Quantidade mínima de nodes no node group padrão."
  type        = number
  default     = 1
}

variable "node_group_max_size" {
  description = "Quantidade máxima de nodes no node group padrão."
  type        = number
  default     = 3
}

variable "node_group_desired_size" {
  description = "Quantidade desejada de nodes no node group padrão."
  type        = number
  default     = 2
}

variable "api_node_port" {
  description = "NodePort fixo do Service da API no EKS (repositório TechChallenger-Api). O target group do NLB interno encaminha para essa porta nos nodes. Precisa estar na faixa 30000-32767 e ser igual ao nodePort declarado no service.yaml da aplicação."
  type        = number
  default     = 30080

  validation {
    condition     = var.api_node_port >= 30000 && var.api_node_port <= 32767
    error_message = "api_node_port precisa estar na faixa de NodePort do Kubernetes (30000-32767)."
  }
}

variable "api_listener_port" {
  description = "Porta do listener do NLB interno da API, usada pela integração do API Gateway via VPC Link."
  type        = number
  default     = 80
}

variable "api_health_check_path" {
  description = "Caminho HTTP do health check do target group do NLB (mesmo endpoint das probes do Deployment da API)."
  type        = string
  default     = "/health"
}

variable "api_gateway_throttling_rate_limit" {
  description = "Limite de requisições por segundo (steady-state) aplicado a todas as rotas do API Gateway."
  type        = number
  default     = 50
}

variable "api_gateway_throttling_burst_limit" {
  description = "Limite de burst de requisições aplicado a todas as rotas do API Gateway."
  type        = number
  default     = 100
}

variable "api_gateway_log_retention_days" {
  description = "Retenção (dias) dos access logs do API Gateway no CloudWatch."
  type        = number
  default     = 7
}

variable "auth_throttling_rate_limit" {
  description = "Limite de requisições por segundo de cada rota POST /auth*, somando todos os clientes."
  type        = number
  default     = 5
}

variable "auth_throttling_burst_limit" {
  description = "Limite de burst de cada rota POST /auth*."
  type        = number
  default     = 10
}

variable "lambda_runtime" {
  description = "Runtime da Lambda de autenticação. O nodejs20.x está depreciado desde abril de 2026, sem novos patches de segurança; a AWS bloqueia a criação de funções nele em 29/07/2027. Antes de trocar, altere o target do esbuild no TechChallenger-severless."
  type        = string
  default     = "nodejs20.x"
}

variable "lambda_architecture" {
  description = "Arquitetura da Lambda de autenticação. O pacote não tem módulos nativos, então funciona em x86_64 e arm64."
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.lambda_architecture)
    error_message = "lambda_architecture precisa ser x86_64 ou arm64."
  }
}

variable "lambda_memory_size" {
  description = "Memória (MB) da Lambda de autenticação. A CPU cresce com a memória, e o bcrypt do POST /auth/login depende dela."
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Timeout (s) da Lambda de autenticação. Precisa ser menor que os 30 s de integração do API Gateway."
  type        = number
  default     = 10
}

variable "lambda_reserved_concurrency" {
  description = "Concorrência reservada da Lambda de autenticação, que limita as conexões abertas no RDS. -1 não reserva: contas com limite baixo, como a do Learner Lab, podem recusar qualquer reserva."
  type        = number
  default     = -1
}

variable "lambda_log_retention_days" {
  description = "Retenção (dias) dos logs da Lambda de autenticação no CloudWatch."
  type        = number
  default     = 7
}

variable "db_port" {
  description = "Porta do RDS PostgreSQL. Precisa ser igual à variável db_port do TechChallenger-infra-database."
  type        = number
  default     = 5432
}

variable "ssm_jwt_secret_param" {
  description = "Nome do parâmetro SSM com o segredo do JWT, publicado pelo workflow ssm-parameters.yml deste repositório."
  type        = string
  default     = "/techchallenger/jwt/secret"
}

variable "ssm_db_param_prefix" {
  description = "Prefixo dos parâmetros SSM de conexão com o banco, publicados pelo workflow ssm-parameters.yml deste repositório."
  type        = string
  default     = "/techchallenger/db"
}
