# Dashboard pedido pelo Tech Challenge: volume diário de ordens de serviço, tempo médio por
# status (Diagnóstico, Execução, Finalização), erros nas integrações, latência da API,
# consumo do Kubernetes, healthcheck e logs.

locals {
  # Status do enunciado -> valor da tag status de oficina.os.tempo_no_status (minúsculas no Datadog).
  status_os = {
    "Diagnóstico" = "emdiagnostico"
    "Execução"    = "emexecucao"
    "Finalização" = "finalizada"
  }

  widgets_os = [
    {
      definition = {
        type             = "note"
        content          = "**Ordens de serviço.** Volume pela métrica `oficina.os.abertas` (distribution, um ponto por OS aberta). Tempo por status pela `oficina.os.tempo_no_status`, registrada quando a OS sai do status. Finalização = da finalização até a entrega do veículo."
        background_color = "white"
        font_size        = "14"
        text_align       = "left"
        show_tick        = false
        tick_pos         = "50%"
        tick_edge        = "left"
      }
    },
    {
      definition = {
        type      = "query_value"
        title     = "OS abertas no período"
        precision = 0
        autoscale = true
        requests = [{
          response_format = "scalar"
          queries         = [{ data_source = "metrics", name = "q1", query = "count:oficina.os.abertas{*}", aggregator = "sum" }]
          formulas        = [{ formula = "q1" }]
        }]
      }
    },
    {
      definition = {
        type        = "timeseries"
        title       = "Volume diário de ordens de serviço"
        show_legend = false
        requests = [{
          response_format = "timeseries"
          display_type    = "bars"
          queries         = [{ data_source = "metrics", name = "q1", query = "count:oficina.os.abertas{*}.rollup(sum, 86400)" }]
          formulas        = [{ formula = "q1", alias = "OS abertas por dia" }]
        }]
      }
    },
    {
      definition = {
        type  = "toplist"
        title = "Tempo médio por status (minutos)"
        requests = [{
          response_format = "scalar"
          queries = [for nome, tag in local.status_os : {
            data_source = "metrics"
            name        = tag
            query       = "avg:oficina.os.tempo_no_status{status:${tag}}"
            aggregator  = "avg"
          }]
          formulas = [for nome, tag in local.status_os : { formula = "${tag} / 60", alias = nome }]
        }]
      }
    },
    {
      definition = {
        type          = "timeseries"
        title         = "Tempo médio por status ao longo do tempo (minutos)"
        show_legend   = true
        legend_layout = "horizontal"
        requests = [{
          response_format = "timeseries"
          display_type    = "line"
          queries = [for nome, tag in local.status_os : {
            data_source = "metrics"
            name        = tag
            query       = "avg:oficina.os.tempo_no_status{status:${tag}}"
          }]
          formulas = [for nome, tag in local.status_os : { formula = "${tag} / 60", alias = nome }]
        }]
      }
    },
    {
      definition = {
        type      = "query_value"
        title     = "Falhas no processamento de OS (erro interno)"
        precision = 0
        autoscale = true
        requests = [{
          response_format = "scalar"
          queries = [{
            data_source = "metrics"
            name        = "q1"
            query       = "sum:oficina.api.falha{tipo:erro_interno AND (controller:ordemservico OR controller:statusordemservico)}.as_count()"
            aggregator  = "sum"
          }]
          formulas = [{ formula = "q1" }]
          conditional_formats = [
            { comparator = ">", value = 0, palette = "white_on_red" },
            { comparator = "<=", value = 0, palette = "white_on_green" },
          ]
        }]
      }
    },
  ]

  widgets_api = [
    {
      definition = {
        type          = "timeseries"
        title         = "Latência da API (s)"
        show_legend   = true
        legend_layout = "horizontal"
        requests = [{
          response_format = "timeseries"
          display_type    = "line"
          queries         = [for p in ["p50", "p95", "p99"] : { data_source = "metrics", name = p, query = "${p}:trace.aspnet_core.request{${local.api_filter}}" }]
          formulas        = [for p in ["p50", "p95", "p99"] : { formula = p, alias = p }]
        }]
      }
    },
    {
      definition = {
        type          = "timeseries"
        title         = "Requisições e erros da API"
        show_legend   = true
        legend_layout = "horizontal"
        requests = [{
          response_format = "timeseries"
          display_type    = "bars"
          queries = [
            { data_source = "metrics", name = "hits", query = "sum:trace.aspnet_core.request.hits{${local.api_filter}}.as_count()" },
            { data_source = "metrics", name = "errors", query = "sum:trace.aspnet_core.request.errors{${local.api_filter}}.as_count()" },
          ]
          formulas = [{ formula = "hits", alias = "requisições" }, { formula = "errors", alias = "erros" }]
        }]
      }
    },
    {
      definition = {
        type  = "toplist"
        title = "Rotas mais lentas (p95, s)"
        requests = [{
          response_format = "scalar"
          queries         = [{ data_source = "metrics", name = "q1", query = "p95:trace.aspnet_core.request{${local.api_filter}} by {resource_name}", aggregator = "avg" }]
          formulas        = [{ formula = "q1", limit = { count = 10, order = "desc" } }]
        }]
      }
    },
    {
      definition = {
        type  = "toplist"
        title = "Falhas da API por controller e tipo"
        requests = [{
          response_format = "scalar"
          queries         = [{ data_source = "metrics", name = "q1", query = "sum:oficina.api.falha{*} by {controller,tipo}.as_count()", aggregator = "sum" }]
          formulas        = [{ formula = "q1", limit = { count = 10, order = "desc" } }]
        }]
      }
    },
  ]

  widgets_integracoes = [
    {
      definition = {
        type          = "timeseries"
        title         = "Falhas nas integrações"
        show_legend   = true
        legend_layout = "horizontal"
        requests = [{
          response_format = "timeseries"
          display_type    = "bars"
          queries         = [{ data_source = "metrics", name = "q1", query = "count:oficina.integracao.falha{*} by {integracao}" }]
          formulas        = [{ formula = "q1" }]
        }]
      }
    },
    {
      definition = {
        type        = "timeseries"
        title       = "Retentativas de envio de e-mail (SMTP)"
        show_legend = false
        requests = [{
          response_format = "timeseries"
          display_type    = "bars"
          queries         = [{ data_source = "metrics", name = "q1", query = "sum:oficina.integracao.retentativa{*} by {integracao}.as_count()" }]
          formulas        = [{ formula = "q1" }]
        }]
      }
    },
    {
      definition = {
        type          = "timeseries"
        title         = "Lambda de autenticação: invocações e erros"
        show_legend   = true
        legend_layout = "horizontal"
        requests = [{
          response_format = "timeseries"
          display_type    = "bars"
          queries = [
            { data_source = "metrics", name = "inv", query = "sum:aws.lambda.enhanced.invocations{${local.lambda_filter}}.as_count()" },
            { data_source = "metrics", name = "err", query = "sum:aws.lambda.enhanced.errors{${local.lambda_filter}}.as_count()" },
          ]
          formulas = [{ formula = "inv", alias = "invocações" }, { formula = "err", alias = "erros" }]
        }]
      }
    },
    {
      definition = {
        type          = "timeseries"
        title         = "Lambda de autenticação: duração (ms)"
        show_legend   = true
        legend_layout = "horizontal"
        requests = [{
          response_format = "timeseries"
          display_type    = "line"
          queries = [
            # Percentis não vêm habilitados para esta distribution: média e máxima.
            { data_source = "metrics", name = "media", query = "avg:aws.lambda.enhanced.duration{${local.lambda_filter}}" },
            { data_source = "metrics", name = "maxima", query = "max:aws.lambda.enhanced.duration{${local.lambda_filter}}" },
            { data_source = "metrics", name = "init", query = "avg:aws.lambda.enhanced.init_duration{${local.lambda_filter}}" },
          ]
          # As métricas enhanced vêm em segundos.
          formulas = [{ formula = "media * 1000", alias = "média" }, { formula = "maxima * 1000", alias = "máxima" }, { formula = "init * 1000", alias = "cold start" }]
        }]
      }
    },
  ]

  widgets_k8s = [
    {
      definition = {
        type          = "timeseries"
        title         = "CPU por pod da API (cores)"
        show_legend   = true
        legend_layout = "horizontal"
        requests = [{
          response_format = "timeseries"
          display_type    = "line"
          queries         = [{ data_source = "metrics", name = "q1", query = "avg:kubernetes.cpu.usage.total{${local.deployment_filter}} by {pod_name}" }]
          formulas        = [{ formula = "q1 / 1000000000" }]
        }]
      }
    },
    {
      definition = {
        type          = "timeseries"
        title         = "Memória por pod da API (MiB)"
        show_legend   = true
        legend_layout = "horizontal"
        requests = [{
          response_format = "timeseries"
          display_type    = "line"
          queries         = [{ data_source = "metrics", name = "q1", query = "avg:kubernetes.memory.usage{${local.deployment_filter}} by {pod_name}" }]
          formulas        = [{ formula = "q1 / 1048576" }]
        }]
      }
    },
    {
      definition = {
        type          = "timeseries"
        title         = "Réplicas da API (HPA)"
        show_legend   = true
        legend_layout = "horizontal"
        requests = [{
          response_format = "timeseries"
          display_type    = "line"
          queries = [
            { data_source = "metrics", name = "disp", query = "sum:kubernetes_state.deployment.replicas_available{${local.deployment_filter}}" },
            { data_source = "metrics", name = "desej", query = "sum:kubernetes_state.deployment.replicas_desired{${local.deployment_filter}}" },
          ]
          formulas = [{ formula = "disp", alias = "disponíveis" }, { formula = "desej", alias = "desejadas" }]
        }]
      }
    },
    {
      definition = {
        type      = "query_value"
        title     = "Restarts de containers da API"
        precision = 0
        autoscale = true
        requests = [{
          response_format = "scalar"
          queries         = [{ data_source = "metrics", name = "q1", query = "sum:kubernetes.containers.restarts{${local.deployment_filter}}", aggregator = "max" }]
          formulas        = [{ formula = "q1" }]
        }]
      }
    },
  ]

  widgets_saude = [
    {
      definition = {
        type                = "manage_status"
        title               = "Alertas e uptime"
        summary_type        = "monitors"
        display_format      = "countsAndList"
        color_preference    = "text"
        hide_zero_counts    = true
        show_last_triggered = true
        query               = "tag:\"project:techchallenger\""
        sort                = "status,asc"
      }
    },
    {
      definition = {
        type                = "log_stream"
        title               = "Logs de erro (API e autenticação)"
        indexes             = []
        query               = "service:(${var.api_service} OR ${var.auth_service}) status:error"
        columns             = ["service", "@CorrelationId", "@correlationId"]
        show_date_column    = true
        show_message_column = true
        message_display     = "expanded-md"
        sort                = { column = "time", order = "desc" }
      }
    },
  ]

  grupos = [
    { titulo = "Ordens de serviço", widgets = local.widgets_os },
    { titulo = "API: latência e erros", widgets = local.widgets_api },
    { titulo = "Integrações: SMTP, banco e Lambda de autenticação", widgets = local.widgets_integracoes },
    { titulo = "Kubernetes", widgets = local.widgets_k8s },
    { titulo = "Saúde, alertas e logs", widgets = local.widgets_saude },
  ]
}

resource "datadog_dashboard_json" "oficina" {
  dashboard = jsonencode({
    title       = "Oficina — Operação"
    description = "Ordens de serviço, API, integrações e Kubernetes do TechChallenger. Gerenciado por Terraform (TechChallenger-infra-kubernetes/observability): alterações feitas na interface são sobrescritas no próximo apply."
    layout_type = "ordered"
    reflow_type = "auto"
    widgets = [for g in local.grupos : {
      definition = {
        type        = "group"
        title       = g.titulo
        layout_type = "ordered"
        widgets     = g.widgets
      }
    }]
  })
}
