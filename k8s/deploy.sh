#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to print status
print_status() {
    echo -e "${YELLOW}[*] $1${NC}"
}

# Function to print success
print_success() {
    echo -e "${GREEN}[+] $1${NC}"
}

# Function to print error
print_error() {
    echo -e "${RED}[-] $1${NC}"
}

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please install it first."
    exit 1
fi

# Create namespace
print_status "Creating namespace..."
kubectl apply -f namespace.yaml

# Create secrets
print_status "Creating secrets..."
kubectl apply -f secrets.yaml

# Deploy MongoDB
print_status "Deploying MongoDB..."
kubectl apply -f database/mongodb-configmap.yaml
kubectl apply -f database/mongodb-service.yaml
kubectl apply -f database/mongodb-statefulset.yaml

# Wait for MongoDB to be ready
print_status "Waiting for MongoDB to be ready..."
kubectl wait --for=condition=ready pod/mongodb-0 -n ualflix --timeout=300s
kubectl wait --for=condition=ready pod/mongodb-1 -n ualflix --timeout=300s
kubectl wait --for=condition=ready pod/mongodb-2 -n ualflix --timeout=300s

# Initialize MongoDB replica set
print_status "Initializing MongoDB replica set..."
kubectl apply -f database/mongodb-init-job.yaml

# Deploy RabbitMQ
print_status "Deploying RabbitMQ..."
kubectl apply -f messaging/rabbitmq-service.yaml
kubectl apply -f messaging/rabbitmq-deployment.yaml

# Wait for RabbitMQ to be ready
print_status "Waiting for RabbitMQ to be ready..."
kubectl wait --for=condition=ready pod -l app=rabbitmq -n ualflix --timeout=300s

# Deploy services
print_status "Deploying services..."
for service in auth catalog streaming admin processor; do
    print_status "Deploying $service service..."
    kubectl apply -f services/$service/
done

# Deploy frontend
print_status "Deploying frontend..."
kubectl apply -f frontend/

# Deploy ingress
print_status "Deploying ingress..."
kubectl apply -f ingress/

# Deploy monitoring
print_status "Deploying monitoring..."
kubectl apply -f monitoring/

print_success "Deployment completed successfully!"
print_status "You can access the application at: http://localhost:80" 