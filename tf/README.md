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
4. 반복 작업을 줄이고 싶다면 `run-interactive.sh`를 실행하여 Init/Plan/Apply, Helm 설치, Portal 링크 확인 등을 메뉴 기반으로 수행할 수 있습니다.
   ```bash
   cd tf
   chmod +x run-interactive.sh   # 최초 1회
   ./run-interactive.sh
   ```
   스크립트 메뉴에서 원하는 번호를 선택하면 Terraform 명령 실행, AGC 컨트롤러 설치, 포털 링크 출력, Gateway 매니페스트 가이드 확인 등을 순차적으로 진행할 수 있습니다.
5. 완료 후 포털에서 리소스 그룹 상태 확인:
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

## AGC 테스트용 예제 애플리케이션
배포가 끝났다면 아래 순서를 따라 두 개의 Nginx 앱을 배포하고 AGC(Alb Controller)를 통해 Ingress 흐름을 검증할 수 있습니다.

1. **클러스터 자격 증명 다운로드**
    ```bash
    AKS_NAME=$(terraform output -raw aks_cluster_name)
    SPOKE_RG=$(terraform output -raw spoke_resource_group)
    az aks get-credentials --name "$AKS_NAME" --resource-group "$SPOKE_RG" --overwrite-existing
    ```

2. **테스트 매니페스트 작성** – 아래 내용을 `agc-nginx-demo.yaml`로 저장한 뒤 `kubectl apply -f agc-nginx-demo.yaml`를 실행합니다. `APPLICATION_LOAD_BALANCER_ID`와 `APPLICATION_LOAD_BALANCER_FRONTEND`는 Terraform 출력 값을 그대로 치환하세요.

    ```yaml
    apiVersion: networking.agc.microsoft.com/v1beta2
    kind: ApplicationLoadBalancer
    metadata:
       name: internal-alb
       namespace: default
    spec:
       resourceRef:
          id: /subscriptions/b052302c-4c8d-49a4-aa2f-9d60a7301a80/resourceGroups/rg-spoke-251128/providers/Microsoft.ServiceNetworking/trafficControllers/aks-kc-agc
       frontend:
          name: private-frontend

    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
       name: nginx-blue
       labels:
          app: nginx-blue
    spec:
       replicas: 1
       selector:
          matchLabels:
             app: nginx-blue
       template:
          metadata:
             labels:
                app: nginx-blue
          spec:
             containers:
                - name: nginx
                   image: mcr.microsoft.com/oss/nginx/nginx:1.23.3
                   ports:
                      - containerPort: 80
                   env:
                      - name: SITE_COLOR
                         value: "blue"
    ---
    apiVersion: v1
    kind: Service
    metadata:
       name: nginx-blue
    spec:
       selector:
          app: nginx-blue
       ports:
          - port: 80
             targetPort: 80

    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
       name: nginx-green
       labels:
          app: nginx-green
    spec:
       replicas: 1
       selector:
          matchLabels:
             app: nginx-green
       template:
          metadata:
             labels:
                app: nginx-green
          spec:
             containers:
                - name: nginx
                   image: mcr.microsoft.com/oss/nginx/nginx:1.23.3
                   ports:
                      - containerPort: 80
                   env:
                      - name: SITE_COLOR
                         value: "green"
    ---
    apiVersion: v1
    kind: Service
    metadata:
       name: nginx-green
    spec:
       selector:
          app: nginx-green
       ports:
          - port: 80
             targetPort: 80

    ---
    apiVersion: gateway.networking.k8s.io/v1beta1
    kind: Gateway
    metadata:
       name: agc-gateway
    spec:
       gatewayClassName: alb.gateway.azure.com
       listeners:
          - name: http
             protocol: HTTP
             port: 80
             hostname: demo.internal
             allowedRoutes:
                namespaces:
                   from: Same

    ---
    apiVersion: gateway.networking.k8s.io/v1beta1
    kind: HTTPRoute
    metadata:
       name: blue-green-route
    spec:
       parentRefs:
          - name: agc-gateway
             sectionName: http
       hostnames:
          - demo.internal
       rules:
          - matches:
                - path:
                      type: PathPrefix
                      value: /blue
             backendRefs:
                - name: nginx-blue
                   port: 80
          - matches:
                - path:
                      type: PathPrefix
                      value: /green
             backendRefs:
                - name: nginx-green
                   port: 80
    ```

3. **동작 확인** – 게이트웨이와 라우트가 `Accepted=True` 상태인지 확인합니다.
    ```bash
    kubectl get gateway,httproute
    ```
    `demo.internal` 호스트에 대한 DNS 레코드를 사설 DNS에 추가한 뒤(혹은 Pod 내에서 `/etc/hosts`로 매핑) `curl http://demo.internal/blue` / `curl http://demo.internal/green` 요청이 각기 다른 Nginx 응답을 반환하면 AGC Ingress 구성이 정상 동작하는 것입니다.

`curl` 결과에 색상이 보이도록 하고 싶다면 Nginx 컨테이너 이미지 대신 커스텀 HTML을 포함한 간단한 이미지를 사용할 수도 있습니다. 필요 시 복제 수를 늘려 부하 분산 동작도 함께 검증해 보세요.

## 로컬 테스트용 API 서버 접근 전략
프라이빗 AKS는 설계상 퍼블릭 API 엔드포인트가 비활성화되어 있으며, `--api-server-authorized-ip-ranges` 옵션은 지원되지 않습니다(명령 실행 시 *"is not supported for private cluster"* 오류 발생). 따라서 외부에서 임시로 허용 IP를 추가하는 방식 대신 아래와 같은 경로로 테스트를 진행해야 합니다.

1. **`az aks command invoke` 사용**: Azure CLI가 백엔드에서 프라이빗 네트워크에 접속하므로 로컬 PC가 인터넷에만 연결되어 있어도 `kubectl` 명령을 실행할 수 있습니다.
   ```bash
   AKS_NAME=$(terraform output -raw aks_cluster_name)
   SPOKE_RG=$(terraform output -raw spoke_resource_group)

   az aks command invoke \
     --name "$AKS_NAME" \
     --resource-group "$SPOKE_RG" \
     --command "kubectl get nodes"
   ```
   반복 실행 시에도 API 서버는 외부에 개방되지 않습니다.

2. **사설 네트워크 경로 구성**: VPN/ExpressRoute/고정 회선, Azure Bastion, Jumpbox VM 등을 통해 허브·스포크 VNet 내부로 진입한 뒤 `kubectl`을 실행합니다. 이 경우 로컬 PC는 사설 VNet과 동일한 네트워크(또는 피어링된 네트워크)에 있어야 하므로 보안 정책을 만족시키기 쉽습니다.

3. **Dev Box or Azure Container Apps(Az CLI Tunnel)**: 개발자용 환경을 Azure 상에 두고, 해당 환경에서 프라이빗 클러스터에 직접 접근하도록 구성할 수도 있습니다. 이 역시 API 서버를 퍼블릭으로 만들지 않으면서도 조작이 가능합니다.

테스트 후에는 프라이빗 DNS/라우팅 구성만 원상태로 두면 되며, 추가적인 `az aks update --enable-public-fqdn`/`--disable-public-fqdn` 작업이 필요하지 않습니다. 만약 조직 정책상 공용 경로가 꼭 필요한 경우, 아키텍처 자체를 Public AKS + 허용 IP 방식으로 다시 설계해야 합니다.

