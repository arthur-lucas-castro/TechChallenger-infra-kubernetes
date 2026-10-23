#!/usr/bin/env bash
# Separa o state único do monorepo (techchallenger-fase1/terraform.tfstate) em dois:
#   infra-kubernetes/terraform.tfstate  -> VPC, EKS, node group, ECR, cleanup de LB
#   infra-database/terraform.tfstate    -> RDS, subnet group, SG do RDS
#
# Rodar UMA vez, com credenciais AWS válidas do Learner Lab, a partir de qualquer pasta:
#   bash scripts/migrar-state-monorepo.sh
#
# O state antigo NÃO é apagado nem alterado: fica no bucket como backup e também
# é baixado em scripts/.state-migration/monorepo.tfstate (ignorado pelo git).
set -euo pipefail

BUCKET="techchallenger-fase1-terraform-state-shared"
OLD_KEY="techchallenger-fase1/terraform.tfstate"
K8S_KEY="infra-kubernetes/terraform.tfstate"
DB_KEY="infra-database/terraform.tfstate"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
DB_REPO="$(cd "${DB_REPO:-$K8S_REPO/../TechChallenger-infra-database}" && pwd)"
WORK="$SCRIPT_DIR/.state-migration"

DB_RESOURCES=(
  aws_db_instance.this
  aws_db_subnet_group.this
  aws_security_group.rds
)

echo "==> Verificando credenciais AWS"
aws sts get-caller-identity >/dev/null

for key in "$K8S_KEY" "$DB_KEY"; do
  if aws s3api head-object --bucket "$BUCKET" --key "$key" >/dev/null 2>&1; then
    echo "ERRO: s3://$BUCKET/$key já existe. A migração parece já ter sido feita; abortando para não sobrescrever."
    exit 1
  fi
done

rm -rf "$WORK" && mkdir -p "$WORK"
cd "$WORK"

echo "==> Baixando state do monorepo (s3://$BUCKET/$OLD_KEY)"
aws s3 cp "s3://$BUCKET/$OLD_KEY" monorepo.tfstate
cp monorepo.tfstate k8s.tfstate
cp monorepo.tfstate db.tfstate

terraform state list -state=monorepo.tfstate > todos.txt || true
if [ ! -s todos.txt ]; then
  echo "State do monorepo está vazio (infraestrutura já destruída)."
  echo "Nada para migrar: basta rodar o apply de cada repositório na ordem"
  echo "infra-kubernetes -> infra-database -> severless -> Api."
  exit 0
fi

echo "==> Recursos encontrados no monorepo:"
sed 's/^/    /' todos.txt

printf '%s\n' "${DB_RESOURCES[@]}" | sort > db.txt
sort todos.txt | comm -12 - db.txt > db_presentes.txt
sort todos.txt | comm -23 - db.txt > k8s_presentes.txt

echo "==> Montando state do infra-kubernetes (removendo recursos do banco)"
if [ -s db_presentes.txt ]; then
  xargs -d '\n' terraform state rm -state=k8s.tfstate -backup=k8s.backup.tfstate < db_presentes.txt
fi

echo "==> Montando state do infra-database (mantendo só recursos do banco)"
if [ -s k8s_presentes.txt ]; then
  xargs -d '\n' terraform state rm -state=db.tfstate -backup=db.backup.tfstate < k8s_presentes.txt
fi

echo "==> Enviando state para s3://$BUCKET/$K8S_KEY"
(cd "$K8S_REPO" && terraform init -input=false -reconfigure >/dev/null && terraform state push "$WORK/k8s.tfstate")

echo "==> Enviando state para s3://$BUCKET/$DB_KEY"
(cd "$DB_REPO" && terraform init -input=false -reconfigure >/dev/null && terraform state push "$WORK/db.tfstate")

echo "==> Conferência: plan do infra-kubernetes (esperado: sem mudanças de recursos)"
(cd "$K8S_REPO" && terraform plan -input=false -lock=false)

if [ -f "$DB_REPO/terraform.tfvars" ] || [ -n "${TF_VAR_db_password:-}" ]; then
  echo "==> Conferência: plan do infra-database"
  echo "    Esperado: 1 to add (SG rds-client), 1 to change (SG do RDS ganha a regra do rds-client)."
  (cd "$DB_REPO" && terraform plan -input=false -lock=false)
else
  echo "==> Pulei o plan do infra-database: crie $DB_REPO/terraform.tfvars ou exporte TF_VAR_db_username/TF_VAR_db_password."
fi

echo
echo "Migração concluída. O state antigo continua em s3://$BUCKET/$OLD_KEY como backup."
echo "NÃO rode mais os workflows de infra do monorepo: eles enxergariam os mesmos recursos pelo state antigo."
