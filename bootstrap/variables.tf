variable "aws_region" {
  description = "Região AWS onde os recursos de backend (S3 + DynamoDB) serão criados."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto, usado como prefixo dos recursos de backend."
  type        = string
  default     = "techchallenger-fase1"
}

variable "environment" {
  description = "Ambiente/escopo do state (ex.: shared, dev, prod). Um bucket e uma tabela costumam ser compartilhados entre ambientes, usando prefixos de key distintos por ambiente."
  type        = string
  default     = "shared"
}
