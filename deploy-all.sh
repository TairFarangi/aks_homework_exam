#!/bin/bash
set -e # Terminate script immediately if a command returns a non-zero exit code

# --- FALLBACK DEFAULTS (Used only if no existing resources are detected) ---
NEW_RG="aks-homework-rg"
NEW_LOCATION="westeurope"
NEW_CLUSTER="aks-homework-cluster"
NEW_ACR="tairfacr01"

# Colors for better visibility
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🚀 Starting FULL automated infrastructure setup and deployment...${NC}"

# Ensure the script is executed from the project root (where app/ and k8s/ exist)
if [ ! -d "./app" ] || [ ! -d "./k8s" ]; then
    echo -e "${RED}❌ Error: Please run this script from the project root directory!${NC}"
    exit 1
fi


# --- STEP 1: RESOURCE GROUP DISCOVERY ---
echo -e "${BLUE}🔍 Step 1: Discovering Active AKS Resource Group...${NC}"

# 1. Primary Check: Find a Resource Group that already contains an active AKS cluster
RG_NAME=$(az aks list --query "[0].resourceGroup" -o tsv)

# 2. Secondary Check: If no AKS is found, look for our specific fallback RG name
if [ -z "$RG_NAME" ]; then
    echo -e "${YELLOW}⚠️ No active AKS found. Searching for existing RG: $NEW_RG...${NC}"
    RG_NAME=$(az group list --query "[?name=='$NEW_RG'].name" -o tsv)
fi

# 3. Final Fallback: If still not found, create a new Resource Group
if [ -z "$RG_NAME" ]; then
    echo -e "${YELLOW}ℹ️ No relevant Resource Group found. Creating new: $NEW_RG...${NC}"
    az group create --name $NEW_RG --location $NEW_LOCATION
    RG_NAME=$NEW_RG
else
    echo -e "${GREEN}✅ Found existing relevant Resource Group: $RG_NAME${NC}"
fi


# --- STEP 2: ACR DISCOVERY ---
echo -e "${BLUE}🔍 Step 2: Discovering Container Registry in $RG_NAME...${NC}"

# Search for an existing ACR ONLY within the identified Resource Group
ACR_NAME=$(az acr list --resource-group $RG_NAME --query "[0].name" -o tsv)

if [ -z "$ACR_NAME" ]; then
    echo -e "${YELLOW}🏗️ No ACR found in $RG_NAME. Creating new: $NEW_ACR...${NC}"
    az acr create --resource-group $RG_NAME --name $NEW_ACR --sku Basic
    ACR_NAME=$NEW_ACR
    sleep 10 # Allow extra time for Azure DNS to update
else
    echo -e "${GREEN}✅ Found existing ACR: $ACR_NAME (in $RG_NAME)${NC}"
fi


# --- STEP 3: AKS DISCOVERY ---
echo -e "${BLUE}🔍 Step 3: Discovering AKS Cluster in $RG_NAME...${NC}"

# Search for an existing AKS cluster specifically within the identified Resource Group
CLUSTER_NAME=$(az aks list --resource-group $RG_NAME --query "[0].name" -o tsv)

if [ -z "$CLUSTER_NAME" ]; then
    echo -e "${YELLOW}☸️ No AKS found in $RG_NAME. Creating new: $NEW_CLUSTER (5-10 mins)...${NC}"
    az aks create \
        --resource-group $RG_NAME \
        --name $NEW_CLUSTER \
        --node-count 1 \
        --node-vm-size Standard_B2s_v2 \
        --enable-managed-identity \
        --network-plugin azure \
        --network-policy calico \
        --generate-ssh-keys

    CLUSTER_NAME=$NEW_CLUSTER
else
    echo -e "${GREEN}✅ Found existing AKS Cluster: $CLUSTER_NAME (in $RG_NAME)${NC}"
fi

