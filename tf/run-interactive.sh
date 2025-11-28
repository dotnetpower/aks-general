#!/usr/bin/env bash
set -euo pipefail

# 인터랙티브 실행 메뉴를 통해 Terraform 배포와 후속 작업을 순차적으로 수행합니다.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PLAN_FILE="tfplan"

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[오류] '$cmd' 명령을 찾을 수 없습니다. 먼저 설치해 주세요." >&2
    exit 1
  fi
}

ensure_state_exists() {
  if [[ ! -f "terraform.tfstate" ]]; then
    echo "[안내] terraform.tfstate 파일이 없습니다. 먼저 'Terraform Apply'를 실행해 주세요." >&2
    exit 1
  fi
}

run_terraform_init() {
  require_command terraform
  terraform init
}

run_terraform_validate() {
  require_command terraform
  terraform validate
}

run_terraform_plan() {
  require_command terraform
  terraform plan -out "$PLAN_FILE"
}

run_terraform_apply() {
  require_command terraform
  if [[ ! -f "$PLAN_FILE" ]]; then
    echo "[안내] $PLAN_FILE 파일이 없어 새로 plan 을 생성합니다."
    terraform plan -out "$PLAN_FILE"
  fi
  terraform apply -auto-approve "$PLAN_FILE"
}

show_portal_links() {
  local subscription_id
  if command -v az >/dev/null 2>&1; then
    subscription_id=$(az account show --query id -o tsv 2>/dev/null || echo "<subscription-id>")
  else
    subscription_id="<subscription-id>"
  fi

  local hub_url="https://portal.azure.com/#view/HubsExtension/BrowseResourceGroups/resourceId/%2Fsubscriptions%2F${subscription_id}%2FresourceGroups%2Frg-hub-2511"
  local spoke_url="https://portal.azure.com/#view/HubsExtension/BrowseResourceGroups/resourceId/%2Fsubscriptions%2F${subscription_id}%2FresourceGroups%2Frg-spoke-2511"

  cat <<EOF
[포털 링크]
허브 RG : $hub_url
스포크 RG : $spoke_url
EOF
}

fetch_output() {
  require_command terraform
  ensure_state_exists
  terraform output -raw "$1"
}

install_helm_controller() {
  require_command terraform
  require_command helm
  ensure_state_exists

  local client_id
  client_id=$(terraform output -raw agc_identity_client_id)

  HELM_MSI_CLIENT_ID="$client_id" \
  helm upgrade --install alb-controller oci://mcr.microsoft.com/application-lb/charts/alb-controller \
    --version 1.0.0 \
    --namespace azure-alb-system \
    --create-namespace \
    --set albController.podIdentity.clientID="$client_id"
}

install_alb_extension() {
  require_command terraform
  require_command az
  ensure_state_exists

  local client_id aks_name aks_rg
  client_id=$(terraform output -raw agc_identity_client_id)
  aks_name=$(terraform output -raw aks_cluster_name)
  aks_rg=$(terraform output -raw spoke_resource_group)

  az k8s-extension create \
    --name alb-controller \
    --extension-type microsoft.alb/alb-controller \
    --cluster-type managedClusters \
    --cluster-name "$aks_name" \
    --resource-group "$aks_rg" \
    --scope cluster \
    --configuration-settings podIdentity.clientId="$client_id"
}

show_gateway_hints() {
  cat <<'EOF'
[게이트웨이 매니페스트 가이드]
1. terraform output -raw application_load_balancer_id 값으로 ApplicationLoadBalancer 리소스를 참조합니다.
2. application_load_balancer_frontend_name 을 Gateway 리스너(frontend)와 매핑합니다.
3. Gateway / HTTPRoute 리소스에 원하는 사설 FQDN 및 백엔드 서비스를 정의합니다.
4. 배포는 kubectl apply -f <manifest.yaml> 방식으로 진행합니다.
EOF
}

print_outputs() {
  require_command terraform
  ensure_state_exists
  terraform output
}

menu() {
  cat <<'EOF'
========================================
AKS + AGC 워크플로우 인터랙티브 스크립트
========================================
1) Terraform Init
2) Terraform Validate
3) Terraform Plan (-out tfplan)
4) Terraform Apply (-auto-approve tfplan)
5) Azure Portal 링크 출력
6) Helm 으로 AGC 컨트롤러 설치
7) az k8s-extension 으로 AGC 컨트롤러 설치
8) Gateway 매니페스트 가이드 출력
9) Terraform Outputs 표시
0) 종료
EOF
}

while true; do
  menu
  read -rp "원하는 작업 번호를 입력하세요: " choice
  case "$choice" in
    1) run_terraform_init ;;
    2) run_terraform_validate ;;
    3) run_terraform_plan ;;
    4) run_terraform_apply ;;
    5) show_portal_links ;;
    6) install_helm_controller ;;
    7) install_alb_extension ;;
    8) show_gateway_hints ;;
    9) print_outputs ;;
    0) echo "종료합니다."; break ;;
    *) echo "유효하지 않은 선택입니다." ;;
  esac
  echo
  read -rp "계속하려면 Enter 를 누르세요..." _pause
  echo
done
