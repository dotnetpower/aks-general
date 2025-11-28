# AKS + AGC 허브-스포크 예제를 위한 기본 입력 변수

variable "location" {
  description = "리소스를 생성할 Azure 지역"
  type        = string
  default     = "koreacentral"
}

variable "hub_resource_group_name" {
  description = "허브 리소스 그룹 이름"
  type        = string
  default     = "rg-hub-251128"
}

variable "spoke_resource_group_name" {
  description = "스포크 리소스 그룹 이름"
  type        = string
  default     = "rg-spoke-251128"
}

variable "prefix" {
  description = "리소스 네이밍 접두사"
  type        = string
  default     = "aks-kc"
}

variable "environment" {
  description = "환경 태그"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default = {
    Project     = "aks-private-agic"
    ManagedBy   = "terraform"
    Environment = "dev"
  }
}

variable "hub_vnet_address_space" {
  description = "허브 가상 네트워크 주소 범위"
  type        = list(string)
  default     = ["10.10.0.0/16"]
}

variable "spoke_vnet_address_space" {
  description = "스포크 가상 네트워크 주소 범위"
  type        = list(string)
  default     = ["10.20.0.0/16"]
}

variable "subnet_prefixes" {
  description = "주요 서브넷에 사용할 CIDR"
  type = object({
    hub_dns_inbound  = string
    hub_dns_outbound = string
    spoke_agc        = string
    spoke_aks_node   = string
    spoke_pod_cidr   = string
  })
  default = {
    hub_dns_inbound  = "10.10.2.0/26"
    hub_dns_outbound = "10.10.2.64/26"
    spoke_agc        = "10.20.2.0/24"
    spoke_aks_node   = "10.20.1.0/24"
    spoke_pod_cidr   = "10.244.0.0/16"
  }
}

variable "kubernetes_version" {
  description = "AKS 제어 plane 버전"
  type        = string
  default     = "1.32.9"
}

variable "aks_node_vm_size" {
  description = "AKS 기본 노드풀 VM 크기"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "aks_node_count" {
  description = "기본 노드풀 초기 노드 수"
  type        = number
  default     = 3
}

variable "service_cidr" {
  description = "AKS 서비스 CIDR"
  type        = string
  default     = "10.100.0.0/16"
}

variable "dns_service_ip" {
  description = "클러스터 DNS 서비스 IP"
  type        = string
  default     = "10.100.0.10"
}

variable "private_dns_zone_name" {
  description = "AKS 프라이빗 제어 plane 용 사설 DNS 존"
  type        = string
  default     = "privatelink.koreacentral.azmk8s.io"
}
