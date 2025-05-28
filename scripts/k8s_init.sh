#!/bin/bash
# setup-ualflix-k8s.sh
# Script completo para setup do UALFlix no Kubernetes com 3 nós

set -e  # Parar em caso de erro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configurações
NAMESPACE="ualflix"
NODES=3
MEMORY=4096
CPUS=2

echo -e "${BLUE}🎬 UALFlix - Setup Kubernetes com 3 Nós${NC}"
echo -e "${PURPLE}=================================================${NC}"

# Função para imprimir status
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar pré-requisitos
check_prerequisites() {
    print_status "Verificando pré-requisitos..."
    
    # Verificar Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker não encontrado. Por favor, instale o Docker primeiro."
        exit 1
    fi
    
    # Verificar kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl não encontrado. Por favor, instale o kubectl primeiro."
        exit 1
    fi
    
    # Verificar Minikube
    if ! command -v minikube &> /dev/null; then
        print_error "Minikube não encontrado. Por favor, instale o Minikube primeiro."
        exit 1
    fi
    
    print_success "Todos os pré-requisitos estão instalados!"
}

# Inicializar cluster
start_cluster() {
    print_status "Iniciando cluster Minikube com $NODES nós..."
    
    # Parar Minikube existente se houver
    print_status "Parando instâncias existentes do Minikube..."
    minikube delete 2>/dev/null || true
    
    # Iniciar novo cluster
    minikube start \
        --driver=docker \
        --nodes=$NODES \
        --cpus=$CPUS \
        --memory=$MEMORY \
        --disk-size=20g \
        --kubernetes-version=v1.28.0
    
    print_success "Cluster iniciado com $NODES nós!"
    
    # Verificar nós
    print_status "Verificando nós do cluster..."
    kubectl get nodes
}

# Habilitar addons
enable_addons() {
    print_status "Habilitando addons necessários..."
    
    minikube addons enable ingress
    minikube addons enable dashboard
    minikube addons enable metrics-server
    minikube addons enable default-storageclass
    minikube addons enable storage-provisioner
    
    print_success "Addons habilitados!"
}

# Configurar Docker environment
setup_docker_env() {
    print_status "Configurando Docker environment do Minikube..."
    eval $(minikube docker-env)
    print_success "Docker environment configurado!"
}

# Build das imagens
build_images() {
    print_status "Construindo imagens Docker..."
    
    setup_docker_env
    
    # Lista de serviços para build
    services=("frontend" "authentication_service" "catalog_service" "streaming_service" "admin_service" "video_processor")
    
    for service in "${services[@]}"; do
        print_status "Building $service..."
        docker build -t ${service}:latest ./${service}/
    done
    
    print_success "Todas as imagens foram construídas!"
    
    # Listar imagens
    print_status "Imagens disponíveis:"
    docker images | grep -E "(frontend|authentication_service|catalog_service|streaming_service|admin_service|video_processor)"
}

# Deploy da aplicação
deploy_application() {
    print_status "Iniciando deploy da aplicação UALFlix..."
    
    # 1. Namespace
    print_status "Criando namespace..."
    kubectl apply -f k8s/namespace.yaml
    
    # 2. Secrets e ConfigMaps
    print_status "Aplicando secrets e configmaps..."
    kubectl apply -f k8s/secrets.yaml
    
    # 3. MongoDB (Base de dados)
    print_status "Deploying MongoDB..."
    kubectl apply -f k8s/database/
    
    print_status "Aguardando MongoDB ficar pronto..."
    kubectl wait --for=condition=ready pod -l app=mongodb -n $NAMESPACE --timeout=300s || true
    sleep 10
    
    # 4. RabbitMQ (Message Queue)
    print_status "Deploying RabbitMQ..."
    kubectl apply -f k8s/messaging/
    
    print_status "Aguardando RabbitMQ ficar pronto..."
    kubectl wait --for=condition=ready pod -l app=rabbitmq -n $NAMESPACE --timeout=300s || true
    sleep 5
    
    # 5. Serviços da aplicação
    print_status "Deploying application services..."
    kubectl apply -f k8s/services/auth/
    kubectl apply -f k8s/services/catalog/
    kubectl apply -f k8s/services/streaming/
    kubectl apply -f k8s/services/admin/
    kubectl apply -f k8s/services/processor/
    
    print_status "Aguardando serviços ficarem prontos..."
    sleep 30
    kubectl wait --for=condition=available deployment --all -n $NAMESPACE --timeout=300s || true
    
    # 6. Frontend
    print_status "Deploying React Frontend..."
    kubectl apply -f k8s/frontend/
    kubectl wait --for=condition=available deployment/frontend -n $NAMESPACE --timeout=300s || true
    
    # 7. NGINX Gateway (Roteador Principal)
    print_status "Deploying NGINX Gateway (Roteador Principal)..."
    kubectl apply -f k8s/ingress/nginx-configmap.yaml
    kubectl apply -f k8s/ingress/nginx-deployment.yaml
    kubectl apply -f k8s/ingress/nginx-service.yaml
    kubectl wait --for=condition=available deployment/nginx-gateway -n $NAMESPACE --timeout=300s || true
    
    # 8. Monitoring (Opcional)
    print_status "Deploying monitoring stack..."
    kubectl apply -f k8s/monitoring/ || true
    
    print_success "Deploy da aplicação concluído!"
}

