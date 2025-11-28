# Application Gateway for Containers (AGC) 리소스 및 관리 ID
resource "azurerm_user_assigned_identity" "agc" {
  name                = "${var.prefix}-agc-identity"
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name
  tags                = local.common_tags
}

# 스포크 서브넷에 연결되는 AGC 본체
resource "azurerm_application_load_balancer" "agc" {
  name                = local.agc_name
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name
  tags                = local.common_tags
}

resource "azurerm_application_load_balancer_subnet_association" "agc" {
  name                         = "${var.prefix}-agc-subnet"
  application_load_balancer_id = azurerm_application_load_balancer.agc.id
  subnet_id                    = azurerm_subnet.agc.id
  tags                         = local.common_tags
}

resource "azurerm_application_load_balancer_frontend" "private" {
  name                         = "private-frontend"
  application_load_balancer_id = azurerm_application_load_balancer.agc.id
  tags                         = local.common_tags
}

# AGC 컨트롤러용 권한 (허브 VNet + 리소스 그룹)
resource "azurerm_role_assignment" "agc_vnet" {
  scope                = azurerm_virtual_network.spoke.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.agc.principal_id
}

resource "azurerm_role_assignment" "agc_rg" {
  scope                = azurerm_resource_group.spoke.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.agc.principal_id
}
