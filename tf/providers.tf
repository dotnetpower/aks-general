terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.115"
    }
  }

  # 운영 배포 전에는 원격 상태 백엔드를 구성하세요
  # backend "azurerm" {}
}

provider "azurerm" {
  features {}
}
