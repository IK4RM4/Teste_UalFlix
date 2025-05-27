# README.md

# UALFlix - Deploy em Kubernetes com Minikube

Este projeto define a infraestrutura de um sistema de streaming distribuído com vários serviços em containers, todos orquestrados por Kubernetes.

## 🧱 Pré-requisitos

- Docker
- Minikube
- kubectl
- Make

## 🚀 1. Iniciar o Minikube
```bash
minikube start --driver=docker
```

## 📦 2. Construir Imagens Localmente (sem Docker Hub)
```bash
minikube image build ./catalog_service -t catalog_service:latest
minikube image build ./authentication_service -t authentication_service:latest
minikube image build ./admin_service -t admin_service:latest
minikube image build ./streaming_service -t streaming_service:latest
minikube image build ./video_processor -t video_processor:latest
minikube image build ./frontend -t frontend:latest
```

## ⚙️ 3. Aplicar toda a configuração Kubernetes
```bash
make apply
```

## 🌐 4. Aceder aos Serviços

### Frontend (React)
```bash
minikube service frontend-service
```

### NGINX Gateway
```bash
minikube service nginx-service
```

### Prometheus
```bash
minikube service prometheus-service
```

### Grafana
```bash
minikube service grafana-service
```

> ⚠️ Podes usar o `nginx-service` como ponto central e configurar o `/` para frontend, `/catalog/` para o catálogo, etc.

## 📊 Métricas disponíveis
- Prometheus coleta métricas de `catalog` e `streaming`
- Grafana pode ser configurado com dashboards para visualizar uso e latência dos serviços

---

## ✅ Testar funcionamento
- Verifica upload/listagem no frontend
- Força falhas matando pods (`kubectl delete pod`) e observa a recuperação
- Consulta logs:
```bash
kubectl logs deployment/catalog-deployment
```

---