# AKS Homework Project
A production-ready microservices environment on Azure Kubernetes Service (AKS), featuring automated infrastructure discovery, ingress routing, zero-trust network isolation, and self-healing runtime management.

 ## ⚡ TL;DR - Quick Start (Run This First)
The deployment is fully automated. 
The script handles the entire lifecycle: cluster discovery/provisioning, ACR authentication, Docker builds, and Kubernetes resource deployment.

1. **Login to Azure:**
```Bash
az login
```

2. **Run the automation script:**
```Bash
chmod +x deploy-all.sh  # Optional if needed
./deploy-all.sh
```

**Requirements:** Azure CLI, Docker, and kubectl connected to your AKS cluster.

## Architecture & Features

### 🚀 Key Capabilities
* Smart Auto-Discovery: The script scans your subscription and attaches itself to existing resources, eliminating the need for manual configuration.
* Service A (Node.js): A backend application fetching real-time BTC prices with internal 10-minute moving average logic.
* Service B (Hello-Kubernetes): A specialized demonstration service providing real-time pod metadata and environment details.
* Path-Based Ingress: Unified entry point via Nginx Ingress Controller.
* Zero-Trust Networking: Strict NetworkPolicy prevents unauthorized internal communication (e.g., Service A cannot reach Service B directly).
* Self-Healing: Liveness and Readiness probes ensure traffic only reaches healthy pods.
* Networking Reliability: Forced IPv4 resolution to prevent connectivity issues in environments where IPv6 is not fully supported by external APIs or container networking layers.


### 🗺️ System Flow
- External Access: Services are exposed via a single Public IP:
    - `http://<EXTERNAL-IP>/service-a` → Routes to Node.js App.
    - `http://<EXTERNAL-IP>/service-b` → Routes to Hello-Kubernetes Dashboard (include pod and node info).
- Internal Security: A NetworkPolicy is applied to Service B to prevent direct communication from Service A, while allowing ingress traffic from the Ingress Controller (and other internal services).
By using a namespaceSelector in the NetworkPolicy, we ensure that the only authorized path to Service B is through the formal Ingress route.
- Infrastructure as Code: All resources are defined via YAML manifests for full repeatability.


### 🛠️ Automated Pipeline (deploy-all.sh)
The provided script handles the entire lifecycle without requiring any manual variable updates:
1. **Infrastructure Discovery:** Locates your Resource Group, Container Registry (ACR), and AKS Cluster.
2. **Provisioning (On-Demand):** If no environment is detected, it provisions a new, hardened AKS setup from scratch.
3. **Auto-Installation:** Automatically installs the NGINX Ingress Controller if not present in the cluster.
4. **CI/CD Flow:** Builds the Service A Docker image, pushes it to ACR, and authenticates the cluster.
5. **K8s Deployment:** Applies all manifests (Deployments, Services, Ingress, NetworkPolicies) recursively.
6. **Connectivity Validation:** Implements retry logic to handle DNS propagation and ensures the API server is reachable before deploying.
7. **Final Output:** Provides the public LoadBalancer URLs for immediate testing.



## 🧠 Architectural Notes
- State: The 10-minute history is stored In-Memory for this demo. In a full environment, Redis or CosmosDB would be used to persist data across pod restarts.
- Scalability: Configured with replicas: 1 (Singleton) to ensure consistent logging and avoid API rate limits. Horizontal scaling would require a shared database (Producer/Consumer pattern).
- Resiliency: A Readiness Probe is implemented to ensure the service reports as Not Ready until the first successful API fetch is completed after a restart.



## Validation & Testing

### External Routing Access
Validate that the Ingress Controller correctly routes external traffic based on URL paths.
Once the script completes, it will display your Public IP.

- Test the routes (via browser or curl):
    - Service A: Open `http://<EXTERNAL-IP>/service-a`
        - Expected: HTML response ("Service A is Running!") and BTC price logs in the pod logs.
    - Service B: Open `http://<EXTERNAL-IP>/service-b`
        - Expected: visual dashboard showing Pod Name and Node info.


### Network Isolation (Security Check)
To verify the Zero-Trust policy, attempt to reach Service B from Service A:
(Service A should be forbidden from communicating directly with Service B)

```Bash
# This should TIMEOUT, proving the NetworkPolicy is enforcing isolation
kubectl exec -it $(kubectl get pod -l app=service-a -o jsonpath='{.items[0].metadata.name}') -- wget -qO- --timeout=5 http://service-b
```

### Application Logs
- The script will wait for the Readiness Probes to pass. 
- Once completed, you can verify the application logic - Bitcoin price retrieval and 10-minute averages by checking the logs:

Monitor the BTC price fetching and moving average calculations:

```Bash
# View real-time BTC prices and 10-minute averages (in service-a):
kubectl logs -l app=service-a --tail=20
```

### Stability & Self-Healing (Probes):
- Verify that the Liveness and Readiness probes are active:
    - Readiness: Service A only accepts traffic after a successful API fetch.
    - Liveness: Automatic restart if the application process hangs or fails to update data.
- To manually verify probe behavior from inside the cluster:

```bash
# Expected: /healthz -> "Alive", /ready -> "Ready" (after first successful API fetch)
kubectl exec -it $(kubectl get pod -l app=service-a -o jsonpath='{.items[0].metadata.name}') -- wget -qO- http://localhost:8080/healthz
kubectl exec -it $(kubectl get pod -l app=service-a -o jsonpath='{.items[0].metadata.name}') -- wget -qO- http://localhost:8080/ready
```


## 📂 Project Structure
<details>
  <summary><b>Click to view Project Structure</b></summary>

  ```text
├── k8s/
│   ├── deployments/
│   │   ├── service-a-deployment.yaml 
│   │   └── service-b-deployment.yaml
│   ├── network/
│   │   ├── ingress.yaml           # Nginx Path-based rules
│   │   └── network-policy.yaml    # Isolation logic
│   └── services/
│       ├── service-a-svc.yaml     
│       └── service-b-svc.yaml
├── app/
│   ├── app.js                     # Node.js app Logic (with /ready & /healthz)
│   ├── package.json
│   └── Dockerfile
│   └── .gitignore
└── deploy-all.sh                  # Automated deployment script
└── README.md                      # Documentation
