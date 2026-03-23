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

# 5. Force Kubernetes to pull the new image even if the tag is the same
echo -e "${BLUE}🔄 Restarting deployments to apply latest code changes...${NC}"
kubectl rollout restart deployment service-a
kubectl rollout restart deployment service-b

# 6. Wait for Pods to be ready
echo -e "${BLUE}⏳ Waiting for pods to stabilize (Readiness Probes)...${NC}"
# Use label selectors to ensure all pods matching the app label are ready
kubectl wait --for=condition=ready pod -l app=service-a --timeout=180s
kubectl wait --for=condition=ready pod -l app=service-b --timeout=180s

# 7. Display current status
echo -e "${GREEN}✅ Deployment Complete! Current Cluster Status:${NC}"
kubectl get pods,svc,ingress

echo -e "${BLUE}🌐 Hint: Run 'kubectl get ingress' to find your External IP.${NC}"
