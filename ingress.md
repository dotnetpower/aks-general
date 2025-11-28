# Ingress Controller
https://learn.microsoft.com/ko-kr/azure/application-gateway/tutorial-ingress-controller-add-on-existing#deploy-a-new-application-gateway

```bash
RESOURCE_GROUP='myResourceGroup2'
LOCATION='koreacentral'
AKS_NAME='myCluster'

az group create --name $RESOURCE_GROUP --location $LOCATION
az aks create --name $AKS_NAME --resource-group $RESOURCE_GROUP --network-plugin azure --network-plugin-mode overlay --enable-managed-identity --generate-ssh-keys --kubernetes-version 1.32.0

# deploy a new appgw
az network public-ip create --name myPublicIp --resource-group $RESOURCE_GROUP --allocation-method Static --sku Standard
az network vnet create --name myVnet --resource-group $RESOURCE_GROUP --address-prefix 10.0.0.0/16 --subnet-name mySubnet --subnet-prefix 10.0.0.0/24 
az network application-gateway create --name myApplicationGateway --resource-group $RESOURCE_GROUP --sku Standard_v2 --public-ip-address myPublicIp --vnet-name myVnet --subnet mySubnet --priority 100

# enabling AGIC addon
appgwId=$(az network application-gateway show --name myApplicationGateway --resource-group $RESOURCE_GROUP -o tsv --query "id") 
az aks enable-addons --name $AKS_NAME --resource-group $RESOURCE_GROUP --addon ingress-appgw --appgw-id $appgwId

# peering between vnets
nodeResourceGroup=$(az aks show --name $AKS_NAME --resource-group $RESOURCE_GROUP -o tsv --query "nodeResourceGroup")
aksVnetName=$(az network vnet list --resource-group $nodeResourceGroup -o tsv --query "[0].name")

aksVnetId=$(az network vnet show --name $aksVnetName --resource-group $nodeResourceGroup -o tsv --query "id")
az network vnet peering create --name AppGWtoAKSVnetPeering --resource-group $RESOURCE_GROUP --vnet-name myVnet --remote-vnet $aksVnetId --allow-vnet-access

appGWVnetId=$(az network vnet show --name myVnet --resource-group $RESOURCE_GROUP -o tsv --query "id")
az network vnet peering create --name AKStoAppGWVnetPeering --resource-group $nodeResourceGroup --vnet-name $aksVnetName --remote-vnet $appGWVnetId --allow-vnet-access

# deploy a sample app
az aks get-credentials --name $AKS_NAME --resource-group $RESOURCE_GROUP
kubectl apply -f https://raw.githubusercontent.com/Azure/application-gateway-kubernetes-ingress/master/docs/examples/aspnetapp.yaml

# verify
kubectl get ingress


# test upgrade to LTS version
# https://learn.microsoft.com/ko-kr/azure/aks/long-term-support#migrate-to-the-latest-lts-version

az aks update --resource-group $RESOURCE_GROUP --name $AKS_NAME --tier premium --k8s-support-plan AKSLongTermSupport --auto-upgrade-channel patch

# az group delete --name $RESOURCE_GROUP 
# az group delete --name MC_myResourceGroup_myCluster_eastus




apiVersion: v1
kind: Pod
metadata:
  name: aspnetapp
  labels:
    app: aspnetapp
spec:
  containers:
  - image: "mcr.microsoft.com/dotnet/samples:aspnetapp"
    name: aspnetapp-image
    ports:
    - containerPort: 8080
      protocol: TCP

---

apiVersion: v1
kind: Service
metadata:
  name: aspnetapp
spec:
  selector:
    app: aspnetapp
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080

---

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: aspnetapp
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
spec:
  ingressClassName: azure-application-gateway
  rules:
  - http:
      paths:
      - path: /
        backend:
          service:
            name: aspnetapp
            port:
              number: 80
        pathType: Exact

```