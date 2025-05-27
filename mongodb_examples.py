"""
Exemplos de código para adaptar serviços UALFlix para MongoDB
Substitua as queries PostgreSQL por estas queries MongoDB
"""

from pymongo import MongoClient
from bson import ObjectId
from datetime import datetime
import bcrypt

# Conexão MongoDB
def get_mongodb_connection():
    client = MongoClient('mongodb://mongodb-service:27017/')
    db = client['ualflix']
    return db

# === AUTHENTICATION SERVICE ===

def authenticate_user_mongodb(username, password):
    """Autenticar usuário no MongoDB"""
    db = get_mongodb_connection()
    
    # Buscar usuário
    user = db.users.find_one({'username': username})
    if not user:
        return None
    
    # Verificar password (assumindo bcrypt)
    if bcrypt.checkpw(password.encode('utf-8'), user['password'].encode('utf-8')):
        return {
            'id': str(user['_id']),
            'username': user['username'],
            'email': user['email'],
            'is_admin': user.get('is_admin', False)
        }
    return None

def create_user_mongodb(username, email, password, is_admin=False):
    """Criar novo usuário no MongoDB"""
    db = get_mongodb_connection()
    
    # Hash da password
    hashed_password = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
    
    user_doc = {
        'username': username,
        'email': email,
        'password': hashed_password.decode('utf-8'),
        'is_admin': is_admin,
        'created_at': datetime.now(),
        'updated_at': datetime.now()
    }
    
    result = db.users.insert_one(user_doc)
    return str(result.inserted_id)

# === CATALOG SERVICE ===

def create_video_mongodb(title, description, filename, url, user_id):
    """Criar novo vídeo no MongoDB"""
    db = get_mongodb_connection()
    
    video_doc = {
        'title': title,
        'description': description,
        'filename': filename,
        'url': url,
        'duration': 0,
        'file_path': f'/videos/{filename}',
        'thumbnail_path': None,
        'upload_date': datetime.now(),
        'view_count': 0,
        'status': 'active',
        'user_id': ObjectId(user_id)
    }
    
    result = db.videos.insert_one(video_doc)
    return str(result.inserted_id)

def get_videos_mongodb(user_id=None, limit=50):
    """Listar vídeos do MongoDB"""
    db = get_mongodb_connection()
    
    query = {}
    if user_id:
        query['user_id'] = ObjectId(user_id)
    
    # Aggregation para incluir informações do usuário
    pipeline = [
        {'$match': query},
        {'$lookup': {
            'from': 'users',
            'localField': 'user_id',
            'foreignField': '_id',
            'as': 'user_info'
        }},
        {'$sort': {'upload_date': -1}},
        {'$limit': limit}
    ]
    
    videos = []
    for video in db.videos.aggregate(pipeline):
        user_info = video.get('user_info', [{}])[0]
        videos.append({
            'id': str(video['_id']),
            'title': video['title'],
            'description': video['description'],
            'filename': video['filename'],
            'url': video['url'],
            'upload_date': video['upload_date'].isoformat(),
            'view_count': video['view_count'],
            'uploaded_by': user_info.get('username', 'Unknown')
        })
    
    return videos

def get_video_by_id_mongodb(video_id):
    """Buscar vídeo por ID no MongoDB"""
    db = get_mongodb_connection()
    
    pipeline = [
        {'$match': {'_id': ObjectId(video_id)}},
        {'$lookup': {
            'from': 'users',
            'localField': 'user_id',
            'foreignField': '_id',
            'as': 'user_info'
        }}
    ]
    
    result = list(db.videos.aggregate(pipeline))
    if not result:
        return None
    
    video = result[0]
    user_info = video.get('user_info', [{}])[0]
    
    return {
        'id': str(video['_id']),
        'title': video['title'],
        'description': video['description'],
        'filename': video['filename'],
        'url': video['url'],
        'upload_date': video['upload_date'].isoformat(),
        'view_count': video['view_count'],
        'uploaded_by': user_info.get('username', 'Unknown')
    }

def increment_view_count_mongodb(video_id, user_id=None):
    """Incrementar contador de visualizações"""
    db = get_mongodb_connection()
    
    # Incrementar view_count do vídeo
    db.videos.update_one(
        {'_id': ObjectId(video_id)},
        {'$inc': {'view_count': 1}}
    )
    
    # Registrar visualização
    view_doc = {
        'video_id': ObjectId(video_id),
        'user_id': ObjectId(user_id) if user_id else None,
        'view_date': datetime.now(),
        'watch_duration': 0  # Pode ser atualizado posteriormente
    }
    
    db.video_views.insert_one(view_doc)

# === ADMIN SERVICE ===

def get_system_stats_mongodb():
    """Obter estatísticas do sistema"""
    db = get_mongodb_connection()
    
    stats = {
        'total_users': db.users.count_documents({}),
        'total_videos': db.videos.count_documents({}),
        'total_views': db.video_views.count_documents({}),
        'active_videos': db.videos.count_documents({'status': 'active'}),
        'admin_users': db.users.count_documents({'is_admin': True})
    }
    
    # Top vídeos mais vistos
    top_videos = list(db.videos.find(
        {'status': 'active'}, 
        {'title': 1, 'view_count': 1}
    ).sort('view_count', -1).limit(5))
    
    stats['top_videos'] = [
        {
            'title': video['title'],
            'views': video['view_count']
        } for video in top_videos
    ]
    
    return stats

# === QUERIES DE EXEMPLO PARA SUBSTITUIR SQL ===

# PostgreSQL: SELECT * FROM users WHERE username = %s
# MongoDB:#!/bin/bash

# UALFlix Kubernetes MongoDB Structure Generator
# Migração para MongoDB + Estrutura Profissional

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️ $1${NC}"; }
print_header() { echo -e "${PURPLE}��� $1${NC}"; }
print_success() { echo -e "${CYAN}��� $1${NC}"; }

echo -e "${PURPLE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${PURPLE}��� UALFlix Kubernetes + MongoDB Professional Structure${NC}"
echo -e "${PURPLE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Verificar pré-requisitos
if [[ ! -f "docker-compose.yml" ]] || [[ ! -d "catalog_service" ]]; then
    print_error "Execute este script no diretório raiz do projeto UALFlix"
    exit 1
fi

print_status "Projeto UALFlix detectado"

# Limpar estrutura existente
if [[ -d "k8s" ]]; then
    print_warning "Pasta k8s/ existente será substituída"
    read -p "Continuar? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Operação cancelada"
        exit 0
    fi
    rm -rf k8s/
fi

# Criar estrutura profissional
print_info "Criando estrutura Kubernetes profissional..."

mkdir -p k8s/{database,messaging,services/{catalog,streaming,admin,auth,processor},frontend,monitoring/{prometheus,grafana},ingress}

print_status "Estrutura de pastas criada"

# 1. NAMESPACE.YAML
print_info "Criando namespace.yaml..."

cat > k8s/namespace.yaml << 'EOF'
# NAMESPACE - Isolamento do projeto UALFlix
apiVersion: v1
kind: Namespace
metadata:
  name: ualflix
  labels:
    project: ualflix-streaming
    academic: "true"
    version: v2.0
    database: mongodb
    description: "Sistema de Streaming com MongoDB - Projeto Acadêmico"
