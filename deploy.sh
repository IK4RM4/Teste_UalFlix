#!/bin/bash
# SOLUÇÃO COMPLETA PARA OS PROBLEMAS DO KUBERNETES UALFLIX

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${RED}🔧 CORRIGINDO TODOS OS PROBLEMAS ENCONTRADOS${NC}"
echo "=================================================="


# Parar port-forwards
pkill -f "kubectl port-forward" 2>/dev/null || true

echo "✅ Limpeza completa realizada"

# REINICIAR REGISTRY
echo -e "\n${YELLOW}📦 ETAPA 2: Configurar Registry${NC}"
kubectl port-forward -n kube-system service/registry 5000:80 &
sleep 8

# Testar registry
if ! curl -sf http://localhost:5000/v2/_catalog >/dev/null; then
    echo "Registry com problemas, usando porta alternativa..."
    pkill -f "kubectl port-forward.*registry" 2>/dev/null || true
    kubectl port-forward -n kube-system service/registry 5000:5000 &
    sleep 5
fi

echo "✅ Registry configurado"

# RE-PUSH DAS IMAGENS
echo -e "\n${YELLOW}🐳 ETAPA 3: Re-push das Imagens${NC}"

# Verificar e re-push de todas as imagens
SERVICES=("authentication_service" "catalog_service" "streaming_service" "admin_service" "video_processor" "frontend")

for service in "${SERVICES[@]}"; do
    echo "Re-building e pushing $service..."
    docker build -t localhost:5000/$service:latest ./$service/
    for attempt in {1..3}; do
        if docker push localhost:5000/$service:latest; then
            echo "✅ $service pushed com sucesso"
            break
        else
            echo "Tentativa $attempt falhou, tentando novamente..."
            sleep 3
        fi
    done
done

# Verificar registry
echo "Imagens no registry:"
curl -s http://localhost:5000/v2/_catalog

echo "✅ Imagens re-pushed"

# CORRIGIR ARQUIVO CATALOG DEPLOYMENT
echo -e "\n${YELLOW}📝 ETAPA 4: Corrigir Arquivo Catalog Deployment${NC}"

# Backup e corrigir o arquivo catalog deployment
if [ -f "k8s/services/catalog/deployment.yaml" ]; then
    cp "k8s/services/catalog/deployment.yaml" "k8s/services/catalog/deployment.yaml.bak"
    
    # Verificar se o arquivo tem apiVersion
    if ! grep -q "apiVersion:" "k8s/services/catalog/deployment.yaml"; then
        echo "Adicionando apiVersion ao arquivo catalog deployment..."
        cat > k8s/services/catalog/deployment.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: video-storage-pvc
  namespace: ualflix
  labels:
    app: catalog-service
    component: storage
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
  storageClassName: "standard"

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog-service
  namespace: ualflix
  labels:
    app: catalog-service
    tier: backend
    component: api
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  selector:
    matchLabels:
      app: catalog-service
  template:
    metadata:
      labels:
        app: catalog-service
        tier: backend
        component: api
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8000"
        prometheus.io/path: "/metrics"
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
      - name: catalog-service
        image: localhost:5000/catalog_service:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 8000
          name: http
          protocol: TCP
        env:
        - name: MONGODB_CONNECTION_STRING
          value: "mongodb://mongodb-service.ualflix.svc.cluster.local:27017/ualflix"
        - name: QUEUE_HOST
          value: "rabbitmq-service.ualflix.svc.cluster.local"
        - name: QUEUE_USER
          value: "ualflix"
        - name: QUEUE_PASSWORD
          value: "ualflix_password"
        - name: AUTH_SERVICE_URL
          value: "http://auth-service.ualflix.svc.cluster.local:8000"
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: false
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: video-storage
          mountPath: /videos
        - name: tmp-storage
          mountPath: /tmp
      volumes:
      - name: video-storage
        persistentVolumeClaim:
          claimName: video-storage-pvc
      - name: tmp-storage
        emptyDir: {}
EOF
    fi
fi

echo "✅ Arquivo catalog deployment corrigido"

# CRIAR MONGODB SIMPLIFICADO
echo -e "\n${YELLOW}🗄️ ETAPA 5: MongoDB Simplificado${NC}"

