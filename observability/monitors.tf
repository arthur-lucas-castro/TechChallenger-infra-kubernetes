# Alertas exigidos pelo Tech Challenge: falhas no processamento de ordens de serviço,
# latência e erros da API, consumo de recursos do Kubernetes e falhas nas integrações.
# O healthcheck/uptime fica em synthetics.tf.

# ── Ordens de serviço ────────────────────────────────────────────────────────

resource "datadog_monitor" "os_falha_processamento" {
  name     = "[Oficina] Falha no processamento de ordens de serviço"
  type     = "query alert"
  priority = "1"

  # tipo:erro_interno = exceção inesperada ou banco indisponível (ExceptionMiddleware da API).
  # Regras de negócio violadas (dominio, validacao) são respostas esperadas e não alertam.
  query = "sum(last_5m):sum:oficina.api.falha{tipo:erro_interno AND (controller:ordemservico OR controller:statusordemservico)}.as_count() > 0"

  monitor_thresholds {
    critical = 0
  }

  message = <<-EOT
    {{#is_alert}}
    {{value}} requisição(ões) de ordem de serviço falharam com erro interno nos últimos 5 minutos.
    Veja os logs com `service:${var.api_service} status:error` e o trace pelo CorrelationId.
    Banco indisponível também cai aqui: confira o RDS e as conexões.
    {{/is_alert}}
    {{#is_recovery}}Processamento de ordens de serviço normalizado.{{/is_recovery}}
    ${local.notify}
  EOT

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.tags, ["area:ordem-servico"])
}

# ── API ──────────────────────────────────────────────────────────────────────

resource "datadog_monitor" "api_taxa_erro" {
  name     = "[Oficina] Taxa de erro da API acima do limite"
  type     = "query alert"
  priority = "2"

  query = "sum(last_10m):sum:trace.aspnet_core.request.errors{${local.api_filter}}.as_count() / sum:trace.aspnet_core.request.hits{${local.api_filter}}.as_count() > ${var.api_error_rate_threshold}"

  monitor_thresholds {
    critical = var.api_error_rate_threshold
    warning  = var.api_error_rate_threshold / 2
  }

  message = <<-EOT
    {{#is_alert}}Taxa de erro da API em {{value}} (limite ${var.api_error_rate_threshold}) nos últimos 10 minutos. Veja APM > ${var.api_service} > Errors.{{/is_alert}}
    {{#is_warning}}Taxa de erro da API subindo: {{value}}.{{/is_warning}}
    {{#is_recovery}}Taxa de erro da API normalizada.{{/is_recovery}}
    ${local.notify}
  EOT

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.tags, ["area:api"])
}

resource "datadog_monitor" "api_latencia" {
  name     = "[Oficina] Latência p95 da API alta"
  type     = "query alert"
  priority = "2"

  query = "percentile(last_10m):p95:trace.aspnet_core.request{${local.api_filter}} > ${var.api_latency_p95_threshold_seconds}"

  monitor_thresholds {
    critical = var.api_latency_p95_threshold_seconds
    warning  = var.api_latency_p95_threshold_seconds / 2
  }

  message = <<-EOT
    {{#is_alert}}Latência p95 da API em {{value}} s (limite ${var.api_latency_p95_threshold_seconds} s). Veja as rotas mais lentas em APM > ${var.api_service} > Resources.{{/is_alert}}
    {{#is_warning}}Latência p95 da API subindo: {{value}} s.{{/is_warning}}
    {{#is_recovery}}Latência da API normalizada.{{/is_recovery}}
    ${local.notify}
  EOT

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.tags, ["area:api"])
}

# ── Integrações ──────────────────────────────────────────────────────────────

resource "datadog_monitor" "integracao_falha" {
  name     = "[Oficina] Falha em integração: {{integracao.name}}"
  type     = "query alert"
  priority = "2"

  # Distribution: enviada pela API (smtp, postgres) e pela Lambda (lambda_auth).
  query = "sum(last_10m):count:oficina.integracao.falha{*} by {integracao} > 0"

  monitor_thresholds {
    critical = 0
  }

  message = <<-EOT
    {{#is_alert}}
    {{value}} falha(s) na integração {{integracao.name}} nos últimos 10 minutos.
    smtp: notificação de status da OS não enviada. postgres: consulta ao banco falhou.
    lambda_auth: autenticação respondeu 500/503 (banco ou SSM fora do ar).
    {{/is_alert}}
    {{#is_recovery}}Integração {{integracao.name}} normalizada.{{/is_recovery}}
    ${local.notify}
  EOT

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.tags, ["area:integracoes"])
}

resource "datadog_monitor" "lambda_auth_erros" {
  name     = "[Oficina] Erros na Lambda de autenticação"
  type     = "query alert"
  priority = "2"

  # Erros de execução (exceção não tratada, timeout, falta de memória). Recusas como
  # CPF inválido são respostas 4xx normais e não contam.
  query = "sum(last_10m):sum:aws.lambda.enhanced.errors{${local.lambda_filter}}.as_count() > 0"

  monitor_thresholds {
    critical = 0
  }

  message = <<-EOT
    {{#is_alert}}A Lambda ${var.auth_function_name} teve {{value}} erro(s) de execução nos últimos 10 minutos. Veja Serverless > ${var.auth_function_name}.{{/is_alert}}
    {{#is_recovery}}Lambda de autenticação normalizada.{{/is_recovery}}
    ${local.notify}
  EOT

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.tags, ["area:autenticacao"])
}

# ── Kubernetes ───────────────────────────────────────────────────────────────

resource "datadog_monitor" "k8s_sem_replicas" {
  name     = "[Oficina] API sem réplicas disponíveis no EKS"
  type     = "query alert"
  priority = "1"

  query = "max(last_5m):sum:kubernetes_state.deployment.replicas_available{${local.deployment_filter}} < 1"

  monitor_thresholds {
    critical = 1
  }

  message = <<-EOT
    {{#is_alert}}O Deployment ${var.api_deployment} está sem réplicas disponíveis. Veja `kubectl get pods -l app=${var.api_deployment}` e os eventos do pod.{{/is_alert}}
    {{#is_recovery}}Réplicas da API disponíveis novamente.{{/is_recovery}}
    ${local.notify}
  EOT

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.tags, ["area:kubernetes"])
}

resource "datadog_monitor" "k8s_restarts" {
  name     = "[Oficina] Pods da API reiniciando"
  type     = "query alert"
  priority = "3"

  query = "change(sum(last_10m),last_10m):sum:kubernetes.containers.restarts{${local.deployment_filter}} > 0"

  monitor_thresholds {
    critical = 0
  }

  message = <<-EOT
    {{#is_alert}}Containers da API reiniciaram {{value}} vez(es) em 10 minutos (OOMKilled, probe falhando ou CrashLoopBackOff).{{/is_alert}}
    {{#is_recovery}}Sem novos restarts na API.{{/is_recovery}}
    ${local.notify}
  EOT

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.tags, ["area:kubernetes"])
}

resource "datadog_monitor" "k8s_memoria" {
  name     = "[Oficina] Memória dos pods da API perto do limite"
  type     = "query alert"
  priority = "3"

  query = "avg(last_10m):avg:kubernetes.memory.usage{${local.deployment_filter}} by {pod_name} / avg:kubernetes.memory.limits{${local.deployment_filter}} by {pod_name} > 0.8"

  monitor_thresholds {
    critical = 0.8
    warning  = 0.7
  }

  message = <<-EOT
    {{#is_alert}}O pod {{pod_name.name}} usa {{value}} do limite de memória. Acima de 100% o container é OOMKilled.{{/is_alert}}
    {{#is_warning}}O pod {{pod_name.name}} usa {{value}} do limite de memória.{{/is_warning}}
    {{#is_recovery}}Memória do pod {{pod_name.name}} normalizada.{{/is_recovery}}
    ${local.notify}
  EOT

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.tags, ["area:kubernetes"])
}

resource "datadog_monitor" "k8s_cpu" {
  name     = "[Oficina] CPU dos pods da API perto do limite"
  type     = "query alert"
  priority = "3"

  # kubernetes.cpu.usage.total é em nanocores; kubernetes.cpu.limits, em cores.
  query = "avg(last_10m):avg:kubernetes.cpu.usage.total{${local.deployment_filter}} by {pod_name} / (avg:kubernetes.cpu.limits{${local.deployment_filter}} by {pod_name} * 1000000000) > 0.8"

  monitor_thresholds {
    critical = 0.8
    warning  = 0.7
  }

  message = <<-EOT
    {{#is_alert}}O pod {{pod_name.name}} usa {{value}} do limite de CPU e está sendo estrangulado. O HPA deveria escalar; confira as réplicas.{{/is_alert}}
    {{#is_warning}}O pod {{pod_name.name}} usa {{value}} do limite de CPU.{{/is_warning}}
    {{#is_recovery}}CPU do pod {{pod_name.name}} normalizada.{{/is_recovery}}
    ${local.notify}
  EOT

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.tags, ["area:kubernetes"])
}
