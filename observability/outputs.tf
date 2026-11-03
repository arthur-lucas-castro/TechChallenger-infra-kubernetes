output "dashboard_url" {
  description = "Caminho do dashboard \"Oficina — Operação\" no Datadog (prefixe com https://app.<site>)."
  value       = datadog_dashboard_json.oficina.url
}

output "monitor_ids" {
  description = "IDs dos monitores criados."
  value = {
    os_falha_processamento = datadog_monitor.os_falha_processamento.id
    api_taxa_erro          = datadog_monitor.api_taxa_erro.id
    api_latencia           = datadog_monitor.api_latencia.id
    integracao_falha       = datadog_monitor.integracao_falha.id
    lambda_auth_erros      = datadog_monitor.lambda_auth_erros.id
    k8s_sem_replicas       = datadog_monitor.k8s_sem_replicas.id
    k8s_restarts           = datadog_monitor.k8s_restarts.id
    k8s_memoria            = datadog_monitor.k8s_memoria.id
    k8s_cpu                = datadog_monitor.k8s_cpu.id
  }
}

output "uptime_test_url" {
  description = "URL verificada pelo teste de uptime. Vazio quando o endpoint do API Gateway não foi encontrado."
  value       = local.api_gateway_endpoint == "" ? "" : "${local.api_gateway_endpoint}/health"
}
