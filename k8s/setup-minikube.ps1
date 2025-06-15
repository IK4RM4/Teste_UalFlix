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

# Check if minikube is installed
if (-not (Get-Command minikube -ErrorAction SilentlyContinue)) {
    Write-Error "Minikube is not installed. Please install it first."
    exit 1
}

# Stop any existing minikube instance
Write-Status "Stopping any existing Minikube instance..."
minikube stop

# Delete any existing minikube instance
Write-Status "Deleting any existing Minikube instance..."
minikube delete

# Start minikube with 3 nodes
Write-Status "Starting Minikube with 3 nodes..."
minikube start --nodes=3 --driver=docker --cpus=4 --memory=8192 --disk-size=50g

# Enable required addons
Write-Status "Enabling required addons..."
minikube addons enable ingress
minikube addons enable metrics-server
minikube addons enable dashboard

# Configure Docker to use minikube's daemon
Write-Status "Configuring Docker to use Minikube's daemon..."
minikube docker-env | Invoke-Expression

# Build and load images
Write-Status "Building and loading Docker images..."

# Build authentication service
Write-Status "Building authentication service..."
docker build -t authentication_service:latest ./authentication_service

# Build catalog service
Write-Status "Building catalog service..."
docker build -t catalog_service:latest ./catalog_service

# Build streaming service
Write-Status "Building streaming service..."
docker build -t streaming_service:latest ./streaming_service

# Build admin service
Write-Status "Building admin service..."
docker build -t admin_service:latest ./admin_service

# Build video processor
Write-Status "Building video processor..."
docker build -t video_processor:latest ./video_processor

# Build frontend
Write-Status "Building frontend..."
docker build -t frontend:latest ./frontend

# Deploy the application
Write-Status "Deploying the application..."
.\deploy.ps1

# Get minikube IP
$minikubeIP = minikube ip
Write-Success "Minikube is running at: $minikubeIP"
Write-Status "You can access the application at: http://$minikubeIP"

# Show dashboard URL
Write-Status "Kubernetes Dashboard URL:"
minikube dashboard --url 