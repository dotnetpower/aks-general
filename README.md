
# aks-general
전반적인 아키텍처는 다음 문서 참조: https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/containers/aks/baseline-aks#plan-the-ip-addresses


## 네트워크
[Egress 의 type 을 기본 Loadbalancer 에서 UserDefinedRouting 으로 변경하여 PIP 생성 억제](./outboundtype.md)

## Workload Identity 사용 예시
[Workload Identity를 사용하여 ADLS Gen2(Storage Account) 에 접근하는 방법 ](./workload-id.md)