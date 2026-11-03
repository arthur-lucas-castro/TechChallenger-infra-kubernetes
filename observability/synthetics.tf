# Healthcheck e uptime vistos de fora da AWS: GET /health pelo API Gateway, o mesmo
# caminho de um cliente. Cobre gateway, VPC Link, NLB, nodes e pod de uma vez.
resource "datadog_synthetics_test" "api_health" {
  count = local.api_gateway_endpoint == "" ? 0 : 1

  name      = "[Oficina] Uptime da API (GET /health)"
  type      = "api"
  subtype   = "http"
  status    = "live"
  locations = ["aws:us-east-1", "aws:sa-east-1"]

  request_definition {
    method  = "GET"
    url     = "${local.api_gateway_endpoint}/health"
    timeout = 10
  }

  assertion {
    type     = "statusCode"
    operator = "is"
    target   = "200"
  }

  assertion {
    type     = "responseTime"
    operator = "lessThan"
    target   = "2000"
  }

  options_list {
    tick_every = 300
    # Alerta só quando as duas regiões falham, para não acordar ninguém por um blip de rede.
    min_location_failed = 2

    retry {
      count    = 1
      interval = 1000
    }

    monitor_options {
      renotify_interval = 0
    }
  }

  message = <<-EOT
    {{#is_alert}}A API não responde em ${local.api_gateway_endpoint}/health. Confira o API Gateway, o NLB interno e os pods (`kubectl get pods -l app=${var.api_deployment}`).{{/is_alert}}
    {{#is_recovery}}API respondendo novamente.{{/is_recovery}}
    ${local.notify}
  EOT

  tags = concat(local.tags, ["area:uptime"])
}
