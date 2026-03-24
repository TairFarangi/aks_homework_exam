# AKS Homework Project
> This project demonstrates the design and implementation of a production-ready environment on Azure Kubernetes Service (AKS), featuring a secure, end-to-end microservices architecture with ingress routing, network isolation, and runtime health management.

> ## ⚡ TL;DR - Quick Start (Run This First)
>To deploy the entire project (Docker build, Push to ACR, and K8s Deployment) automatically, run:
>
>1. **Update Configuration:** Open deploy-all.sh and update the variables at the top to match your environment:
>
>```Bash
># --- CONFIGURATION (Update these) ---
>RG_NAME="your-resource-group"
>CLUSTER_NAME="your-cluster-name"
>ACR_NAME="your-container-registry-name"
>```
>
>2. **Make the script executable:**
>```Bash
>chmod +x deploy-all.sh
>```
>
>3. **Run the automation script:**
>```bash
>./deploy-all.sh
>```
>Requires: Azure CLI (az login), Docker, and kubectl connected to your AKS cluster.



## Overview

### 🚀 Key Features
- Service A (Node.js): Backend app fetching real-time BTC prices from the CoinGecko API.
- Service B (Nginx): Static web server secured behind network policies.
- Ingress Controller: Path-based routing for external access.
- Network Security: Zero-Trust network model enforced via Kubernetes NetworkPolicy.
- Networking Reliability: Forced IPv4 resolution to prevent connectivity issues in environments where IPv6 is not fully supported by external APIs or container networking layers.
- Self-Healing: Implementation of Liveness and Readiness probes.

### 🏗️ Architecture
- External Access: Services are exposed via a single Public IP:
    - http://<EXTERNAL-IP>/service-a → Routes to Node.js App.
    - http://<EXTERNAL-IP>/service-b → Routes to Nginx.

- Internal Security: A NetworkPolicy is applied to Service B to prevent direct communication from Service A, while allowing ingress traffic from the Ingress Controller and other internal services.

- Application Deployment: The infrastructure is defined as code (YAML) for repeatability.

### Prerequisites:

- Azure CLI & Kubectl configured.
- Install NGINX Ingress Controller:
``` bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
```

- After installing the Ingress Controller, wait for an external IP:
``` bash 
kubectl get svc -n ingress-nginx
```

## 🚀 How to Run (Automated Deployment)
To ensure a fully automated and repeatable setup, a single deployment script is provided (deploy-all.sh).
This script handles the entire lifecycle: cluster connection, ACR authentication, Docker image building, and Kubernetes resource deployment.

### Step 1: Configuration
Before running the script, open deploy-all.sh and update the configuration variables at the top to match your environment:

``` bash
# --- CONFIGURATION (Update these) ---
RG_NAME="your-resource-group"
CLUSTER_NAME="your-cluster-name"
ACR_NAME="your-container-registry-name"
```

### Step 2: Execution
1. Open any Unix-based shell (Linux/macOS/Git Bash on Windows) in the project root directory.

2. Make the script executable:
```Bash
chmod +x deploy-all.sh
```

3. Run the deployment script:
```Bash
./deploy-all.sh
```

- What the script does:
    - Authenticates with Azure Container Registry defined in the configuration variables.
    - Builds and pushes the Service A (Node.js) image.
    - Deploys all resources (Deployments, Services, Ingress, NetworkPolicies) recursively.
    - Waits for Readiness Probes to ensure the services are fully operational before finishing.

### Step 3: Validation & Logs
- The script will wait for the Readiness Probes to pass. 
- Once completed, you can verify the application logic - Bitcoin price retrieval and 10-minute averages by checking the logs:

```Bash
# View real-time BTC prices and 10-minute averages (in service-a):
kubectl logs -l app=service-a --tail=20
```

## Validation

### External Routing:
Validate that the Ingress Controller correctly routes external traffic based on URL paths.

- First, retrieve your Public IP address:
```Bash
# Look for the 'ADDRESS' column
kubectl get ingress aks-main-ingress
```

- Test the routes (via browser or curl):
    - Service A: Open http://<EXTERNAL-IP>/service-a
        - Expected: HTML response ("Service A is Running!") and BTC price logs in the pod logs.
    - Service B: Open http://<EXTERNAL-IP>/service-b
        - Expected: Nginx Welcome page.

### Network Security (East-West):
- Test the Zero-Trust policy. Service A should be forbidden from communicating directly with Service B.
(Test the block from Service A to Service B (Expected: Timeout))

```Bash
# Expected: Timeout or connection refused, proving Service A cannot reach Service B
kubectl exec -it <SERVICE_A_POD> -- wget -qO- --timeout=5 http://service-b
```

### Stability & Self-Healing (Probes):
- Verify that the Liveness and Readiness probes are active:
    - Readiness: Service A only accepts traffic after a successful API fetch.
    - Liveness: Automatic restart if the application process hangs or fails to update data.
- To manually verify probe behavior from inside the cluster:

```bash
kubectl exec -it <SERVICE_A_POD> -- wget -qO- http://localhost:8080/healthz
kubectl exec -it <SERVICE_A_POD> -- wget -qO- http://localhost:8080/ready
```
   - Expected: 
    - /healthz → "Alive"
    - /ready → "Ready" (after at least one successful BTC price fetch)



## 📂 Project Structure
<details>
  <summary><b>Click to view Project Structure</b></summary>

  ```text
├── k8s/
│   ├── deployments/
│   │   ├── service-a-deploy.yaml  # Hardened with Probes & Resources
│   │   └── service-b-deploy.yaml
│   ├── network/
│   │   ├── ingress.yaml           # Nginx Path-based rules
│   │   └── network-policy.yaml    # Isolation logic
│   └── services/
│       ├── service-a-svc.yaml     # Internal ClusterIP
│       └── service-b-svc.yaml
├── app/
│   ├── app.js                     # Node.js app Logic (with /ready & /healthz)
│   ├── package.json
│   └── Dockerfile
└── deploy-all.sh                  # Automated deployment script.
└── README.md                      # Documentation
