# AKS 에서 workload identity 를 사용하여 Storage Account 에 접근
AKS를 생성할때 Control Plain 이 사용하는 account 와 pod 내에서 사용하는 kubelet account 를 User Assigned Identity 를 생성하여 적용하는 방법

```bash
# 환경변수는 적절하게 변경
RESOURCE_GROUP='rg-adls-01'
LOCATION='koreacentral'
AKS_NAME='aks-cluster-01'
STORAGE_ACCOUNT='stadls01'
CONTROLPLAIN_UAI='aks-controlplane-01'
KUBELET_UAI='aks-kubelet-01'
FILE_SYSTEM_NAME='my-filesystem'
NAMESPACE='default'
SERVICE_ACCOUNT_NAME='workload-sa'

# resource group 생성
az group create --name $RESOURCE_GROUP --location $LOCATION

# User Assigned Identity 생성
# Control Plain 용 User Assigned Identity
az identity create \
  --name $CONTROLPLAIN_UAI \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION

# Kubelet 용 User Assigned Identity
az identity create \
  --name $KUBELET_UAI \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION

# clientId와 resourceId 추출
CONTROLPLAIN_CLIENT_ID=$(az identity show --name $CONTROLPLAIN_UAI --resource-group $RESOURCE_GROUP --query 'clientId' -o tsv)
CONTROLPLAIN_RESOURCE_ID=$(az identity show --name $CONTROLPLAIN_UAI --resource-group $RESOURCE_GROUP --query 'id' -o tsv)
echo "Client ID: $CONTROLPLAIN_CLIENT_ID"
echo "Resource ID: $CONTROLPLAIN_RESOURCE_ID"

KUBELET_CLIENT_ID=$(az identity show --name $KUBELET_UAI --resource-group $RESOURCE_GROUP --query 'clientId' -o tsv)
KUBELET_RESOURCE_ID=$(az identity show --name $KUBELET_UAI --resource-group $RESOURCE_GROUP --query 'id' -o tsv)
echo "Client ID: $KUBELET_CLIENT_ID"
echo "Resource ID: $KUBELET_RESOURCE_ID"

# storage account 생성(ADLS Gen2)
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2 \
  --hns true 

# AKS 생성
az aks create \
  --name $AKS_NAME \
  --resource-group $RESOURCE_GROUP \
  --enable-oidc-issuer \
  --enable-workload-identity \
  --assign-identity $CONTROLPLAIN_RESOURCE_ID \
  --assign-kubelet-identity $KUBELET_RESOURCE_ID \
  --generate-ssh-keys \
  --node-count 2 


# AKS에 Managed Identity Federated Credential 추가
AKS_OIDC_ISSUER=$(az aks show -n $AKS_NAME -g $RESOURCE_GROUP --query "oidcIssuerProfile.issuerUrl" -o tsv)
echo "AKS OIDC Issuer: $AKS_OIDC_ISSUER"

az identity federated-credential create \
  --name ${SERVICE_ACCOUNT_NAME}-fc \
  --identity-name $KUBELET_UAI \
  --resource-group $RESOURCE_GROUP \
  --issuer $AKS_OIDC_ISSUER \
  --subject "system:serviceaccount:$NAMESPACE:$SERVICE_ACCOUNT_NAME"

# Storage Account에 User Assigned Identity 권한 부여
az role assignment create \
  --assignee $KUBELET_CLIENT_ID \
  --role "Storage Blob Data Contributor" \
  --scope $(az storage account show --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP --query id -o tsv)

# 컨테이너 생성
az storage container create \
  --name $FILE_SYSTEM_NAME \
  --account-name $STORAGE_ACCOUNT \
  --auth-mode login

# 테스트 파일 생성
echo 'test file' >> test.txt

# 파일 업로드
az storage fs file upload \
  --account-name $STORAGE_ACCOUNT \
  --source test.txt \
  --path test.txt \
  --file-system $FILE_SYSTEM_NAME \
  --auth-mode login

# 파일 조회
az storage fs file list \
  --account-name $STORAGE_ACCOUNT \
  --file-system $FILE_SYSTEM_NAME \
  --auth-mode login

# AKS 인증 정보 가져오기
az aks get-credentials \
  --name $AKS_NAME \
  --resource-group $RESOURCE_GROUP

# ServiceAccount 생성
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: workload-sa
  namespace: default
  annotations:
    azure.workload.identity/client-id: $KUBELET_CLIENT_ID
EOF


# Pod 생성
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: adls-client
  namespace: default
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: workload-sa
  containers:
    - name: app
      image: mcr.microsoft.com/azure-cli  # 또는 Azure SDK 포함된 이미지
      command: ["/bin/bash", "-c", "while true; do echo 'hello'; sleep 5; done"]
      env:
        - name: STORAGE_ACCOUNT
          value: $STORAGE_ACCOUNT
        - name: FILE_SYSTEM_NAME
          value: $FILE_SYSTEM_NAME
      
EOF

alias k=kubectl

k exec -it adls-client -- /bin/bash
```
pod 내에 접속이 되었다면 `root [ / ]# az login --identity` 명령으로 로그인 시도.

pod 내에서 storage account 파일 조회
```bash
# 파일 조회
az storage fs file list \
  --account-name $STORAGE_ACCOUNT \
  --file-system $FILE_SYSTEM_NAME \
  --auth-mode login

[
  {
    "contentLength": 10,
    "creationTime": "2025-04-09T07:05:34.529594+00:00",
    "encryptionScope": null,
    "etag": "0x8DD7734EC9768B8",
    "expiryTime": null,
    "group": "9fab820a-fa51-4922-b3e4-981d696b3892",
    "isDirectory": false,
    "lastModified": "2025-04-09T07:05:34",
    "name": "test.txt",
    "owner": "9fab820a-fa51-4922-b3e4-981d696b3892",
    "permissions": "rw-r-----"
  }
]
```

workload identity 의 client-id 를 조회

```bash
k describe sa workload-sa

Name:                workload-sa
Namespace:           default
Labels:              <none>
Annotations:         azure.workload.identity/client-id: 4595c900-71a8-4206-829a-3fb5e680f5da
Image pull secrets:  <none>
Mountable secrets:   <none>
Tokens:              <none>
Events:              <none>
```


해당 client id 가 실제 어떤 mi 인지 확인
```bash
az ad sp show --id 4595c900-71a8-4206-829a-3fb5e680f5da
```

displayName 에 kubelet uai 가 확인됨.

## pod 내에서 azure 리소스에 접근할때 IMDS 확인 방법
```bash
curl -H "Metadata: true" \
"http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/"

```
위 명령에서 출력되는 client_id 값이 실제 workload identity 로 사용되는 managed identity 로 확인.