# Verificar status
check_status() {
    print_status "Verificando status do sistema..."
    
    echo -e "\n${YELLOW}📋 Namespace:${NC}"
    kubectl get namespace $NAMESPACE
    
    echo -e "\n${YELLOW}🏷️  Nós do cluster:${NC}"
    kubectl get nodes -o wide
    
    echo -e "\n${YELLOW}📦 Pods:${NC}"
    kubectl get pods -n $NAMESPACE -o wide
    
    echo -e "\n${YELLOW}🔗 Services:${NC}"
    kubectl get services -n $NAMESPACE
    
    echo -e "\n${YELLOW}🚀 Deployments:${NC}"
    kubectl get deployments -n $NAMESPACE
    
    echo -e "\n${YELLOW}💾 Persistent Volumes:${NC}"
    kubectl get pv
    kubectl get pvc -n $NAMESPACE
}

# Obter URLs de acesso
get_access_urls() {
    print_status "Obtendo URLs de acesso..."
    
    echo -e "\n${GREEN}🌐 URLs de Acesso:${NC}"
    
    echo -e "${BLUE}Aplicação Principal (NGINX Gateway):${NC}"
    NGINX_URL=$(minikube service nginx-gateway --namespace $NAMESPACE --url)
    echo "  $NGINX_URL"
    
    echo -e "\n${BLUE}Prometheus:${NC}"
    PROMETHEUS_URL=$(minikube service prometheus-service --namespace $NAMESPACE --url 2>/dev/null || echo "  Não disponível")
    echo "  $PROMETHEUS_URL"
    
    echo -e "\n${BLUE}Grafana:${NC}"
    GRAFANA_URL=$(minikube service grafana-service --namespace $NAMESPACE --url 2>/dev/null || echo "  Não disponível")
    echo "  $GRAFANA_URL"
    
    echo -e "\n${BLUE}Kubernetes Dashboard:${NC}"
    echo "  Execute: minikube dashboard"
}

# Testes básicos
run_tests() {
    print_status "Executando testes básicos..."
    
    # Teste de conectividade
    print_status "Testando conectividade interna..."
    
    # Aguardar um pouco para garantir que tudo está pronto
    sleep 10
    
    # Testar NGINX Gateway
    if kubectl exec -n $NAMESPACE deployment/frontend -- curl -f http://nginx-gateway:8080/health --max-time 10 >/dev/null 2>&1; then
        print_success "NGINX Gateway respondendo"
    else
        print_warning "NGINX Gateway não respondendo"
    fi
    
    # Testar Auth Service
    if kubectl exec -n $NAMESPACE deployment/frontend -- curl -f http://auth-service:8000/health --max-time 10 >/dev/null 2>&1; then
        print_success "Auth Service respondendo"
    else
        print_warning "Auth Service não respondendo"
    fi
    
    # Testar Catalog Service
    if kubectl exec -n $NAMESPACE deployment/frontend -- curl -f http://catalog-service:8000/health --max-time 10 >/dev/null 2>&1; then
        print_success "Catalog Service respondendo"
    else
        print_warning "Catalog Service não respondendo"
    fi
}

# Verificar distribuição pelos nós
check_node_distribution() {
    print_status "Verificando distribuição dos pods pelos nós..."
    
    echo -e "\n${YELLOW}📊 Distribuição por Nó:${NC}"
    kubectl get pods -n $NAMESPACE -o wide | awk '{print $1, $7}' | column -t
    
    echo -e "\n${YELLOW}📈 Utilização de Recursos:${NC}"
    kubectl top nodes 2>/dev/null || print_warning "Metrics server ainda não está pronto"
}

