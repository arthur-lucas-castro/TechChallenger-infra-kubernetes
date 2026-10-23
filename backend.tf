terraform {
  backend "s3" {
    bucket         = "techchallenger-fase1-terraform-state-shared"
    key            = "infra-kubernetes/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "techchallenger-fase1-terraform-lock-shared"
    encrypt        = true
  }
}
