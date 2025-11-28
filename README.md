
# aks-general
전반적인 아키텍처는 다음 문서 참조: https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/containers/aks/baseline-aks#plan-the-ip-addresses


## 네트워크
[Egress 의 type 을 기본 Loadbalancer 에서 UserDefinedRouting 으로 변경하여 PIP 생성 억제](./outboundtype.md)

## Workload Identity 사용 예시
[Workload Identity를 사용하여 ADLS Gen2(Storage Account) 에 접근하는 방법 ](./workload-id.md)

## Terraform 예제 (AKS + AGC)
- `/tf` 폴더에 AKS 프라이빗 클러스터 + Application Gateway for Containers(AGC) + Azure CNI Overlay 전체 구성이 포함되어 있습니다.
- `tf/README.md` 문서를 먼저 읽고 변수(`variables.tf`)와 출력(`outputs.tf`)을 확인한 뒤 환경에 맞춰 `terraform.tfvars` 등을 준비하세요.
- `.gitignore`에 Terraform 상태/plan/민감 파라미터 파일이 이미 포함되어 있으니, 추가로 제외할 항목이 있으면 동일한 위치에 정의하면 됩니다.

### 실행 요약
1. `az login` 후 목표 구독을 `az account set --subscription <subscriptionId>`로 지정합니다.
2. `cd tf && terraform init && terraform validate` 로 기본 검증을 수행합니다.
3. 반복 작업을 줄이고 싶다면 `./run-interactive.sh`를 실행해 메뉴형 워크플로우(Init → Plan → Apply, Helm/Extension 설치, 출력 조회 등)를 사용할 수 있습니다.
4. `terraform apply`가 완료되면 `tf/README.md`의 `후속 작업` 절차(Helm 또는 `az k8s-extension`로 AGC 컨트롤러 설치, Gateway 매니페스트 배포 등)를 따라 마무리합니다.