# Ensure the ACR is attached to the AKS cluster for image pulling permissions
echo -e "${BLUE}🔗 Ensuring ACR connectivity for AKS Cluster...${NC}"
az aks update -n $CLUSTER_NAME -g $RG_NAME --attach-acr $ACR_NAME

# --- STEP 4: PREPARATION & CONNECTIVITY to AKS cluster ---
echo -e "${BLUE}🔑 Refreshing AKS credentials for $CLUSTER_NAME...${NC}"
az aks get-credentials --resource-group $RG_NAME --name $CLUSTER_NAME --overwrite-existing

# Implement a retry loop to handle potential DNS propagation delays
echo -e "${BLUE}⏳ Testing connectivity to Kubernetes API...${NC}"
for i in {1..5}; do
    if kubectl cluster-info &>/dev/null; then
        echo -e "${GREEN}✅ Cluster is reachable!${NC}"
        break
    else
        echo -e "${YELLOW}⚠️ Connection/DNS issues detected. Retrying in 15s... ($i/5)${NC}"
        sleep 15
    fi
    if [ $i -eq 5 ]; then echo -e "${RED}❌ Timeout: Cannot connect to cluster.${NC}"; exit 1; fi
done

echo -e "${BLUE}🔐 Logging in to Azure Container Registry: $ACR_NAME...${NC}"
# Retry logic for ACR login to handle transient networking or DNS issues
for i in {1..3}; do
    if az acr login --name $ACR_NAME 2>/dev/null; then
        echo -e "${GREEN}✅ ACR Login successful!${NC}"
        break
    else
        echo -e "${YELLOW}⚠️ Login failed, retrying in 10s... ($i/3)${NC}"
        sleep 10
    fi
done


# --- STEP 4.5: INGRESS CONTROLLER CHECK ---
echo -e "${BLUE}🔍 Checking for NGINX Ingress Controller...${NC}"
if ! kubectl get namespace ingress-nginx &>/dev/null; then
    echo -e "${YELLOW}🌐 Ingress Controller not found. Installing now...${NC}"
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
    echo -e "${BLUE}⏳ Waiting for Ingress Controller to initialize...${NC}"
    sleep 20
else
    echo -e "${GREEN}✅ NGINX Ingress Controller is already installed.${NC}"
fi


# --- STEP 5: BUILD, PUSH & DEPLOY ---
echo -e "${BLUE}📦 Building and pushing image to $ACR_NAME...${NC}"
docker build -t $ACR_NAME.azurecr.io/service-a:latest ./app
docker push $ACR_NAME.azurecr.io/service-a:latest

echo -e "${BLUE}☸️ Applying Kubernetes resources...${NC}"
kubectl apply -f k8s/ -R


# --- STEP 6: FINAL SYNC & VERIFICATION ---
echo -e "${BLUE}🔄 Restarting deployments to ensure latest image pulled...${NC}"
kubectl rollout restart deployment service-a
kubectl rollout restart deployment service-b

echo -e "${BLUE}⏳ Waiting for pods to stabilize (Readiness Checks)...${NC}"
kubectl wait --for=condition=ready pod -l app=service-a --timeout=300s
kubectl wait --for=condition=ready pod -l app=service-b --timeout=300s

echo -e "${BLUE}⏳ Fetching External IP...${NC}"
EXTERNAL_IP=""
while [ -z "$EXTERNAL_IP" ]; do
  EXTERNAL_IP=$(kubectl get ingress -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  if [ -z "$EXTERNAL_IP" ]; then
    echo -n "."
    sleep 10
  fi
done


echo -e "\n${GREEN}✅ DEPLOYMENT SUCCESSFUL!${NC}"
echo -e "${GREEN}-------------------------------------------------------${NC}"
echo -e "${BLUE}🚀 You can access the services here:${NC}"
echo -e "URL for Service A : ${BLUE}http://$EXTERNAL_IP/service-a${NC}"
echo -e "URL for Service B : ${BLUE}http://$EXTERNAL_IP/service-b${NC}"
echo -e "${GREEN}-------------------------------------------------------${NC}"