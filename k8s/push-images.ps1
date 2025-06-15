# Script para fazer tag e push das imagens para o registry local
$REGISTRY = "localhost:5000"

# Lista de serviços
$SERVICES = @(
    "ualflix-authentication_service",
    "ualflix-catalog_service",
    "ualflix-video_processor",
    "ualflix-admin_service",
    "ualflix-streaming_service",
    "ualflix-frontend"
)

# Para cada serviço
foreach ($SERVICE in $SERVICES) {
    Write-Host "Processando $SERVICE..."
    
    # Tag da imagem
    docker tag ${SERVICE}:latest ${REGISTRY}/${SERVICE}:latest
    
    # Push da imagem
    docker push ${REGISTRY}/${SERVICE}:latest
    
    Write-Host "Imagem $SERVICE processada com sucesso!"
}

Write-Host "Todas as imagens foram processadas!" 