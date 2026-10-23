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