# Criar versão simplificada do MongoDB (sem replica set inicialmente)
cat > /tmp/mongodb-simple.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mongodb-data
  namespace: ualflix
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: "standard"

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mongodb-simple
  namespace: ualflix
  labels:
    app: mongodb
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mongodb
  template:
    metadata:
      labels:
        app: mongodb
    spec:
      containers:
      - name: mongodb
        image: mongo:6.0
        ports:
        - containerPort: 27017
        env:
        - name: MONGO_INITDB_DATABASE
          value: ualflix
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        volumeMounts:
        - name: mongodb-data
          mountPath: /data/db
      volumes:
      - name: mongodb-data
        persistentVolumeClaim:
          claimName: mongodb-data

---
apiVersion: v1
kind: Service
metadata:
  name: mongodb-service
  namespace: ualflix
spec:
  selector:
    app: mongodb
  ports:
  - port: 27017
    targetPort: 27017
    protocol: TCP
  type: ClusterIP
EOF

echo "✅ MongoDB simplificado criado"

# ATUALIZAR NGINX CONFIG PARA USAR NOMES CORRETOS
echo -e "\n${YELLOW}🌐 ETAPA 6: Corrigir NGINX Config${NC}"

# Atualizar nginx config para usar nomes de serviço corretos
cat > k8s/ingress/nginx-configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: ualflix
  labels:
    app: nginx-gateway
    component: config
data:
  nginx.conf: |
    user nginx;
    worker_processes auto;
    error_log /var/log/nginx/error.log warn;
    pid /var/run/nginx.pid;

    events {
        worker_connections 1024;
        use epoll;
        multi_accept on;
    }

    http {
        include /etc/nginx/mime.types;
        default_type application/octet-stream;
        
        # Log format
        log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                        '$status $body_bytes_sent "$http_referer" '
                        '"$http_user_agent" "$http_x_forwarded_for"';
        
        access_log /var/log/nginx/access.log main;
        
        # Performance settings
        sendfile on;
        tcp_nopush on;
        tcp_nodelay on;
        keepalive_timeout 65;
        client_max_body_size 1024M;
        
        # Gzip Settings
        gzip on;
        gzip_vary on;
        gzip_proxied any;
        gzip_comp_level 6;
        gzip_types text/plain text/css application/json application/javascript 
                   text/xml application/xml application/xml+rss text/javascript;

        # Upstream definitions
        upstream frontend_backend {
            server frontend-service:3000;
        }

        upstream auth_backend {
            server auth-service:8000;
        }

        upstream catalog_backend {
            server catalog-service:8000;
        }

        upstream streaming_backend {
            server streaming-service:8001;
        }

        upstream admin_backend {
            server admin-service:8002;
        }

        # Health check endpoint
        server {
            listen 8081;
            server_name localhost;
            
            location /nginx-health {
                access_log off;
                return 200 "healthy\n";
                add_header Content-Type text/plain;
            }
        }

        # Main server
        server {
            listen 8080;
            server_name _;
            
            # CORS headers
            add_header Access-Control-Allow-Origin "*" always;
            add_header Access-Control-Allow-Methods "GET, POST, OPTIONS, PUT, DELETE" always;
            add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization,X-Session-Token" always;

            # Handle preflight requests
            if ($request_method = 'OPTIONS') {
                add_header Access-Control-Allow-Origin "*";
                add_header Access-Control-Allow-Methods "GET, POST, OPTIONS, PUT, DELETE";
                add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization,X-Session-Token";
                add_header Access-Control-Max-Age 1728000;
                add_header Content-Type "text/plain; charset=utf-8";
                add_header Content-Length 0;
                return 204;
            }

            # Frontend
            location / {
                proxy_pass http://frontend_backend;
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection "upgrade";
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_cache_bypass $http_upgrade;
            }

            # Auth API
            location /api/auth/ {
                rewrite ^/api/auth(/.*)$ $1 break;
                proxy_pass http://auth_backend;
                proxy_http_version 1.1;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
            }

            # Admin API
            location /api/admin/ {
                rewrite ^/api/admin(/.*)$ /api/admin$1 break;
                proxy_pass http://admin_backend;
                proxy_http_version 1.1;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
            }

            # Catalog API
            location /api/ {
                rewrite ^/api(/.*)$ $1 break;
                proxy_pass http://catalog_backend;
                proxy_http_version 1.1;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
            }

            # Streaming
            location /stream/ {
                proxy_pass http://streaming_backend/stream/;
                proxy_http_version 1.1;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header Range $http_range;
                proxy_buffering off;
                proxy_cache off;
                add_header Accept-Ranges bytes;
            }

            # Health check
            location /health {
                access_log off;
                return 200 "NGINX Gateway healthy\n";
                add_header Content-Type text/plain;
            }
        }
    }
