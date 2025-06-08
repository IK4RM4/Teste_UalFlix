# Makefile para UALFlix - Kubernetes com 3 Nós
# FUNCIONALIDADE 2: IMPLEMENTAÇÃO DE CLUSTER DE COMPUTADORES

NAMESPACE=ualflix
NODES=3
MEMORY=4096
CPUS=2

# Cores para output
RED=\033[0;31m
GREEN=\033[0;32m
YELLOW=\033[1;33m
BLUE=\033[0;34m
NC=\033[0m # No Color

.PHONY: help cluster-start cluster-stop build deploy clean status logs test scale

help: ## Mostrar ajuda
	@echo "${BLUE}UALFlix - Kubernetes com 3 Nós${NC}"
	@echo "${YELLOW}Comandos disponíveis:${NC}"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  ${GREEN}%-15s${NC} %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ========================================
# FUNCIONALIDADE 2: CLUSTER SETUP
# ========================================

cluster-start: ## Iniciar cluster Minikube com 3 nós
	@echo "${BLUE}🚀 Iniciando cluster Kubernetes com $(NODES) nós...${NC}"
	@minikube delete 2>/dev/null || true
	@minikube start \
		--driver=docker \
		--nodes=$(NODES) \
		--cpus=$(CPUS) \
		--memory=$(MEMORY) \
		--disk-size=20g \
		--kubernetes-version=v1.28.0
	@echo "${GREEN}✅ Cluster iniciado com sucesso!${NC}"
	@make addons-enable

addons-enable: ## Habilitar addons necessários
	@echo "${BLUE}🔧 Habilitando addons...${NC}"
	@minikube addons enable ingress
	@minikube addons enable dashboard
	@minikube addons enable metrics-server
	@minikube addons enable default-storageclass
	@minikube addons enable storage-provisioner
	@echo "${GREEN}✅ Addons habilitados!${NC}"

cluster-stop: ## Parar cluster Minikube
	@echo "${RED}🛑 Parando cluster...${NC}"
	@minikube stop

cluster-delete: ## Deletar cluster Minikube
	@echo "${RED}🗑️  Deletando cluster...${NC}"
	@minikube delete

cluster-info: ## Mostrar informações do cluster
	@echo "${BLUE}📊 Informações do Cluster:${NC}"
	@kubectl cluster-info
	@echo "\n${BLUE}📋 Nós do Cluster:${NC}"
	@kubectl get nodes -o wide

# ========================================
# FUNCIONALIDADE 3: VIRTUALIZAÇÃO
# ========================================

docker-env: ## Configurar ambiente Docker do Minikube
	@echo "${BLUE}🐳 Configurando Docker environment...${NC}"
	@eval $$(minikube docker-env)
	@echo "${GREEN}✅ Docker environment configurado!${NC}"

build: ## Build de todas as imagens Docker
	@echo "${BLUE}🏗️  Building Docker images...${NC}"
	@for service in frontend authentication_service catalog_service streaming_service admin_service video_processor; do \
		echo "Building $$service..."; \
		docker build -t localhost:5000/$$service:latest ./$$service/; \
		docker push localhost:5000/$$service:latest; \
	done
	@echo "${GREEN}✅ Todas as imagens foram construídas!${NC}"

images: ## Listar imagens Docker no Minikube
	@echo "${BLUE}📦 Imagens Docker disponíveis:${NC}"
	@eval $$(minikube docker-env) && docker images | grep -E "(frontend|authentication_service|catalog_service|streaming_service|admin_service|video_processor|mongo|rabbitmq|nginx)"

# ========================================
# FUNCIONALIDADE 4: IMPLEMENTAÇÃO NA CLOUD (Kubernetes)
# ========================================

deploy: ## Deploy completo da aplicação
	@echo "${BLUE}🚀 Iniciando deploy da aplicação UALFlix...${NC}"
	@make deploy-namespace
	@make deploy-secrets
	@make deploy-database
	@make deploy-messaging
	@make deploy-services
	@make deploy-frontend
	@make deploy-gateway
	@make deploy-monitoring
	@echo "${GREEN}✅ Deploy completo realizado!${NC}"
	@make status

deploy-namespace: ## Criar namespace
	@echo "${YELLOW}📁 Criando namespace...${NC}"
	@kubectl apply -f k8s/namespace.yaml

deploy-secrets: ## Aplicar secrets e configmaps
	@echo "${YELLOW}🔐 Aplicando secrets e configmaps...${NC}"
	@kubectl apply -f k8s/secrets.yaml

deploy-database: ## Deploy MongoDB
	@echo "${YELLOW}🗄️  Deploying MongoDB...${NC}"
	@kubectl apply -f k8s/database/
	@echo "Aguardando MongoDB ficar pronto..."
	@kubectl wait --for=condition=ready pod -l app=mongodb -n $(NAMESPACE) --timeout=300s || true

deploy-messaging: ## Deploy RabbitMQ
	@echo "${YELLOW}🐰 Deploying RabbitMQ...${NC}"
	@kubectl apply -f k8s/messaging/
	@echo "Aguardando RabbitMQ ficar pronto..."
	@kubectl wait --for=condition=ready pod -l app=rabbitmq -n $(NAMESPACE) --timeout=300s || true

deploy-services: ## Deploy serviços da aplicação
	@echo "${YELLOW}🔧 Deploying application services...${NC}"
	@kubectl apply -f k8s/services/auth/
	@kubectl apply -f k8s/services/catalog/
	@kubectl apply -f k8s/services/streaming/
	@kubectl apply -f k8s/services/admin/
	@kubectl apply -f k8s/services/processor/
	@echo "Aguardando serviços ficarem prontos..."
	@kubectl wait --for=condition=available deployment --all -n $(NAMESPACE) --timeout=300s || true

deploy-frontend: ## Deploy React Frontend
	@echo "${YELLOW}⚛️  Deploying React Frontend...${NC}"
	@kubectl apply -f k8s/frontend/
	@kubectl wait --for=condition=available deployment/frontend -n $(NAMESPACE) --timeout=300s || true

deploy-gateway: ## Deploy NGINX Gateway (Roteador Principal)
	@echo "${YELLOW}🌐 Deploying NGINX Gateway...${NC}"
	@kubectl apply -f k8s/ingress/nginx-configmap.yaml
	@kubectl apply -f k8s/ingress/nginx-deployment.yaml
	@kubectl apply -f k8s/ingress/nginx-service.yaml
	@kubectl wait --for=condition=available deployment/nginx-gateway -n $(NAMESPACE) --timeout=300s || true

deploy-monitoring: ## Deploy Prometheus e Grafana
	@echo "${YELLOW}📊 Deploying monitoring stack...${NC}"
	@kubectl apply -f k8s/monitoring/ || true
	@echo "Aguardando monitoring ficar pronto..."
	@kubectl wait --for=condition=available deployment/prometheus -n $(NAMESPACE) --timeout=300s || true
	@kubectl wait --for=condition=available deployment/grafana -n $(NAMESPACE) --timeout=300s || true

# ========================================
# FUNCIONALIDADE 7: AVALIAÇÃO DE DESEMPENHO
# ========================================

status: ## Verificar status do sistema
	@echo "${BLUE}📊 Status do Sistema UALFlix:${NC}"
	@echo "\n${YELLOW}🏷️  Namespace:${NC}"
	@kubectl get namespace $(NAMESPACE)
	@echo "\n${YELLOW}📦 Pods:${NC}"
	@kubectl get pods -n $(NAMESPACE) -o wide
	@echo "\n${YELLOW}🔗 Services:${NC}"
	@kubectl get services -n $(NAMESPACE)
	@echo "\n${YELLOW}🚀 Deployments:${NC}"
	@kubectl get deployments -n $(NAMESPACE)
	@echo "\n${YELLOW}⚖️  HPA (Auto-scaling):${NC}"
	@kubectl get hpa -n $(NAMESPACE) || echo "Nenhum HPA configurado ainda"

pods: ## Listar pods com detalhes
	@kubectl get pods -n $(NAMESPACE) -o wide

services: ## Listar serviços
	@kubectl get services -n $(NAMESPACE) -o wide

logs: ## Ver logs dos serviços principais
	@echo "${BLUE}📋 Logs dos Serviços:${NC}"
	@echo "\n${YELLOW}🌐 NGINX Gateway:${NC}"
	@kubectl logs -n $(NAMESPACE) deployment/nginx-gateway --tail=10 || true
	@echo "\n${YELLOW}🔐 Authentication Service:${NC}"
	@kubectl logs -n $(NAMESPACE) deployment/auth-service --tail=10 || true
	@echo "\n${YELLOW}📁 Catalog Service:${NC}"
	@kubectl logs -n $(NAMESPACE) deployment/catalog-service --tail=10 || true

logs-follow: ## Seguir logs em tempo real
	@echo "${BLUE}📋 Seguindo logs do NGINX Gateway...${NC}"
	@kubectl logs -f -n $(NAMESPACE) deployment/nginx-gateway

# ========================================
# FUNCIONALIDADE 6: REPLICAÇÃO DE SERVIÇOS
# ========================================

scale: ## Escalar serviços (uso: make scale SERVICE=catalog-service REPLICAS=5)
	@echo "${BLUE}⚖️  Escalando $(SERVICE) para $(REPLICAS) réplicas...${NC}"
	@kubectl scale deployment $(SERVICE) --replicas=$(REPLICAS) -n $(NAMESPACE)
	@kubectl get deployment $(SERVICE) -n $(NAMESPACE)

scale-all: ## Escalar todos os serviços principais
	@echo "${BLUE}⚖️  Escalando todos os serviços...${NC}"
	@kubectl scale deployment auth-service --replicas=3 -n $(NAMESPACE)
	@kubectl scale deployment catalog-service --replicas=4 -n $(NAMESPACE)
	@kubectl scale deployment streaming-service --replicas=4 -n $(NAMESPACE)
	@kubectl scale deployment admin-service --replicas=2 -n $(NAMESPACE)
	@kubectl scale deployment nginx-gateway --replicas=3 -n $(NAMESPACE)
	@echo "${GREEN}✅ Escalamento concluído!${NC}"

scale-down: ## Reduzir réplicas para economizar recursos
	@echo "${YELLOW}⬇️  Reduzindo réplicas...${NC}"
	@kubectl scale deployment auth-service --replicas=1 -n $(NAMESPACE)
	@kubectl scale deployment catalog-service --replicas=2 -n $(NAMESPACE)
	@kubectl scale deployment streaming-service --replicas=2 -n $(NAMESPACE)
	@kubectl scale deployment admin-service --replicas=1 -n $(NAMESPACE)
	@kubectl scale deployment nginx-gateway --replicas=2 -n $(NAMESPACE)

# ========================================
# ACESSO À APLICAÇÃO
# ========================================

url: ## Obter URL da aplicação
	@echo "${BLUE}🌐 URLs de Acesso:${NC}"
	@echo "${GREEN}Aplicação Principal (NGINX Gateway):${NC}"
	@minikube service nginx-gateway --namespace $(NAMESPACE) --url
	@echo "\n${GREEN}Prometheus:${NC}"
	@minikube service prometheus-service --namespace $(NAMESPACE) --url || true
	@echo "\n${GREEN}Grafana:${NC}"
	@minikube service grafana-service --namespace $(NAMESPACE) --url || true

open: ## Abrir aplicação no browser
	@echo "${BLUE}🌐 Abrindo UALFlix no browser...${NC}"
	@minikube service nginx-gateway --namespace $(NAMESPACE)

dashboard: ## Abrir Kubernetes Dashboard
	@echo "${BLUE}📊 Abrindo Kubernetes Dashboard...${NC}"
	@minikube dashboard

tunnel: ## Iniciar tunnel para LoadBalancer (deixar rodando em terminal separado)
	@echo "${BLUE}🚇 Iniciando Minikube tunnel...${NC}"
	@echo "${YELLOW}⚠️  Mantenha este comando rodando em um terminal separado${NC}"
	@minikube tunnel

port-forward: ## Port forward para desenvolvimento
	@echo "${BLUE}🔌 Iniciando port forwards...${NC}"
	@echo "${YELLOW}NGINX Gateway: http://localhost:8080${NC}"
	@kubectl port-forward -n $(NAMESPACE) service/nginx-gateway 8080:8080 &
	@echo "${YELLOW}Prometheus: http://localhost:9090${NC}"
	@kubectl port-forward -n $(NAMESPACE) service/prometheus-service 9090:9090 &
	@echo "${YELLOW}Grafana: http://localhost:3001${NC}"
	@kubectl port-forward -n $(NAMESPACE) service/grafana-service 3001:3000 &
	@echo "${GREEN}✅ Port forwards iniciados em background${NC}"

# ========================================
# TESTES E DEBUG
# ========================================

test: ## Testar conectividade dos serviços
	@echo "${BLUE}🧪 Testando conectividade...${NC}"
	@echo "\n${YELLOW}Testando NGINX Gateway:${NC}"
	@kubectl exec -n $(NAMESPACE) deployment/frontend -- curl -f http://nginx-gateway:8080/health || true
	@echo "\n${YELLOW}Testando Auth Service:${NC}"
	@kubectl exec -n $(NAMESPACE) deployment/frontend -- curl -f http://auth-service:8000/health || true
	@echo "\n${YELLOW}Testando Catalog Service:${NC}"
	@kubectl exec -n $(NAMESPACE) deployment/frontend -- curl -f http://catalog-service:8000/health || true

debug: ## Debug de um pod específico (uso: make debug POD=catalog-service)
	@echo "${BLUE}🐛 Entrando no pod $(POD)...${NC}"
	@kubectl exec -it -n $(NAMESPACE) deployment/$(POD) -- /bin/bash

describe: ## Descrever um recurso (uso: make describe RESOURCE=pod/nome-do-pod)
	@kubectl describe -n $(NAMESPACE) $(RESOURCE)

events: ## Ver eventos do cluster
	@echo "${BLUE}📅 Eventos do Cluster:${NC}"
	@kubectl get events -n $(NAMESPACE) --sort-by=.metadata.creationTimestamp

top: ## Ver utilização de recursos
	@echo "${BLUE}📊 Utilização de Recursos:${NC}"
	@echo "\n${YELLOW}Nós:${NC}"
	@kubectl top nodes || echo "Metrics server não disponível"
	@echo "\n${YELLOW}Pods:${NC}"
	@kubectl top pods -n $(NAMESPACE) || echo "Metrics server não disponível"

# ========================================
# LIMPEZA
# ========================================

clean: ## Remover toda a aplicação (manter cluster)
	@echo "${RED}🧹 Removendo aplicação UALFlix...${NC}"
	@kubectl delete namespace $(NAMESPACE) --ignore-not-found=true
	@echo "${GREEN}✅ Aplicação removida!${NC}"

clean-all: clean cluster-delete ## Remover tudo (aplicação + cluster)
	@echo "${RED}🗑️  Limpeza completa realizada!${NC}"

restart: ## Reiniciar um deployment (uso: make restart SERVICE=catalog-service)
	@echo "${BLUE}🔄 Reiniciando $(SERVICE)...${NC}"
	@kubectl rollout restart deployment/$(SERVICE) -n $(NAMESPACE)
	@kubectl rollout status deployment/$(SERVICE) -n $(NAMESPACE)

restart-all: ## Reiniciar todos os deployments
	@echo "${BLUE}🔄 Reiniciando todos os serviços...${NC}"
	@kubectl rollout restart deployment --all -n $(NAMESPACE)

# Adicionar estas regras ao Makefile existente

# ========================================
# CORREÇÃO PARA MULTI-NODE
# ========================================

setup-registry: ## Configurar registry para multi-node
	@echo "${BLUE}📦 Configurando registry para cluster multi-nó...${NC}"
	@minikube addons enable registry
	@echo "Aguardando registry ficar pronto..."
	@kubectl wait --for=condition=ready pod -l app=registry -n kube-system --timeout=120s || true
	@echo "${GREEN}✅ Registry configurado!${NC}"

start-registry-forward: ## Iniciar port-forward para registry
	@echo "${BLUE}🔌 Iniciando port-forward para registry...${NC}"
	@kubectl port-forward -n kube-system service/registry 5000:80 &
	@sleep 3
	@echo "${GREEN}✅ Registry disponível em localhost:5000${NC}"

build-registry: setup-registry start-registry-forward ## Build para registry local (multi-node)
	@echo "${BLUE}🏗️ Building imagens para registry local...${NC}"
	@for service in frontend authentication_service catalog_service streaming_service admin_service video_processor; do \
		echo "Building $$service..."; \
		docker build -t $$service:latest ./$$service/; \
		docker tag $$service:latest localhost:5000/$$service:latest; \
		docker push localhost:5000/$$service:latest; \
		echo "✅ $$service enviado para registry"; \
	done
	@echo "${GREEN}✅ Todas as imagens no registry local!${NC}"

# Override do build original para detectar multi-node
build: ## Build de todas as imagens Docker (detecta multi-node)
	@NODE_COUNT=$$(kubectl get nodes --no-headers | wc -l); \
	if [ $$NODE_COUNT -gt 1 ]; then \
		echo "${YELLOW}⚠️ Cluster multi-nó detectado ($$NODE_COUNT nós)${NC}"; \
		echo "${BLUE}Usando registry local...${NC}"; \
		$(MAKE) build-registry; \
	else \
		echo "${BLUE}Cluster single-nó, usando docker-env...${NC}"; \
		$(MAKE) docker-env; \
		$(MAKE) build-local; \
	fi

build-local: docker-env ## Build local (apenas single-node)
	@echo "${BLUE}🏗️ Building Docker images localmente...${NC}"
	@eval $$(minikube docker-env) && \
	for service in frontend authentication_service catalog_service streaming_service admin_service video_processor; do \
		echo "Building $$service..."; \
		docker build -t $$service:latest ./$$service/; \
	done
	@echo "${GREEN}✅ Todas as imagens foram construídas!${NC}"

# Deploy com detecção automática
deploy: ## Deploy automático (detecta single/multi-node)
	@NODE_COUNT=$$(kubectl get nodes --no-headers | wc -l); \
	if [ $$NODE_COUNT -gt 1 ]; then \
		echo "${YELLOW}Deploy para cluster multi-nó ($$NODE_COUNT nós)${NC}"; \
		$(MAKE) deploy-multinode; \
	else \
		echo "${BLUE}Deploy para cluster single-nó${NC}"; \
		$(MAKE) deploy-standard; \
	fi

deploy-multinode: ## Deploy para multi-node com registry
	@echo "${BLUE}🚀 Deploy para cluster multi-nó...${NC}"
	@$(MAKE) deploy-namespace
	@$(MAKE) deploy-secrets
	@$(MAKE) deploy-database
	@$(MAKE) deploy-messaging
	@$(MAKE) deploy-services-registry
	@$(MAKE) deploy-frontend-registry
	@$(MAKE) deploy-gateway
	@$(MAKE) deploy-monitoring
	@echo "${GREEN}✅ Deploy multi-nó concluído!${NC}"

deploy-services-registry: ## Deploy serviços usando registry
	@echo "${YELLOW}🔧 Deploying services com registry local...${NC}"
	@# Criar manifests temporários com registry
	@mkdir -p tmp-manifests
	@for service in auth catalog streaming admin processor; do \
		if [ -f "k8s/services/$$service/deployment.yaml" ]; then \
			sed 's|image: \([^:]*\):latest|image: localhost:5000/\1:latest|g' k8s/services/$$service/deployment.yaml > tmp-manifests/$$service-deployment.yaml; \
			kubectl apply -f tmp-manifests/$$service-deployment.yaml; \
			kubectl apply -f k8s/services/$$service/service.yaml; \
		fi \
	done
	@rm -rf tmp-manifests

deploy-frontend-registry: ## Deploy frontend usando registry
	@echo "${YELLOW}⚛️ Deploying frontend com registry...${NC}"
	@mkdir -p tmp-manifests
	@sed 's|image: frontend:latest|image: localhost:5000/frontend:latest|g' k8s/frontend/deployment.yaml > tmp-manifests/frontend-deployment.yaml
	@kubectl apply -f tmp-manifests/frontend-deployment.yaml
	@kubectl apply -f k8s/frontend/service.yaml
	@rm -rf tmp-manifests

deploy-standard: deploy-namespace deploy-secrets deploy-database deploy-messaging deploy-services deploy-frontend deploy-gateway deploy-monitoring ## Deploy padrão

# Converter cluster para single-node (se necessário)
cluster-single: ## Converter para cluster single-node
	@echo "${YELLOW}🔄 Convertendo para cluster single-node...${NC}"
	@minikube delete
	@minikube start \
		--driver=docker \
		--nodes=1 \
		--cpus=$(CPUS) \
		--memory=$(MEMORY) \
		--disk-size=20g \
		--kubernetes-version=v1.28.0
	@$(MAKE) addons-enable
	@echo "${GREEN}✅ Cluster single-node criado!${NC}"

# Build usando Docker Hub (alternativa)
build-dockerhub: ## Build e push para Docker Hub
	@echo "${BLUE}🐳 Building e enviando para Docker Hub...${NC}"
	@read -p "Docker Hub username: " username; \
	for service in frontend authentication_service catalog_service streaming_service admin_service video_processor; do \
		echo "Building $$service..."; \
		docker build -t $$username/ualflix-$$service:latest ./$$service/; \
		docker push $$username/ualflix-$$service:latest; \
	done
	@echo "${GREEN}✅ Imagens enviadas para Docker Hub!${NC}"

# Verificar tipo de cluster
cluster-info-extended: ## Informações detalhadas do cluster
	@echo "${BLUE}📊 Informações do Cluster:${NC}"
	@kubectl cluster-info
	@echo "\n${BLUE}📋 Nós do Cluster:${NC}"
	@kubectl get nodes -o wide
	@NODE_COUNT=$$(kubectl get nodes --no-headers | wc -l); \
	echo "\n${BLUE}Tipo de cluster:${NC}"; \
	if [ $$NODE_COUNT -eq 1 ]; then \
		echo "  🔸 Single-node ($$NODE_COUNT nó) - Use 'make build' normal"; \
	else \
		echo "  🔹 Multi-node ($$NODE_COUNT nós) - Use 'make build-registry'"; \
	fi
	
# ========================================
# FUNCIONALIDADES COMPLETAS
# ========================================

demo: cluster-start deploy url ## Setup completo para demonstração
	@echo "${GREEN}🎉 UALFlix está pronto para demonstração!${NC}"
	@echo "${BLUE}Funcionalidades implementadas:${NC}"
	@echo "✅ FUNCIONALIDADE 1: Tecnologias de Sistemas Distribuídos"
	@echo "✅ FUNCIONALIDADE 2: Cluster de Computadores (3 nós)"
	@echo "✅ FUNCIONALIDADE 3: Virtualização (Docker + Kubernetes)"
	@echo "✅ FUNCIONALIDADE 4: Implementação na Cloud (Kubernetes)"
	@echo "✅ FUNCIONALIDADE 5: Replicação de Dados (MongoDB)"
	@echo "✅ FUNCIONALIDADE 6: Replicação de Serviços (Load Balancing)"
	@echo "✅ FUNCIONALIDADE 7: Avaliação de Desempenho (Métricas)"

verify: ## Verificar se tudo está funcionando
	@echo "${BLUE}✅ Verificação Final do Sistema:${NC}"
	@echo "\n${YELLOW}1. Nós do cluster:${NC}"
	@kubectl get nodes
	@echo "\n${YELLOW}2. Pods em execução:${NC}"
	@kubectl get pods -n $(NAMESPACE)
	@echo "\n${YELLOW}3. Serviços disponíveis:${NC}"
	@kubectl get services -n $(NAMESPACE)
	@echo "\n${YELLOW}4. Testando aplicação:${NC}"
	@curl -f $$(minikube service nginx-gateway --namespace $(NAMESPACE) --url)/health 2>/dev/null && echo "✅ Aplicação respondendo" || echo "❌ Aplicação não responde"