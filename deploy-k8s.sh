#!/bin/bash
# DEPLOY SIMPLES UALFLIX - KUBERNETES
# Salve como: deploy-k8s.sh
# Execute: bash deploy-k8s.sh

echo "🚀 SUBINDO UALFLIX NO KUBERNETES"

# 1. INICIAR CLUSTER (se não estiver rodando)
echo "▶️ Verificando cluster..."
minikube start --nodes=3 --driver=docker || echo "Cluster já está rodando"

# 2. HABILITAR REGISTRY
echo "▶️ Habilitando registry..."
# minikube addons enable registry
kubectl create namespace ualflix
minikube addons enable ingress

# 3. CONFIGURAR REGISTRY
echo "▶️ Configurando registry..."
kubectl port-forward -n kube-system service/registry 5000:8080 &
sleep 10

# 4. BUILD E PUSH IMAGENS
echo "▶️ Building imagens..."
for service in authentication_service catalog_service streaming_service admin_service video_processor frontend; do
    echo "Building $service..."
    docker build -t localhost:5000/$service:latest ./$service/
    docker push localhost:5000/$service:latest
done

# 5. CORRIGIR DEPLOYMENTS PARA REGISTRY LOCAL
echo "▶️ Corrigindo deployments..."
find k8s -name "*.yaml" -exec sed -i 's|image: \([^:]*\):latest|image: localhost:5000/\1:latest|g' {} \;

# 6. DEPLOY TUDO
echo "▶️ Deploying no Kubernetes..."
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secrets.yaml
kubectl apply -f k8s/database/
sleep 30
kubectl apply -f k8s/messaging/
sleep 20
kubectl apply -f k8s/services/
kubectl apply -f k8s/frontend/
kubectl apply -f k8s/ingress/

# 7. AGUARDAR
echo "▶️ Aguardando pods..."
sleep 60

# 8. MOSTRAR STATUS
echo "✅ PRONTO!"
echo "🌐 Acesse: http://$(minikube ip):30080"
echo "👤 Login: admin/admin"
echo
echo "📊 Status:"
kubectl get pods -n ualflix
kubectl get svc -n ualflix