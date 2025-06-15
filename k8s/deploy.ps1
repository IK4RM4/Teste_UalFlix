# Function to print status
function Write-Status {
    param([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Yellow
}

# Function to print success
function Write-Success {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

# Function to print error
function Write-Error {
    param([string]$Message)
    Write-Host "[-] $Message" -ForegroundColor Red
}

# Check if kubectl is installed
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Error "kubectl is not installed. Please install it first."
    exit 1
}

# Create namespace
Write-Status "Creating namespace..."
kubectl apply -f namespace.yaml

# Create secrets
Write-Status "Creating secrets..."
kubectl apply -f secrets.yaml

# Deploy MongoDB
Write-Status "Deploying MongoDB..."
kubectl apply -f database/mongodb-configmap.yaml
kubectl apply -f database/mongodb-service.yaml
kubectl apply -f database/mongodb-statefulset.yaml

# Wait for MongoDB to be ready
Write-Status "Waiting for MongoDB to be ready..."
kubectl wait --for=condition=ready pod/mongodb-0 -n ualflix --timeout=300s
kubectl wait --for=condition=ready pod/mongodb-1 -n ualflix --timeout=300s
kubectl wait --for=condition=ready pod/mongodb-2 -n ualflix --timeout=300s

# Initialize MongoDB replica set
Write-Status "Initializing MongoDB replica set..."
kubectl apply -f database/mongodb-init-job.yaml

# Deploy RabbitMQ
Write-Status "Deploying RabbitMQ..."
kubectl apply -f messaging/rabbitmq-service.yaml
kubectl apply -f messaging/rabbitmq-deployment.yaml

# Wait for RabbitMQ to be ready
Write-Status "Waiting for RabbitMQ to be ready..."
kubectl wait --for=condition=ready pod -l app=rabbitmq -n ualflix --timeout=300s

# Deploy Nginx Ingress
Write-Status "Deploying Nginx Ingress..."
kubectl apply -f ingress/nginx-configmap.yaml
kubectl apply -f ingress/nginx-ingress.yaml

# Wait for Nginx Ingress to be ready
Write-Status "Waiting for Nginx Ingress to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx --timeout=300s

# Deploy services
Write-Status "Deploying services..."
$services = @("auth", "catalog", "streaming", "admin", "processor")
foreach ($service in $services) {
    Write-Status "Deploying $service service..."
    kubectl apply -f services/$service/
}

# Deploy frontend
Write-Status "Deploying frontend..."
kubectl apply -f frontend/

# Deploy monitoring
Write-Status "Deploying monitoring..."
kubectl apply -f monitoring/

# Get minikube IP
$minikubeIP = minikube ip

# Add host entry for ualflix.local
Write-Status "Adding host entry for ualflix.local..."
$hostsPath = "$env:windir\System32\drivers\etc\hosts"
$hostEntry = "`n$minikubeIP ualflix.local"
if (-not (Select-String -Path $hostsPath -Pattern "ualflix.local" -Quiet)) {
    Add-Content -Path $hostsPath -Value $hostEntry
}

Write-Success "Deployment completed successfully!"
Write-Status "You can access the application at: http://ualflix.local"
Write-Status "Kubernetes Dashboard URL:"
minikube dashboard --url 