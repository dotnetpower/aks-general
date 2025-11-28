output "hub_resource_group" {
  description = "허브 리소스 그룹 이름"
  value       = azurerm_resource_group.hub.name
}

output "spoke_resource_group" {
  description = "스포크 리소스 그룹 이름"
  value       = azurerm_resource_group.spoke.name
}

output "aks_cluster_name" {
  description = "배포된 AKS 클러스터 이름"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "application_load_balancer_id" {
  description = "AGC(Application Load Balancer) 리소스 ID"
  value       = azurerm_application_load_balancer.agc.id
}

output "application_load_balancer_frontend_name" {
  description = "Gateway API 매니페스트에서 참조할 프런트엔드 이름"
  value       = azurerm_application_load_balancer_frontend.private.name
}

output "agc_identity_client_id" {
  description = "AGC에서 사용할 사용자 할당 ID의 클라이언트 ID"
  value       = azurerm_user_assigned_identity.agc.client_id
}

output "nat_gateway_public_ip" {
  description = "Spoke NAT Gateway 를 통해 노출되는 고정 공용 IP"
  value       = azurerm_public_ip.spoke_nat.ip_address
}
