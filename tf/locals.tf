locals {
  # 파생 리소스 이름 모음
  hub_vnet_name   = "${var.prefix}-hub-vnet"
  spoke_vnet_name = "${var.prefix}-spoke-vnet"

  agc_name         = "${var.prefix}-agc"
  nat_gateway_name = "${var.prefix}-nat"

  log_analytics_name = "${var.prefix}-law"

  private_dns_link_hub   = "${var.prefix}-hub-dns-link"
  private_dns_link_spoke = "${var.prefix}-spoke-dns-link"

  # 위치와 환경 정보를 병합한 공통 태그
  common_tags = merge(
    var.tags,
    {
      Environment = var.environment
      Location    = var.location
    }
  )
}
