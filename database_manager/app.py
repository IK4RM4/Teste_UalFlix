#!/usr/bin/env python3
"""
MongoDB Database Manager - Gestão de Replica Set e Replicação
FUNCIONALIDADE 5: Estratégias de Replicação de Dados (MongoDB)
FUNCIONALIDADE 2: Implementação de Cluster (MongoDB Replica Set)
"""

from pymongo import MongoClient, ReadPreference, WriteConcern
from pymongo.errors import ServerSelectionTimeoutError, ConnectionFailure
import os
import logging
import time
from functools import wraps
from datetime import datetime
import threading
from bson import ObjectId

# Configuração de logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class MongoDBManager:
    """Gerenciador de conexões MongoDB com suporte a Replica Set"""
    
    def __init__(self):
        self.primary_config = {
            'host': os.environ.get('MONGODB_PRIMARY_HOST', 'ualflix_db_primary'),
            'port': int(os.environ.get('MONGODB_PRIMARY_PORT', '27017')),
            'username': os.environ.get('MONGODB_USERNAME', 'admin'),
            'password': os.environ.get('MONGODB_PASSWORD', 'password'),
            'database': os.environ.get('MONGODB_DATABASE', 'ualflix'),
            'replica_set': os.environ.get('MONGODB_REPLICA_SET', 'ualflix-replica-set')
        }
        
        self.secondary_config = {
            'host': os.environ.get('MONGODB_SECONDARY_HOST', 'ualflix_db_secondary'),
            'port': int(os.environ.get('MONGODB_SECONDARY_PORT', '27018')),
            'username': os.environ.get('MONGODB_USERNAME', 'admin'),
            'password': os.environ.get('MONGODB_PASSWORD', 'password'),
            'database': os.environ.get('MONGODB_DATABASE', 'ualflix'),
            'replica_set': os.environ.get('MONGODB_REPLICA_SET', 'ualflix-replica-set')
        }
        
        # Clients para diferentes tipos de operações
        self.write_client = None
        self.read_client = None
        self.replica_set_client = None
        
        self._initialize_connections()
    
    def _build_connection_uri(self, config, read_preference=None):
        """Constrói URI de conexão MongoDB"""
        uri = f"mongodb://{config['username']}:{config['password']}@{config['host']}:{config['port']}/{config['database']}"
        
        params = []
        if config.get('replica_set'):
            params.append(f"replicaSet={config['replica_set']}")
        
        if read_preference:
            params.append(f"readPreference={read_preference}")
        
        params.append("authSource=admin")
        
        if params:
            uri += "?" + "&".join(params)
        
        return uri
    
    def _initialize_connections(self):
        """Inicializa as conexões MongoDB"""
        try:
            # Cliente para escritas (PRIMARY)
            write_uri = self._build_connection_uri(self.primary_config)
            self.write_client = MongoClient(
                write_uri,
                serverSelectionTimeoutMS=5000,
                connectTimeoutMS=5000,
                w='majority',  # Write concern
                j=True,        # Journal
                readPreference='primary'
            )
            
            # Cliente para leituras (SECONDARY PREFERRED)
            read_uri = self._build_connection_uri(self.secondary_config, 'secondaryPreferred')
            self.read_client = MongoClient(
                read_uri,
                serverSelectionTimeoutMS=5000,
                connectTimeoutMS=5000,
                readPreference='secondaryPreferred'
            )
            
            # Cliente para replica set completo
            replica_hosts = f"{self.primary_config['host']}:{self.primary_config['port']},{self.secondary_config['host']}:{self.secondary_config['port']}"
            replica_uri = f"mongodb://{self.primary_config['username']}:{self.primary_config['password']}@{replica_hosts}/{self.primary_config['database']}?replicaSet={self.primary_config['replica_set']}&authSource=admin"
            
            self.replica_set_client = MongoClient(
                replica_uri,
                serverSelectionTimeoutMS=10000,
                connectTimeoutMS=10000
            )
            
            logger.info("✅ Conexões MongoDB inicializadas")
            self._test_connections()
            
        except Exception as e:
            logger.error(f"❌ Erro ao inicializar conexões MongoDB: {e}")
            raise
    
    def _test_connections(self):
        """Testa as conexões MongoDB"""
        try:
            # Test write connection
            self.write_client.admin.command('ping')
            logger.info("✅ Conexão de escrita (PRIMARY) OK")
            
            # Test read connection
            self.read_client.admin.command('ping')
            logger.info("✅ Conexão de leitura (SECONDARY) OK")
            
            # Test replica set
            self.replica_set_client.admin.command('ping')
            logger.info("✅ Conexão Replica Set OK")
            
        except Exception as e:
            logger.warning(f"⚠️ Teste de conexão falhou: {e}")
    
    def get_write_database(self):
        """Retorna database para operações de escrita (PRIMARY)"""
        if not self.write_client:
            self._initialize_connections()
        return self.write_client[self.primary_config['database']]
    
    def get_read_database(self):
        """Retorna database para operações de leitura (SECONDARY PREFERRED)"""
        if not self.read_client:
            self._initialize_connections()
        return self.read_client[self.secondary_config['database']]
    
    def get_replica_database(self):
        """Retorna database com acesso ao replica set completo"""
        if not self.replica_set_client:
            self._initialize_connections()
        return self.replica_set_client[self.primary_config['database']]
    
    def check_replica_set_status(self):
        """Verifica status do replica set"""
        try:
            db = self.get_replica_database()
            status = db.command('replSetGetStatus')
            
            members = []
            for member in status.get('members', []):
                members.append({
                    'name': member.get('name'),
                    'state': member.get('stateStr'),
                    'health': member.get('health'),
                    'is_primary': member.get('stateStr') == 'PRIMARY',
                    'is_secondary': member.get('stateStr') == 'SECONDARY',
                    'is_arbiter': member.get('stateStr') == 'ARBITER',
                    'last_heartbeat': member.get('lastHeartbeat'),
                    'ping_ms': member.get('pingMs', 0)
                })
            
            return {
                'set_name': status.get('set'),
                'date': status.get('date'),
                'primary_name': next((m['name'] for m in members if m['is_primary']), None),
                'members': members,
                'status': 'healthy' if len([m for m in members if m['health'] == 1]) >= 2 else 'degraded'
            }
            
        except Exception as e:
            logger.error(f"Erro ao verificar status do replica set: {e}")
            return {'status': 'error', 'error': str(e)}
    
    def test_replication_lag(self):
        """Testa lag de replicação"""
        try:
            # Escrever no primary
            write_db = self.get_write_database()
            test_doc = {
                'test_time': datetime.utcnow(),
                'test_data': f'Replication test {int(time.time())}',
                'type': 'replication_test'
            }
            
            result = write_db.replication_test.insert_one(test_doc)
            test_id = result.inserted_id
            
            # Aguardar um pouco
            time.sleep(1)
            
            # Ler do secondary
            read_db = self.get_read_database()
            found_doc = read_db.replication_test.find_one({'_id': test_id})
            
            if found_doc:
                lag_seconds = (datetime.utcnow() - found_doc['test_time']).total_seconds()
                
                # Limpar teste
                write_db.replication_test.delete_one({'_id': test_id})
                
                return {
                    'replication_working': True,
                    'lag_seconds': lag_seconds,
                    'test_id': str(test_id)
                }
            else:
                return {
                    'replication_working': False,
                    'message': 'Document not found on secondary'
                }
                
        except Exception as e:
            logger.error(f"Erro no teste de replicação: {e}")
            return {'error': str(e)}
    
    def get_database_metrics(self):
        """Obtém métricas das bases de dados"""
        metrics = {}
        
        try:
            # Primary metrics
            write_db = self.get_write_database()
            
            # Estatísticas gerais
            stats = write_db.command('dbStats')
            
            # Contagens das coleções
            users_count = write_db.users.count_documents({})
            videos_count = write_db.videos.count_documents({})
            views_count = write_db.video_views.count_documents({})
            
            metrics['primary'] = {
                'data_size_mb': round(stats.get('dataSize', 0) / (1024 * 1024), 2),
                'storage_size_mb': round(stats.get('storageSize', 0) / (1024 * 1024), 2),
                'index_size_mb': round(stats.get('indexSize', 0) / (1024 * 1024), 2),
                'collections': stats.get('collections', 0),
                'objects': stats.get('objects', 0),
                'users_count': users_count,
                'videos_count': videos_count,
                'views_count': views_count
            }
            
        except Exception as e:
            logger.error(f"Erro ao obter métricas primary: {e}")
            metrics['primary'] = {'error': str(e)}
        
        try:
            # Secondary metrics
            read_db = self.get_read_database()
            
            # Verificar se consegue ler do secondary
            users_count_secondary = read_db.users.count_documents({})
            videos_count_secondary = read_db.videos.count_documents({})
            
            metrics['secondary'] = {
                'users_count': users_count_secondary,
                'videos_count': videos_count_secondary,
                'read_preference': 'secondaryPreferred',
                'status': 'accessible'
            }
            
        except Exception as e:
            logger.error(f"Erro ao obter métricas secondary: {e}")
            metrics['secondary'] = {'error': str(e)}
        
        return metrics
    
    def create_indexes(self):
        """Cria índices necessários"""
        try:
            db = self.get_write_database()
            
            # Índices para users
            db.users.create_index('username', unique=True)
            db.users.create_index('email')
            db.users.create_index('created_at')
            
            # Índices para videos
            db.videos.create_index('title')
            db.videos.create_index('user_id')
            db.videos.create_index('upload_date')
            db.videos.create_index('status')
            db.videos.create_index([('title', 'text'), ('description', 'text')])
            
            # Índices para video_views
            db.video_views.create_index('video_id')
            db.video_views.create_index('user_id')
            db.video_views.create_index('view_date')
            db.video_views.create_index([('video_id', 1), ('user_id', 1)])
            
            logger.info("✅ Índices MongoDB criados")
            
        except Exception as e:
            logger.error(f"Erro ao criar índices: {e}")
    
    def init_collections(self):
        """Inicializa coleções com dados básicos"""
        try:
            db = self.get_write_database()
            
            # Verificar se admin já existe
            admin_exists = db.users.find_one({'username': 'admin'})
            
            if not admin_exists:
                # Criar usuário admin
                from werkzeug.security import generate_password_hash
                
                admin_user = {
                    'username': 'admin',
                    'email': 'admin@ualflix.com',
                    'password': generate_password_hash('admin'),
                    'is_admin': True,
                    'created_at': datetime.utcnow(),
                    'updated_at': datetime.utcnow()
                }
                
                result = db.users.insert_one(admin_user)
                logger.info(f"✅ Usuário admin criado: {result.inserted_id}")
            
            logger.info("✅ Coleções inicializadas")
            
        except Exception as e:
            logger.error(f"Erro ao inicializar coleções: {e}")
    
    def close_connections(self):
        """Fecha todas as conexões"""
        try:
            if self.write_client:
                self.write_client.close()
            if self.read_client:
                self.read_client.close()
            if self.replica_set_client:
                self.replica_set_client.close()
            
            logger.info("✅ Conexões MongoDB fechadas")
            
        except Exception as e:
            logger.error(f"Erro ao fechar conexões: {e}")

# Decorators para gestão de conexões
def with_write_db(func):
    """Decorator para operações de escrita"""
    @wraps(func)
    def wrapper(*args, **kwargs):
        try:
            db_manager = MongoDBManager()
            db = db_manager.get_write_database()
            return func(db, *args, **kwargs)
        except Exception as e:
            logger.error(f"Erro na operação de escrita {func.__name__}: {e}")
            raise
    return wrapper

def with_read_db(func):
    """Decorator para operações de leitura"""
    @wraps(func)
    def wrapper(*args, **kwargs):
        try:
            db_manager = MongoDBManager()
            db = db_manager.get_read_database()
            return func(db, *args, **kwargs)
        except Exception as e:
            logger.error(f"Erro na operação de leitura {func.__name__}: {e}")
            # Fallback para primary se secondary falhar
            logger.warning("Tentando fallback para primary...")
            db = db_manager.get_write_database()
            return func(db, *args, **kwargs)
    return wrapper
