# Dashboard, monitores e teste de uptime da oficina no Datadog (ADR-004). As métricas
# oficina.* vêm da API (TechChallenger-Api, docs/K8S.md) e da Lambda (TechChallenger-severless).

# Endpoint público do gateway, criado pela raiz deste repositório. try(): com a raiz
# destruída o state não tem o output, e o teste de uptime simplesmente não é criado.
data "terraform_remote_state" "plataforma" {
  backend = "s3"

  config = {
    bucket = "techchallenger-fase1-terraform-state-859733682813"
    key    = "infra-kubernetes/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  api_gateway_endpoint = trimsuffix(
    var.api_gateway_endpoint != "" ? var.api_gateway_endpoint : try(data.terraform_remote_state.plataforma.outputs.api_gateway_endpoint, ""),
    "/",
  )

  # O Datadog grava valores de tag em minúsculas.
  api_filter        = "service:${var.api_service},env:${var.env}"
  deployment_filter = "kube_deployment:${var.api_deployment}"
  lambda_filter     = "functionname:${lower(var.auth_function_name)}"

  tags = ["project:techchallenger", "env:${var.env}", "managed-by:terraform"]

  notify = var.alert_email == "" ? "" : "@${var.alert_email}"
}
