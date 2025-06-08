# PowerShell script for setting up Minikube registry on Windows

Write-Host "Configurando registry para cluster multi-no..." -ForegroundColor Blue

# Enable registry addon
minikube addons enable registry

# Get the registry port
$registryPort = "52652"

Write-Host "Aguardando registry ficar pronto..."
Start-Sleep -Seconds 10

# Forward the registry port
$job = Start-Process -FilePath "kubectl" -ArgumentList "port-forward", "-n", "kube-system", "service/registry", "$registryPort:5000" -PassThru -NoNewWindow

Write-Host "Registry configurado em localhost:$registryPort" -ForegroundColor Green

# Build and push images
Write-Host "Building e enviando imagens para registry local..." -ForegroundColor Blue

$services = @(
    "frontend",
    "authentication_service",
    "catalog_service",
    "streaming_service",
    "admin_service",
    "video_processor"
)

foreach ($service in $services) {
    $servicePath = Join-Path -Path $PSScriptRoot -ChildPath $service
    if (Test-Path $servicePath) {
        Write-Host "Building $service..."
        docker build -t "localhost:$registryPort/$service:latest" $servicePath
        docker push "localhost:$registryPort/$service:latest"
    } else {
        Write-Host "Directory not found: $servicePath" -ForegroundColor Yellow
    }
}

Write-Host "Todas as imagens no registry local!" -ForegroundColor Green

# Stop port forwarding if still running
if ($job -and (Get-Process -Id $job.Id -ErrorAction SilentlyContinue)) {
    Stop-Process -Id $job.Id
} 