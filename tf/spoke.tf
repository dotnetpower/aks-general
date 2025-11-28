# AKS 를 호스팅하는 Spoke 리소스 그룹
resource "azurerm_resource_group" "spoke" {
  name     = var.spoke_resource_group_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "spoke" {
  name                = local.spoke_vnet_name
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name
  address_space       = var.spoke_vnet_address_space
  tags                = local.common_tags
}

resource "azurerm_public_ip" "spoke_nat" {
  name                = "${local.nat_gateway_name}-pip"
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_nat_gateway" "spoke" {
  name                = local.nat_gateway_name
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name
  sku_name            = "Standard"
  tags                = local.common_tags
}

resource "azurerm_nat_gateway_public_ip_association" "spoke" {
  nat_gateway_id       = azurerm_nat_gateway.spoke.id
  public_ip_address_id = azurerm_public_ip.spoke_nat.id
}

resource "azurerm_subnet" "agc" {
  name                 = "AgcSubnet"
  resource_group_name  = azurerm_resource_group.spoke.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.subnet_prefixes.spoke_agc]

  delegation {
    name = "agc-delegation"
    service_delegation {
      name = "Microsoft.ServiceNetworking/trafficControllers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

resource "azurerm_subnet" "aks_nodes" {
  name                 = "AksNodeSubnet"
  resource_group_name  = azurerm_resource_group.spoke.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.subnet_prefixes.spoke_aks_node]
}

resource "azurerm_subnet_nat_gateway_association" "aks" {
  subnet_id      = azurerm_subnet.aks_nodes.id
  nat_gateway_id = azurerm_nat_gateway.spoke.id
}

# AKS 제어 plane 사설 DNS 해석을 위해 허브와 Spoke VNet 모두에 사설 DNS 존을 연결
resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  name                  = local.private_dns_link_hub
  resource_group_name   = azurerm_resource_group.hub.name
  private_dns_zone_name = azurerm_private_dns_zone.aks.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "spoke" {
  name                  = local.private_dns_link_spoke
  resource_group_name   = azurerm_resource_group.hub.name
  private_dns_zone_name = azurerm_private_dns_zone.aks.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
  tags                  = local.common_tags
}

# 허브-스포크 연결을 위한 VNet 피어링
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "hub-to-spoke"
  resource_group_name          = azurerm_resource_group.hub.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "spoke-to-hub"
  resource_group_name          = azurerm_resource_group.spoke.name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = false
}

# AKS 에서 네트워크 리소스를 제어하기 위해 사용할 사용자 할당 ID
resource "azurerm_user_assigned_identity" "aks" {
  name                = "${var.prefix}-aks-identity"
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name
  tags                = local.common_tags
}

# AKS 관리용 사용자 할당 ID 권한 부여
resource "azurerm_role_assignment" "aks_network" {
  scope                = azurerm_virtual_network.spoke.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_role_assignment" "aks_dns" {
  scope                = azurerm_private_dns_zone.aks.id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# AKS 클러스터 정의
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix}-aks"
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name
  dns_prefix          = "${var.prefix}-aks"
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Standard"

  private_cluster_enabled             = true
  private_dns_zone_id                 = azurerm_private_dns_zone.aks.id
  private_cluster_public_fqdn_enabled = false
  workload_identity_enabled           = true
  oidc_issuer_enabled                 = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.aks_node_vm_size
    node_count                   = var.aks_node_count
    vnet_subnet_id               = azurerm_subnet.aks_nodes.id
    only_critical_addons_enabled = true
    os_disk_size_gb              = 128
    os_disk_type                 = "Managed"
    type                         = "VirtualMachineScaleSets"
    upgrade_settings {
      max_surge = "33%"
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    dns_service_ip      = var.dns_service_ip
    service_cidr        = var.service_cidr
    pod_cidr            = var.subnet_prefixes.spoke_pod_cidr
    outbound_type       = "loadBalancer"
  }

  azure_policy_enabled = true

  oms_agent {
    msi_auth_for_monitoring_enabled = true
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.shared.id
  }

  depends_on = [
    azurerm_role_assignment.aks_network,
    azurerm_role_assignment.aks_dns
  ]
}