# Menu de funcionalidades
show_features() {
    echo -e "\n${GREEN}✅ Funcionalidades UALFlix Implementadas:${NC}"
    echo -e "${BLUE}FUNCIONALIDADE 1:${NC} Tecnologias de Sistemas Distribuídos"
    echo -e "  → Microserviços comunicando via APIs REST"
    echo -e "  → Processamento assíncrono com RabbitMQ"
    
    echo -e "\n${BLUE}FUNCIONALIDADE 2:${NC} Cluster de Computadores"
    echo -e "  → Kubernetes com $NODES nós"
    echo -e "  → Coordenação de recursos compartilhados"
    echo -e "  → Adição/remoção de nós sem interrupção"
    
    echo -e "\n${BLUE}FUNCIONALIDADE 3:${NC} Virtualização"
    echo -e "  → Containers Docker para isolamento"
    echo -e "  → Pods Kubernetes para orquestração"
    
    echo -e "\n${BLUE}FUNCIONALIDADE 4:${NC} Implementação na Cloud"
    echo -e "  → Deploy em ambiente Kubernetes"
    echo -e "  → Elasticidade automática (HPA)"
    
    echo -e "\n${BLUE}FUNCIONALIDADE 5:${NC} Replicação de Dados"
    echo -e "  → MongoDB Replica Set com 3 instâncias"
    echo -e "  → Estratégias síncrona e assíncrona"
    
    echo -e "\n${BLUE}FUNCIONALIDADE 6:${NC} Replicação de Serviços"
    echo -e "  → Múltiplas réplicas com Load Balancing"
    echo -e "  → NGINX como roteador principal"
    echo -e "  → Detecção de falhas e recuperação automática"
    
    echo -e "\n${BLUE}FUNCIONALIDADE 7:${NC} Avaliação de Desempenho"
    echo -e "  → Métricas com Prometheus"
    echo -e "  → Dashboards com Grafana"
    echo -e "  → Monitoramento de latência e throughput"
}

# Comandos úteis
show_useful_commands() {
    echo -e "\n${YELLOW}🔧 Comandos Úteis:${NC}"
    echo -e "${BLUE}Ver logs:${NC}"
    echo "  kubectl logs -f -n $NAMESPACE deployment/nginx-gateway"
    echo "  kubectl logs -f -n $NAMESPACE deployment/catalog-service"
    
    echo -e "\n${BLUE}Escalar serviços:${NC}"
    echo "  kubectl scale deployment catalog-service --replicas=5 -n $NAMESPACE"
    
    echo -e "\n${BLUE}Debug:${NC}"
    echo "  kubectl exec -it -n $NAMESPACE deployment/catalog-service -- /bin/bash"
    
    echo -e "\n${BLUE}Port forward:${NC}"
    echo "  kubectl port-forward -n $NAMESPACE service/nginx-gateway 8080:8080"
    
    echo -e "\n${BLUE}Monitoramento:${NC}"
    echo "  kubectl top nodes"
    echo "  kubectl top pods -n $NAMESPACE"
    
    echo -e "\n${BLUE}Dashboard:${NC}"
    echo "  minikube dashboard"
}

# Função principal
main() {
    echo -e "${PURPLE}Iniciando setup completo do UALFlix...${NC}\n"
    
    # Verificar argumentos
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        echo "Uso: $0 [opções]"
        echo "Opções:"
        echo "  --skip-build    Pular build das imagens"
        echo "  --help         Mostrar esta ajuda"
        exit 0
    fi
    
    # Executar passos
    check_prerequisites
    start_cluster
    enable_addons
    
    if [[ "$1" != "--skip-build" ]]; then
        build_images
    else
        print_warning "Pulando build das imagens (--skip-build)"
    fi
    
    deploy_application
    sleep 20  # Aguardar estabilização
    
    check_status
    check_node_distribution
    run_tests
    get_access_urls
    show_features
    show_useful_commands
    
    echo -e "\n${GREEN}🎉 Setup do UALFlix concluído com sucesso!${NC}"
    echo -e "${YELLOW}A aplicação está disponível em:${NC} $NGINX_URL"
    echo -e "${YELLOW}Para abrir no browser:${NC} minikube service nginx-gateway --namespace $NAMESPACE"
}

# Trap para limpeza em caso de interrupção
trap 'print_error "Setup interrompido"; exit 1' INT TERM

# Executar função principal
main "$@"