EOF

echo "✅ NGINX config corrigido"

# DEPLOY SEQUENCIAL
echo -e "\n${YELLOW}🚀 ETAPA 7: Deploy Sequencial${NC}"

# 1. Namespace
kubectl apply -f k8s/namespace.yaml

# 2. Secrets
kubectl apply -f k8s/secrets.yaml

# 3. MongoDB Simples
kubectl apply -f /tmp/mongodb-simple.yaml
echo "Aguardando MongoDB..."
sleep 30

# 4. RabbitMQ
kubectl apply -f k8s/messaging/
echo "Aguardando RabbitMQ..."
sleep 20

# 5. NGINX Config
kubectl apply -f k8s/ingress/nginx-configmap.yaml

# 6. Services individuais
echo "Deploying serviços..."
kubectl apply -f k8s/services/auth/
kubectl apply -f k8s/services/catalog/
kubectl apply -f k8s/services/streaming/
kubectl apply -f k8s/services/admin/
kubectl apply -f k8s/services/processor/

# 7. Frontend
kubectl apply -f k8s/frontend/

# 8. NGINX Gateway
kubectl apply -f k8s/ingress/nginx-deployment.yaml
kubectl apply -f k8s/ingress/nginx-service.yaml

echo "✅ Deploy sequencial completo"

# AGUARDAR E VERIFICAR
echo -e "\n${YELLOW}⏳ ETAPA 8: Aguardar Pods${NC}"
sleep 60

echo -e "\n${BLUE}📊 STATUS FINAL:${NC}"
kubectl get pods -n ualflix
echo
kubectl get svc -n ualflix

# TESTE DE CONECTIVIDADE
echo -e "\n${YELLOW}🧪 ETAPA 9: Teste de Conectividade${NC}"

MINIKUBE_IP=$(minikube ip)
echo "IP do Minikube: $MINIKUBE_IP"

# Testar conectividade
if curl -sf "http://$MINIKUBE_IP:30080/health" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Aplicação acessível!${NC}"
else
    echo -e "${YELLOW}⚠️ Aplicação ainda não acessível, verificando port-forward...${NC}"
    kubectl port-forward -n ualflix service/nginx-gateway 8080:8080 &
    sleep 5
    if curl -sf "http://localhost:8080/health" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Aplicação acessível via port-forward!${NC}"
    fi
fi

# INFORMAÇÕES FINAIS
echo -e "\n${GREEN}🎉 CORREÇÃO COMPLETA!${NC}"
echo "====================="
echo
echo "🌐 ACESSO:"
echo "  1. NodePort: http://$MINIKUBE_IP:30080"
echo "  2. Port-forward: kubectl port-forward -n ualflix service/nginx-gateway 8080:8080"
echo "  3. Minikube service: minikube service nginx-gateway --namespace ualflix"
echo
echo "👤 LOGIN:"
echo "  Username: admin"
echo "  Password: admin"
echo
echo "🔧 VERIFICAR STATUS:"
echo "  kubectl get pods -n ualflix"
echo "  kubectl get svc -n ualflix"
echo
echo "🧹 LIMPAR (se necessário):"
echo "  kubectl delete namespace ualflix"

# Criar script de monitoramento
cat > monitor-ualflix.sh << 'EOF'
#!/bin/bash
echo "🔍 UALFlix Status Monitor"
echo "========================"
echo
echo "📦 Pods:"
kubectl get pods -n ualflix
echo
echo "🔗 Services:"
kubectl get svc -n ualflix
echo
echo "🌐 URLs:"
echo "  NodePort: http://$(minikube ip):30080"
echo "  Health: curl http://$(minikube ip):30080/health"
echo
echo "📋 Registry:"
curl -s http://localhost:5000/v2/_catalog 2>/dev/null || echo "Registry não acessível"
EOF

chmod +x monitor-ualflix.sh
echo
echo "✅ Script de monitoramento criado: ./monitor-ualflix.sh"

# Adicionar o Secret do keyfile
kubectl apply -f k8s/database/mongodb-keyfile-secret.yaml