# gitlab enterprise 구성 

```bash
# 지역 및 리소스 그룹
location="koreacentral"
resourceGroup="rg-gitlab"

# 가상 네트워크 및 서브넷
vnetName="gitlab-vnet"
subnetName="gitlab-subnet"

# 네트워크 보안 그룹 및 규칙 이름
nsgName="gitlab-nsg"
nsgRuleHTTP="AllowHTTP"
nsgRuleHTTPS="AllowHTTPS"
nsgRuleSSH="AllowSSH"

# 네트워크 인터페이스
nicName="gitlab-nic"
publicIpName="gitlab-pip"


# 가상 머신
vmName="gitlab-vm"
vmSize="Standard_DS2_v2"
adminUsername="azureuser"
image="Ubuntu2204"

# 기타
publicIpSku="Standard"
```

```bash
echo "📦 리소스 그룹 생성 중..."
az group create \
  --name $resourceGroup \
  --location $location

echo "🌐 VNet 및 Subnet 생성 중..."
az network vnet create \
  --resource-group $resourceGroup \
  --name $vnetName \
  --subnet-name $subnetName

echo "🔐 NSG 생성 및 규칙 추가 중..."
az network nsg create \
  --resource-group $resourceGroup \
  --name $nsgName

# 포트 열기: HTTP (80)
az network nsg rule create \
  --resource-group $resourceGroup \
  --nsg-name $nsgName \
  --name $nsgRuleHTTP \
  --protocol tcp \
  --priority 1000 \
  --destination-port-ranges 80 \
  --access allow \
  --direction inbound

# 포트 열기: HTTPS (443)
az network nsg rule create \
  --resource-group $resourceGroup \
  --nsg-name $nsgName \
  --name $nsgRuleHTTPS \
  --protocol tcp \
  --priority 1010 \
  --destination-port-ranges 443 \
  --access allow \
  --direction inbound

# 포트 열기: SSH (22)
az network nsg rule create \
  --resource-group $resourceGroup \
  --nsg-name $nsgName \
  --name $nsgRuleSSH \
  --protocol tcp \
  --priority 1020 \
  --destination-port-ranges 22 \
  --access allow \
  --direction inbound

echo "🌐 Public IP 생성 중..."
az network public-ip create \
  --resource-group $resourceGroup \
  --name $publicIpName \
  --sku $publicIpSku \
  --allocation-method Static

echo "🔌 NIC 생성 중..."
az network nic create \
  --resource-group $resourceGroup \
  --name $nicName \
  --vnet-name $vnetName \
  --subnet $subnetName \
  --network-security-group $nsgName \
  --public-ip-address $publicIpName

echo "💻 가상 머신 생성 중..."
az vm create \
  --resource-group $resourceGroup \
  --name $vmName \
  --image $image \
  --admin-username $adminUsername \
  --authentication-type ssh \
  --generate-ssh-keys \
  --nics $nicName \
  --size $vmSize 

echo "🌍 Public IP 주소 확인 중..."
publicIp=$(az vm show \
  --resource-group $resourceGroup \
  --name $vmName \
  --show-details \
  --query publicIps \
  --output tsv)

echo "✅ VM 준비 완료: $publicIp"

# ========= GitLab 설치 안내 =========

echo ""
echo "🛠️  SSH로 VM에 접속하여 GitLab EE 설치:"
echo "    ssh $adminUsername@$publicIp"
echo ""
echo "📦 접속 후 아래 명령어 실행:"
cat <<'EOF'

# ===== GitLab EE 설치 명령어 =====

# 시스템 업데이트 및 필수 패키지 설치
sudo apt-get update
sudo apt-get install -y curl openssh-server ca-certificates tzdata perl

# GitLab 저장소 설정
curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ee/script.deb.sh | sudo bash

# GitLab 설치 (퍼블릭 IP 또는 도메인 입력) - 주의! IP 변경
EXTERNAL_URL="http://<public-ip>" sudo apt-get install -y gitlab-ee

# 설치 완료 후 웹 브라우저로 접속:
#   http://<public-ip>

# 초기 root 패스워드 확인
sudo cat /etc/gitlab/initial_root_password

EOF

echo ""

```
