variable "datadog_api_key" {
  description = "API key do Datadog. O workflow observability.yml lê de /techchallenger/datadog/api-key no SSM."
  type        = string
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Application key do Datadog, exigida para criar dashboards e monitores. O workflow observability.yml lê do secret DATADOG_APP_KEY do environment aws-deploy."
  type        = string
  sensitive   = true
}

variable "datadog_site" {
  description = "Site da conta Datadog (ex.: datadoghq.com, us5.datadoghq.com). O mesmo do datadog.yml e do infra-apply.yml."
  type        = string
  default     = "datadoghq.com"
}

variable "alert_email" {
  description = "E-mail que recebe os alertas. Vazio: os monitores só aparecem no Datadog, sem notificação."
  type        = string
  default     = ""
}

variable "env" {
  description = "Tag env usada pela API (tags.datadoghq.com/env) e pela Lambda (DD_ENV)."
  type        = string
  default     = "prod"
}

variable "api_service" {
  description = "Service da API no Datadog (tags.datadoghq.com/service do deployment.yaml do TechChallenger-Api)."
  type        = string
  default     = "techchallenger-api"
}

variable "api_deployment" {
  description = "Nome do Deployment da API no Kubernetes."
  type        = string
  default     = "techchallenger-api"
}

variable "auth_function_name" {
  description = "Nome da Lambda de autenticação (output lambda_auth_function_name da raiz deste repositório)."
  type        = string
  default     = "techchallenger-fase1-auth"
}

variable "auth_service" {
  description = "Service da Lambda de autenticação no Datadog (DD_SERVICE em ../lambda.tf)."
  type        = string
  default     = "techchallenger-auth"
}

variable "api_gateway_endpoint" {
  description = "URL do API Gateway para o teste de uptime. Vazio: lê o output api_gateway_endpoint do state da raiz. Sem nenhum dos dois, o teste não é criado."
  type        = string
  default     = ""
}

variable "api_latency_p95_threshold_seconds" {
  description = "Latência p95 da API (s) que dispara o alerta."
  type        = number
  default     = 1
}

variable "api_error_rate_threshold" {
  description = "Fração de requisições com erro (0 a 1) que dispara o alerta."
  type        = number
  default     = 0.05
}
