# 허브 리소스 그룹과 공유 서비스
resource "azurerm_resource_group" "hub" {
  name     = var.hub_resource_group_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_log_analytics_workspace" "shared" {
  name                = "${local.log_analytics_name}-${var.location}"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  sku                 = "PerGB2018"
  retention_in_days   = 60
  tags                = local.common_tags
}

resource "azurerm_virtual_network" "hub" {
  name                = local.hub_vnet_name
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  address_space       = var.hub_vnet_address_space
  tags                = local.common_tags
}

resource "azurerm_subnet" "hub_dns_inbound" {
  name                 = "DnsInboundSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.subnet_prefixes.hub_dns_inbound]
}

resource "azurerm_subnet" "hub_dns_outbound" {
  name                 = "DnsOutboundSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.subnet_prefixes.hub_dns_outbound]
}

# 사설 DNS Resolver 및 Inbound/Outbound 엔드포인트
resource "azurerm_private_dns_resolver" "hub" {
  name                = "${var.prefix}-dns-resolver"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  virtual_network_id  = azurerm_virtual_network.hub.id
  tags                = local.common_tags
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "hub" {
  name                    = "${var.prefix}-dns-inbound"
  location                = azurerm_resource_group.hub.location
  private_dns_resolver_id = azurerm_private_dns_resolver.hub.id

  ip_configurations {
    subnet_id                    = azurerm_subnet.hub_dns_inbound.id
    private_ip_allocation_method = "Dynamic"
  }
}

resource "azurerm_private_dns_resolver_outbound_endpoint" "hub" {
  name                    = "${var.prefix}-dns-outbound"
  location                = azurerm_resource_group.hub.location
  private_dns_resolver_id = azurerm_private_dns_resolver.hub.id
  subnet_id               = azurerm_subnet.hub_dns_outbound.id
}

# AKS Private Cluster FQDN 을 위한 사설 DNS 존
resource "azurerm_private_dns_zone" "aks" {
  name                = var.private_dns_zone_name
  resource_group_name = azurerm_resource_group.hub.name
  tags                = local.common_tags
}
