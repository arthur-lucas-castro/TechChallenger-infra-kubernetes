terraform {
  required_version = ">= 1.5.0"

  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "4.25.0"
    }
  }
}

# Keys passadas pelo workflow observability.yml: a API key vem do SSM e a application key,
# do secret DATADOG_APP_KEY (TF_VAR_datadog_api_key / TF_VAR_datadog_app_key).
provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
  api_url = "https://api.${var.datadog_site}/"
}
