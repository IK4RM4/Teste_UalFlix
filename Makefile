# Variáveis
NAMESPACE=ualflix

# Iniciar Minikube
start:
	minikube start --driver=docker --cpus=2 --memory=4096

# Construir imagens localmente dentro do Minikube
build:
	minikube -p minikube docker-env | Invoke-Expression; \
	docker build -t catalog_service:latest ./catalog_service; \
	docker build -t streaming_service:latest ./streaming_service; \
	docker build -t authentication_service:latest ./authentication_service; \
	docker build -t admin_service:latest ./admin_service; \
	docker build -t frontend:latest ./frontend; \
	docker build -t video_processor:latest ./video_processor


# Aplicar namespace e todos os recursos
apply:
	kubectl apply -f k8s/namespace.yaml
	kubectl config set-context --current --namespace=$(NAMESPACE)
	kubectl apply -f k8s/

# Aceder ao serviço do NGINX no browser
open:
	minikube service nginx-service --namespace=$(NAMESPACE)

# Ver pods
status:
	kubectl get pods -n $(NAMESPACE)

# Remover todos os recursos
clean:
	kubectl delete -f k8s/

# Reiniciar tudo (minikube + apply)
rebuild: clean build apply
