# AKS 프라이빗 클러스터 + Application Gateway for Containers (AGC) + Azure CNI Overlay

이 예제는 **Korea Central** 지역에 허브-스포크 토폴로지를 배치합니다.

- **허브(`rg-hub-2511`)**: Private DNS Resolver, Private DNS Zone, Log Analytics Workspace.
- **스포크(`rg-spoke-2511`)**: Azure CNI Overlay 를 사용하는 프라이빗 AKS 클러스터, AGC(Application Load Balancer), NAT Gateway. 허브와의 VNet 피어링으로 Pod 가 사설 통신을 유지합니다.
- **아웃바운드 경로**: AKS 노드는 스포크 서브넷에 연결된 NAT Gateway 를 통해 인터넷으로 나가며, 고정 공용 IP는 `nat_gateway_public_ip` 출력으로 확인합니다.
- **AGC**: 퍼블릭 IP 없이 전용 서브넷에만 연결되며, Terraform 출력 값을 이용해 Helm 혹은 `az k8s-extension` 으로 컨트롤러를 배포합니다.

## 폴더 구성

| 파일 | 설명 |
| --- | --- |
| `providers.tf` | Terraform/azurerm 버전 고정. |
| `variables.tf` | 지역, CIDR, 노드 수 등 파라미터. |
| `locals.tf` | 파생 이름·공통 태그. |
| `hub.tf` | 허브 RG, VNet, Private DNS. |
| `spoke.tf` | 스포크 RG, VNet, NAT, AKS, 권한. |
| `agc.tf` | Application Load Balancer 및 사용자 할당 ID. |
| `outputs.tf` | 배포 후 참고할 출력 값. |

## 실행 순서

