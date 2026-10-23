data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 7

  tags = {
    Project     = var.cluster_name
    Environment = var.environment
    Terraform   = "true"
  }
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = data.aws_iam_role.lab_role.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = module.vpc.private_subnets
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  enabled_cluster_log_types = ["api", "audit"]

  depends_on = [aws_cloudwatch_log_group.eks]

  tags = {
    Project     = var.cluster_name
    Environment = var.environment
    Terraform   = "true"
  }
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = data.aws_iam_role.lab_role.arn
  subnet_ids      = module.vpc.private_subnets

  instance_types = var.node_instance_types
  disk_size      = var.node_disk_size

  scaling_config {
    min_size     = var.node_group_min_size
    max_size     = var.node_group_max_size
    desired_size = var.node_group_desired_size
  }

  labels = {
    role = "app"
  }

  tags = {
    Project     = var.cluster_name
    Environment = var.environment
    Terraform   = "true"
  }
}

resource "null_resource" "cleanup_k8s_load_balancers" {
  triggers = {
    cluster_name = aws_eks_cluster.this.name
    region       = "us-east-1"
    vpc_id       = module.vpc.vpc_id
    service_name = "techchallenger-api"
  }

  depends_on = [aws_eks_cluster.this, aws_eks_node_group.default, module.vpc]

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -uo pipefail

      echo "Configurando kubeconfig para o cluster ${self.triggers.cluster_name}..."
      if ! aws eks update-kubeconfig --name "${self.triggers.cluster_name}" --region "${self.triggers.region}"; then
        echo "Cluster indisponível ou já destruído, seguindo sem limpeza via kubectl."
        exit 0
      fi

      echo "Removendo todos os Services type=LoadBalancer do cluster..."
      kubectl get services --all-namespaces --no-headers \
        -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,TYPE:.spec.type \
        | awk '$3 == "LoadBalancer" { print $1, $2 }' \
        | while read -r ns name; do
            [ -n "$name" ] || continue
            echo "  - $ns/$name"
            kubectl delete service "$name" -n "$ns" --ignore-not-found=true --timeout=60s || true
          done

      echo "Aguardando load balancers remanescentes na VPC ${self.triggers.vpc_id} serem removidos..."
      for i in $(seq 1 30); do
        count=$(aws elbv2 describe-load-balancers --region "${self.triggers.region}" \
          --query "length(LoadBalancers[?VpcId=='${self.triggers.vpc_id}'])" --output text 2>/dev/null || echo 0)
        if [ "$count" = "0" ]; then
          echo "Nenhum load balancer remanescente na VPC."
          exit 0
        fi
        echo "Tentativa $i/30: ainda há $count load balancer(es) na VPC, aguardando 10s..."
        sleep 10
      done

      echo "AVISO: ainda há load balancer(es) na VPC após 5 minutos de espera; o destroy das subnets pode falhar."
    EOT
  }
}
