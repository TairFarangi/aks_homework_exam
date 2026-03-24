#!/bin/bash

# --- CONFIGURATION (Update these) ---
RG_NAME="aks-homework-rg" # Azure resource group 
CLUSTER_NAME="aks-homework-cluster" # K8S cluster name
ACR_NAME="tairfacr01" # Azure container registry name

# Colors for better visibility
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🚀 Starting automated deployment...${NC}"

# Check context
if [ ! -d "./app" ] || [ ! -d "./k8s" ]; then
    echo -e "${RED}❌ Error: Please run this script from the project root directory!${NC}"
    exit 1
fi

# 1. Connect to the AKS cluster
echo -e "${BLUE}🔑 Connecting to AKS cluster...${NC}"
az aks get-credentials --resource-group $RG_NAME --name $CLUSTER_NAME --overwrite-existing

# 2. Login to ACR
echo -e "${BLUE}🔐 Logging in to Azure Container Registry...${NC}"
az acr login --name $ACR_NAME

# 3. Build and Push Image (Service A)
echo -e "${BLUE}📦 Building and pushing Docker image...${NC}"
docker build -t $ACR_NAME.azurecr.io/service-a:latest ./app
docker push $ACR_NAME.azurecr.io/service-a:latest

# 4. Apply K8s Resources
echo -e "${BLUE}☸️ Applying Kubernetes resources...${NC}"
kubectl apply -f k8s/ -R

# 5. Restart Deployments
echo -e "${BLUE}🔄 Restarting deployments to apply latest code changes...${NC}"
kubectl rollout restart deployment service-a
kubectl rollout restart deployment service-b

# 6. Wait for Pods to be ready
echo -e "${BLUE}⏳ Waiting for pods to stabilize (Readiness Probes)...${NC}"
# Use label selectors to ensure all pods matching the app label are ready
kubectl wait --for=condition=ready pod -l app=service-a --timeout=180s
kubectl wait --for=condition=ready pod -l app=service-b --timeout=180s

# 7. Wait for External IP
echo -e "${BLUE}⏳ Waiting for External IP (this may take a minute)...${NC}"

EXTERNAL_IP=""
# Loop until the Ingress gets an IP from Azure Load Balancer
while [ -z "$EXTERNAL_IP" ]; do
  # Adjust 'main-ingress' to your actual Ingress name if it's different in your YAML
  EXTERNAL_IP=$(kubectl get ingress -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [ -z "$EXTERNAL_IP" ]; then
    echo -n "."
    sleep 5
  fi
done

echo -e "\n${GREEN}✅ Deployment Complete!${NC}"
echo -e "${GREEN}-------------------------------------------------------${NC}"
echo -e "${BLUE}🚀 You can access the services here:${NC}"
echo -e "Service A: ${GREEN}http://$EXTERNAL_IP/service-a${NC}"
echo -e "Service B: ${GREEN}http://$EXTERNAL_IP/service-b${NC}"
echo -e "${GREEN}-------------------------------------------------------${NC}"