1. Terraform 1.6 이상 설치 ( [가이드](https://developer.hashicorp.com/terraform/tutorials/cli/install-cli) ).
2. Azure CLI 로그인 후 구독 지정:
   ```bash
   az login
   az account set --subscription <subscription-id>
   ```
3. `tf` 폴더에서 실행:
   ```bash
   terraform init
   terraform validate
   terraform plan -out tfplan
   terraform apply tfplan
   ```
4. 완료 후 포털에서 리소스 그룹 상태 확인:
   - 허브: `https://portal.azure.com/#view/HubsExtension/BrowseResourceGroups/resourceId/%2Fsubscriptions%2F<subscriptionId>%2FresourceGroups%2Frg-hub-2511`
   - 스포크: `https://portal.azure.com/#view/HubsExtension/BrowseResourceGroups/resourceId/%2Fsubscriptions%2F<subscriptionId>%2FresourceGroups%2Frg-spoke-2511`

## 후속 작업

1. **AGC 컨트롤러 설치 (Helm)**
   ```bash
   HELM_MSI_CLIENT_ID=$(terraform output -raw agc_identity_client_id)

   helm upgrade --install alb-controller oci://mcr.microsoft.com/application-lb/charts/alb-controller \
     --version 1.0.0 \
     --namespace azure-alb-system \
     --create-namespace \
     --set albController.podIdentity.clientID="$HELM_MSI_CLIENT_ID"
   ```
   `application_load_balancer_id` 및 `application_load_balancer_frontend_name` 출력 값은 Gateway API/`ApplicationLoadBalancer` 매니페스트에서 참조합니다.

2. **AKS Extension 사용(선택)**: `az k8s-extension create --extension-type microsoft.alb/alb-controller` 명령으로 동일한 사용자 할당 ID를 넘겨 설치할 수 있습니다. 세부값은 [공식 문서](https://learn.microsoft.com/azure/application-gateway/)를 참고하세요.

3. **게이트웨이 매니페스트 배포**: `ApplicationLoadBalancer`, `Gateway`, `HTTPRoute` 리소스를 작성하여 AGC가 사설 리스너를 구성하도록 지정합니다.

4. **운영 팁**
   - `nat_gateway_public_ip` 출력이 AKS 아웃바운드 공용 IP 입니다.
   - CIDR, 노드 크기 등은 `variables.tf` 값을 덮어써 조정합니다. (예: `terraform apply -var "aks_node_count=5"`).
   - 실서비스에서는 원격 상태 저장소(Azure Storage 등)를 사용하고 CI/CD 파이프라인에 통합하세요.

## Azure CLI 스크립트 예제
Terraform 대신 Azure CLI로 동일한 리소스를 생성하려면 아래 스크립트를 복사해 실행하세요. 미리 `SUBSCRIPTION_ID`를 실제 구독 ID로 바꾸고, 필요 시 CIDR/노드 수 등의 기본값을 수정하면 됩니다. Application Load Balancer(AGC) CLI는 `alb` 확장이 필요하므로 스크립트 초반에 자동으로 설치합니다.

```bash
#!/usr/bin/env bash
set -euo pipefail

# ===== 사용자 입력 =====
SUBSCRIPTION_ID="<subscription-id>"   # 예: b052302c-4c8d-49a4-aa2f-9d60a7301a80
LOCATION="koreacentral"
PREFIX="aks-kc"
ENV_TAG="dev"

HUB_RG="rg-hub-2511"
SPOKE_RG="rg-spoke-2511"
PRIVATE_DNS_ZONE="privatelink.koreacentral.azmk8s.io"

HUB_VNET_CIDR="10.10.0.0/16"
SPOKE_VNET_CIDR="10.20.0.0/16"
SUBNET_DNS_IN="10.10.2.0/26"
SUBNET_DNS_OUT="10.10.2.64/26"
SUBNET_AKS="10.20.1.0/24"
SUBNET_AGC="10.20.2.0/24"
POD_CIDR="10.244.0.0/16"
SERVICE_CIDR="10.100.0.0/16"
DNS_SERVICE_IP="10.100.0.10"
NODE_COUNT=3
NODE_SIZE="Standard_D4s_v3"
K8S_VERSION="1.32.9"

[[ "$SUBSCRIPTION_ID" == "<subscription-id>" ]] && {
   echo "[오류] SUBSCRIPTION_ID 값을 실제 구독 ID로 변경하세요." >&2
   exit 1
}

# ===== 파생 변수 =====
TAGS="Environment=$ENV_TAG ManagedBy=azure-cli Project=aks-private-agc Location=$LOCATION"
HUB_VNET="${PREFIX}-hub-vnet"
SPOKE_VNET="${PREFIX}-spoke-vnet"
LOG_ANALYTICS="${PREFIX}-law-${LOCATION}"
NAT_NAME="${PREFIX}-nat"
NAT_PIP="${NAT_NAME}-pip"
AKS_NAME="${PREFIX}-aks"
AKS_ID_NAME="${PREFIX}-aks-identity"
AGC_NAME="${PREFIX}-agc"
AGC_ID_NAME="${PREFIX}-agc-identity"
AGC_FRONTEND="private-frontend"
PRIVATE_DNS_LINK_HUB="${PREFIX}-hub-dns-link"
PRIVATE_DNS_LINK_SPOKE="${PREFIX}-spoke-dns-link"
SPOKE_RG_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$SPOKE_RG"

az account set --subscription "$SUBSCRIPTION_ID"
az extension add --name aks-preview --upgrade
az extension add --name alb --upgrade

for ns in Microsoft.ContainerService Microsoft.Network Microsoft.ServiceNetworking Microsoft.ServiceLinker; do
   state=$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
   [[ "$state" != "Registered" ]] && az provider register --namespace "$ns" --wait
done

az group create --name "$HUB_RG" --location "$LOCATION" --tags $TAGS >/dev/null
az group create --name "$SPOKE_RG" --location "$LOCATION" --tags $TAGS >/dev/null

az monitor log-analytics workspace create \
   --resource-group "$HUB_RG" \
   --workspace-name "$LOG_ANALYTICS" \
   --location "$LOCATION" \
   --retention-time 60 \
   --tags $TAGS >/dev/null
LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show -g "$HUB_RG" -n "$LOG_ANALYTICS" --query id -o tsv)

az network vnet create -g "$HUB_RG" -n "$HUB_VNET" --location "$LOCATION" --address-prefixes "$HUB_VNET_CIDR" --tags $TAGS >/dev/null
az network vnet subnet create -g "$HUB_RG" --vnet-name "$HUB_VNET" --name DnsInboundSubnet --address-prefixes "$SUBNET_DNS_IN"
az network vnet subnet create -g "$HUB_RG" --vnet-name "$HUB_VNET" --name DnsOutboundSubnet --address-prefixes "$SUBNET_DNS_OUT"

az network vnet create -g "$SPOKE_RG" -n "$SPOKE_VNET" --location "$LOCATION" --address-prefixes "$SPOKE_VNET_CIDR" --tags $TAGS >/dev/null
az network vnet subnet create -g "$SPOKE_RG" --vnet-name "$SPOKE_VNET" --name AksNodeSubnet --address-prefixes "$SUBNET_AKS"
az network vnet subnet create -g "$SPOKE_RG" --vnet-name "$SPOKE_VNET" --name AgcSubnet --address-prefixes "$SUBNET_AGC" --delegations "Microsoft.ServiceNetworking/trafficControllers"

HUB_VNET_ID=$(az network vnet show -g "$HUB_RG" -n "$HUB_VNET" --query id -o tsv)
SPOKE_VNET_ID=$(az network vnet show -g "$SPOKE_RG" -n "$SPOKE_VNET" --query id -o tsv)
AKS_SUBNET_ID=$(az network vnet subnet show -g "$SPOKE_RG" --vnet-name "$SPOKE_VNET" -n AksNodeSubnet --query id -o tsv)
AGC_SUBNET_ID=$(az network vnet subnet show -g "$SPOKE_RG" --vnet-name "$SPOKE_VNET" -n AgcSubnet --query id -o tsv)
DNS_INBOUND_SUBNET_ID=$(az network vnet subnet show -g "$HUB_RG" --vnet-name "$HUB_VNET" -n DnsInboundSubnet --query id -o tsv)
DNS_OUTBOUND_SUBNET_ID=$(az network vnet subnet show -g "$HUB_RG" --vnet-name "$HUB_VNET" -n DnsOutboundSubnet --query id -o tsv)

az network public-ip create -g "$SPOKE_RG" -n "$NAT_PIP" --sku Standard --allocation-method Static --location "$LOCATION" --tags $TAGS >/dev/null
az network nat gateway create -g "$SPOKE_RG" -n "$NAT_NAME" --location "$LOCATION" --public-ip-addresses "$NAT_PIP" --tags $TAGS >/dev/null
az network vnet subnet update -g "$SPOKE_RG" --vnet-name "$SPOKE_VNET" --name AksNodeSubnet --nat-gateway "$NAT_NAME" >/dev/null

az network private-dns zone create -g "$HUB_RG" -n "$PRIVATE_DNS_ZONE" >/dev/null
PRIVATE_DNS_ZONE_ID=$(az network private-dns zone show -g "$HUB_RG" -n "$PRIVATE_DNS_ZONE" --query id -o tsv)
az network private-dns link vnet create -g "$HUB_RG" -n "$PRIVATE_DNS_LINK_HUB" --zone-name "$PRIVATE_DNS_ZONE" --virtual-network "$HUB_VNET_ID" --registration-enabled false >/dev/null
az network private-dns link vnet create -g "$HUB_RG" -n "$PRIVATE_DNS_LINK_SPOKE" --zone-name "$PRIVATE_DNS_ZONE" --virtual-network "$SPOKE_VNET_ID" --registration-enabled false >/dev/null

DNS_RESOLVER_NAME="${PREFIX}-dns-resolver"
az network private-dns-resolver create -g "$HUB_RG" -n "$DNS_RESOLVER_NAME" --location "$LOCATION" --virtual-network "$HUB_VNET_ID" --tags $TAGS >/dev/null
az network private-dns-resolver inbound-endpoint create -g "$HUB_RG" --resolver-name "$DNS_RESOLVER_NAME" --name "${PREFIX}-dns-inbound" --location "$LOCATION" --ip-configurations subnet=$DNS_INBOUND_SUBNET_ID >/dev/null
az network private-dns-resolver outbound-endpoint create -g "$HUB_RG" --resolver-name "$DNS_RESOLVER_NAME" --name "${PREFIX}-dns-outbound" --location "$LOCATION" --subnet $DNS_OUTBOUND_SUBNET_ID >/dev/null

az network vnet peering create -g "$HUB_RG" --name hub-to-spoke --vnet-name "$HUB_VNET" --remote-vnet "$SPOKE_VNET_ID" --allow-vnet-access --allow-forwarded-traffic >/dev/null
az network vnet peering create -g "$SPOKE_RG" --name spoke-to-hub --vnet-name "$SPOKE_VNET" --remote-vnet "$HUB_VNET_ID" --allow-vnet-access --allow-forwarded-traffic >/dev/null

az identity create -g "$SPOKE_RG" -n "$AKS_ID_NAME" --location "$LOCATION" --tags $TAGS >/dev/null
az identity create -g "$SPOKE_RG" -n "$AGC_ID_NAME" --location "$LOCATION" --tags $TAGS >/dev/null
AKS_ID=$(az identity show -g "$SPOKE_RG" -n "$AKS_ID_NAME" --query id -o tsv)
AKS_PRINCIPAL_ID=$(az identity show -g "$SPOKE_RG" -n "$AKS_ID_NAME" --query principalId -o tsv)
AGC_ID=$(az identity show -g "$SPOKE_RG" -n "$AGC_ID_NAME" --query id -o tsv)
AGC_PRINCIPAL_ID=$(az identity show -g "$SPOKE_RG" -n "$AGC_ID_NAME" --query principalId -o tsv)
AGC_CLIENT_ID=$(az identity show -g "$SPOKE_RG" -n "$AGC_ID_NAME" --query clientId -o tsv)

az role assignment create --assignee-object-id "$AKS_PRINCIPAL_ID" --assignee-principal-type ServicePrincipal --role "Network Contributor" --scope "$SPOKE_VNET_ID" >/dev/null
az role assignment create --assignee-object-id "$AKS_PRINCIPAL_ID" --assignee-principal-type ServicePrincipal --role "Private DNS Zone Contributor" --scope "$PRIVATE_DNS_ZONE_ID" >/dev/null
az role assignment create --assignee-object-id "$AGC_PRINCIPAL_ID" --assignee-principal-type ServicePrincipal --role "Network Contributor" --scope "$SPOKE_VNET_ID" >/dev/null
az role assignment create --assignee-object-id "$AGC_PRINCIPAL_ID" --assignee-principal-type ServicePrincipal --role "Contributor" --scope "$SPOKE_RG_ID" >/dev/null

az network alb create --resource-group "$SPOKE_RG" --name "$AGC_NAME" --location "$LOCATION" --tags $TAGS >/dev/null
az network alb frontend create --resource-group "$SPOKE_RG" --alb-name "$AGC_NAME" --name "$AGC_FRONTEND" --subnet "$AGC_SUBNET_ID" >/dev/null

az aks create \
   --resource-group "$SPOKE_RG" \
   --name "$AKS_NAME" \
   --location "$LOCATION" \
   --kubernetes-version "$K8S_VERSION" \
   --tier Standard \
   --nodepool-name system \
   --node-count "$NODE_COUNT" \
   --node-vm-size "$NODE_SIZE" \
   --node-osdisk-size 128 \
   --network-plugin azure \
   --network-plugin-mode overlay \
   --pod-cidr "$POD_CIDR" \
   --service-cidr "$SERVICE_CIDR" \
   --dns-service-ip "$DNS_SERVICE_IP" \
   --vnet-subnet-id "$AKS_SUBNET_ID" \
   --outbound-type loadBalancer \
   --enable-private-cluster \
   --private-dns-zone "$PRIVATE_DNS_ZONE_ID" \
   --enable-managed-identity \
   --assign-identity "$AKS_ID" \
   --enable-oidc-issuer \
   --enable-workload-identity \
   --enable-azure-policy \
   --enable-addons monitoring \
   --workspace-resource-id "$LOG_ANALYTICS_ID" \
   --tags $TAGS

cat <<INFO
========================================
생성 완료
----------------------------------------
AKS 리소스 그룹 : $SPOKE_RG
AKS 클러스터   : $AKS_NAME
AGC 리소스 ID  : $(az network alb show -g "$SPOKE_RG" -n "$AGC_NAME" --query id -o tsv)
AGC 프런트엔드 : $AGC_FRONTEND
AGC UAMI ID    : $AGC_ID
AGC Client ID  : $AGC_CLIENT_ID
========================================
INFO
```

> ⚠️ **주의**
> - `az network alb` 명령은 Alb 확장(미리보기) 기능을 사용하므로 최신 CLI(또는 `az upgrade`)가 필요합니다.
> - Azure CLI가 미리보기 기능을 호출할 때 종종 시간이 오래 걸립니다. 명령 실패 시 같은 단계를 다시 실행하거나 `--debug` 옵션으로 상세 로그를 확인하세요.
> - Terraform과 동일하게 AKS는 Managed NAT Gateway 아웃바운드를 사용하므로, 별도 egress 경로가 필요하면 `--outbound-type`과 NAT 설정을 환경에 맞게 조정하세요.
