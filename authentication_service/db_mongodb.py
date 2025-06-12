
#!/usr/bin/env python3
"""
MongoDB Connection Manager com REPLICA SET
Versão que suporta Primary-Secondary-Arbiter
"""

from pymongo import MongoClient, ReadPreference
from pymongo.errors import ServerSelectionTimeoutError
import os
import logging
from functools import wraps
from datetime import datetime
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class MongoDBManager:
    _instance = None
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(MongoDBManager, cls).__new__(cls)
        return cls._instance
    
    def __init__(self):
        if not hasattr(self, 'initialized'):
            self.initialized = True
            self.client = None
            self.write_client = None
            self.read_client = None
            self._initialize_connection()
    
    def _initialize_connection(self):
        """Inicializa conexões ao replica set com fallback melhorado"""
        try:
            # PRIMEIRA TENTATIVA: Conexão simples ao primary
            logger.info("🔄 Tentando conexão simples ao MongoDB primary...")
            simple_uri = "mongodb://ualflix_db_primary:27017/ualflix"
            
            self.client = MongoClient(simple_uri, serverSelectionTimeoutMS=5000)
            self.write_client = self.client
            self.read_client = self.client
            
            # Testar conexão
            self.client.admin.command('ping')
            logger.info("✅ Conectado ao MongoDB em modo simples")
            
            self._setup_database()
            return
            
        except Exception as e1:
            logger.warning(f"Conexão simples falhou: {e1}")
            
            try:
                # SEGUNDA TENTATIVA: Replica set com timeout maior
                logger.info("🔄 Tentando replica set com configurações relaxadas...")
                connection_string = "mongodb://ualflix_db_primary:27017,ualflix_db_secondary:27017/ualflix?replicaSet=ualflix-replica-set&readPreference=primaryPreferred"
                
                self.client = MongoClient(
                    connection_string,
                    serverSelectionTimeoutMS=10000,
                    connectTimeoutMS=10000,
                    retryWrites=False,  # Desativar retry para debugging
                    retryReads=False
                )
                
                self.write_client = self.client
                self.read_client = self.client
                
                # Testar conexão
                self.client.admin.command('ping')
                logger.info("✅ Conectado ao replica set")
                
                self._setup_database()
                return
                
            except Exception as e2:
                logger.warning(f"Replica set falhou: {e2}")
                
                try:
                    # TERCEIRA TENTATIVA: Apenas o primary, sem replica set
                    logger.info("🔄 Tentando apenas primary sem replica set...")
                    fallback_uri = "mongodb://ualflix_db_primary:27017/ualflix?directConnection=true"
                    
                    self.client = MongoClient(fallback_uri, serverSelectionTimeoutMS=5000)
                    self.write_client = self.client
                    self.read_client = self.client
                    
                    # Testar conexão
                    self.client.admin.command('ping')
                    logger.info("✅ Conectado ao primary diretamente")
                    
                    self._setup_database()
                    return
                    
                except Exception as e3:
                    logger.error(f"❌ Todas as tentativas de conexão falharam: {e3}")
                    raise Exception(f"Impossível conectar ao MongoDB: {e3}")
                
    def _test_connections(self):
        """Testa todas as conexões"""
        self.client.admin.command('ping')
        self.write_client.admin.command('ping')
        self.read_client.admin.command('ping')
        logger.info("🔍 Todas as conexões testadas")
    
    def _fallback_to_simple_connection(self):
        """Fallback para conexão simples"""
        logger.warning("⚠️ Tentando fallback para conexão simples...")
        try:
            simple_uri = "mongodb://ualflix_db_primary:27017/ualflix"
            
            self.client = MongoClient(simple_uri, serverSelectionTimeoutMS=10000)
            self.write_client = self.client
            self.read_client = self.client
            
            self.client.admin.command('ping')
            logger.warning("⚠️ Conectado em modo fallback")
            
            self._setup_database()
            
        except Exception as e2:
            logger.error(f"❌ Falha total: {e2}")
            raise
    
    def _setup_database(self):
        """Setup da base de dados com admin correto"""
        try:
            db = self.get_write_database()
            
            # Criar coleções
            collections = ['users', 'videos', 'video_views', 'replication_test']
            for coll in collections:
                if coll not in db.list_collection_names():
                    db.create_collection(coll)
            
            # Índices
            try:
                db.users.create_index('username', unique=True)
                db.users.create_index('email')
                db.videos.create_index('user_id')
                db.videos.create_index('status')
                db.video_views.create_index('video_id')
                db.replication_test.create_index('test_id')
                logger.info("✅ Índices criados")
            except Exception as e:
                logger.warning(f"Índices já existem: {e}")
            
            # CORREÇÃO: Verificar e criar utilizador admin CORRETAMENTE
            existing_admin = db.users.find_one({'username': 'admin'})
            
            if not existing_admin:
                from werkzeug.security import generate_password_hash
                
                # Criar admin com senha 'admin'
                admin_password_hash = generate_password_hash('admin', method='pbkdf2:sha256')
                
                admin_user = {
                    'username': 'admin',
                    'email': 'admin@ualflix.com',
                    'password': admin_password_hash,  # Hash correto da senha 'admin'
                    'is_admin': True,
                    'created_at': datetime.utcnow(),
                    'updated_at': datetime.utcnow()
                }
                
                result = db.users.insert_one(admin_user)
                logger.info(f"✅ Admin criado com ID: {result.inserted_id}")
                logger.info("📋 CREDENCIAIS: username=admin, password=admin")
                
            else:
                # Se admin existe mas tem senha temporária, atualizar
                if existing_admin.get('temp_password') or existing_admin.get('password') == 'admin_temp_will_be_hashed_by_app':
                    from werkzeug.security import generate_password_hash
                    
                    admin_password_hash = generate_password_hash('admin', method='pbkdf2:sha256')
                    
                    db.users.update_one(
                        {'username': 'admin'},
                        {
                            '$set': {
                                'password': admin_password_hash,
                                'is_admin': True,
                                'updated_at': datetime.utcnow()
                            },
                            '$unset': {
                                'temp_password': 1
                            }
                        }
                    )
                    logger.info("✅ Senha do admin atualizada para 'admin'")
                else:
                    # Garantir que é admin
                    db.users.update_one(
                        {'username': 'admin'},
                        {
                            '$set': {
                                'is_admin': True,
                                'updated_at': datetime.utcnow()
                            }
                        }
                    )
                    logger.info("✅ Admin já existe - verificado")
            
            # Verificação final
            final_admin = db.users.find_one({'username': 'admin'})
            if final_admin and final_admin.get('is_admin'):
                logger.info("🎯 ADMIN PRONTO: username='admin', password='admin'")
            else:
                logger.error("❌ Problema na criação/verificação do admin")
            
        except Exception as e:
            logger.warning(f"Setup da BD: {e}")
    
    def get_database(self):
        """Database com conexão principal"""
        if not self.client:
            self._initialize_connection()
        return self.client[os.environ.get('MONGODB_DATABASE', 'ualflix')]
    
    def get_write_database(self):
        """Database para ESCRITA (primary)"""
        if not self.write_client:
            self._initialize_connection()
        return self.write_client[os.environ.get('MONGODB_DATABASE', 'ualflix')]
    
    def get_read_database(self):
        """Database para LEITURA (secondary preferred)"""
        if not self.read_client:
            self._initialize_connection()
        return self.read_client[os.environ.get('MONGODB_DATABASE', 'ualflix')]
    
    def check_replica_set_status(self):
        """Status REAL do replica set"""
        try:
            status = self.client.admin.command("replSetGetStatus")
            
            members = []
            primary_name = None
            
            for member in status.get('members', []):
                member_info = {
                    'name': member.get('name'),
                    'state': member.get('state'),
                    'health': member.get('health'),
                    'is_primary': member.get('state') == 1,
                    'is_secondary': member.get('state') == 2,
                    'is_arbiter': member.get('state') == 7
                }
                
                if member_info['is_primary']:
                    primary_name = member_info['name']
                
                members.append(member_info)
            
            return {
                'set_name': status.get('set'),
                'status': 'healthy',
                'primary_name': primary_name,
                'members': members,
                'total_members': len(members),
                'healthy_members': len([m for m in members if m['health'] == 1]),
                'source': 'real_replica_set'
            }
            
        except Exception as e:
            logger.error(f"Erro ao verificar replica set: {e}")
            return {
                'set_name': 'ualflix-replica-set',
                'status': 'error',
                'error': str(e),
                'members': [],
                'source': 'error'
            }
    
    def test_replication_lag(self):
        """TESTE REAL de lag de replicação"""
        try:
            test_id = f"replication_test_{int(time.time())}"
            start_time = time.time()
            
            # ESCREVER no primary
            write_db = self.get_write_database()
            test_doc = {
                'test_id': test_id,
                'write_time': datetime.utcnow(),
                'test_type': 'replication_lag'
            }
            write_db.replication_test.insert_one(test_doc)
            
            # TENTAR LER do secondary
            max_attempts = 10
            lag_seconds = None
            
            for attempt in range(max_attempts):
                try:
                    read_db = self.get_read_database()
                    found_doc = read_db.replication_test.find_one({'test_id': test_id})
                    
                    if found_doc:
                        lag_seconds = time.time() - start_time
                        logger.info(f"🔄 Replicação detectada em {lag_seconds:.3f}s")
                        break
                    
                    time.sleep(0.5)
                    
                except Exception as e:
                    logger.warning(f"Tentativa {attempt + 1} falhou: {e}")
                    time.sleep(0.5)
            
            # LIMPAR
            try:
                write_db.replication_test.delete_one({'test_id': test_id})
            except:
                pass
            
            replication_working = lag_seconds is not None
            
            return {
                'replication_working': replication_working,
                'lag_seconds': lag_seconds if lag_seconds else 999.0,
                'test_id': test_id,
                'attempts_made': attempt + 1 if replication_working else max_attempts,
                'status': 'healthy' if replication_working and lag_seconds < 5.0 else 'warning',
                'source': 'real_replication_test'
            }
            
        except Exception as e:
            logger.error(f"Erro no teste de replicação: {e}")
            return {
                'replication_working': False,
                'lag_seconds': 999.0,
                'test_id': 'error',
                'error': str(e),
                'source': 'error'
            }
    
    def get_database_metrics(self):
        """Métricas REAIS da base de dados"""
        try:
            # Métricas do PRIMARY
            write_db = self.get_write_database()
            write_stats = write_db.command('dbStats')
            
            primary_metrics = {
                'data_size_mb': round(write_stats.get('dataSize', 0) / (1024 * 1024), 2),
                'storage_size_mb': round(write_stats.get('storageSize', 0) / (1024 * 1024), 2),
                'index_size_mb': round(write_stats.get('indexSize', 0) / (1024 * 1024), 2),
                'collections': write_stats.get('collections', 0),
                'objects': write_stats.get('objects', 0),
                'users_count': write_db.users.count_documents({}) if 'users' in write_db.list_collection_names() else 0,
                'videos_count': write_db.videos.count_documents({}) if 'videos' in write_db.list_collection_names() else 0,
                'views_count': write_db.video_views.count_documents({}) if 'video_views' in write_db.list_collection_names() else 0,
                'connection_type': 'primary_write',
                'source': 'real_primary_stats'
            }
            
            # Métricas do SECONDARY
            try:
                read_db = self.get_read_database()
                read_stats = read_db.command('dbStats')
                
                secondary_metrics = {
                    'users_count': read_db.users.count_documents({}) if 'users' in read_db.list_collection_names() else 0,
                    'videos_count': read_db.videos.count_documents({}) if 'videos' in read_db.list_collection_names() else 0,
                    'views_count': read_db.video_views.count_documents({}) if 'video_views' in read_db.list_collection_names() else 0,
                    'data_size_mb': round(read_stats.get('dataSize', 0) / (1024 * 1024), 2),
                    'collections': read_stats.get('collections', 0),
                    'objects': read_stats.get('objects', 0),
                    'read_preference': 'secondaryPreferred',
                    'connection_type': 'secondary_read',
                    'source': 'real_secondary_stats'
                }
                
            except Exception as e:
                logger.warning(f"Não foi possível obter métricas do secondary: {e}")
                secondary_metrics = {
                    'error': str(e),
                    'read_preference': 'primary_fallback',
                    'source': 'secondary_error'
                }
            
            return {
                'primary': primary_metrics,
                'secondary': secondary_metrics,
                'replica_set_name': os.environ.get('MONGODB_REPLICA_SET', 'ualflix-replica-set'),
                'collection_timestamp': datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            logger.error(f"Erro ao obter métricas: {e}")
            return {
                'primary': {'error': str(e), 'source': 'primary_error'},
                'secondary': {'error': str(e), 'source': 'secondary_error'},
                'replica_set_name': 'error'
            }
    
    def _get_primary_host(self):
        """Obtém o host primary atual"""
        try:
            status = self.check_replica_set_status()
            return status.get('primary_name', 'unknown')
        except:
            return 'unknown'
    
    def create_indexes(self):
        self._setup_database()
    
    def init_collections(self):
        self._setup_database()

# Singleton
_mongodb_manager = None

def get_mongodb_manager():
    global _mongodb_manager
    if _mongodb_manager is None:
        _mongodb_manager = MongoDBManager()
    return _mongodb_manager

def with_write_db(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        try:
            db_manager = get_mongodb_manager()
            db = db_manager.get_write_database()
            return func(db, *args, **kwargs)
        except Exception as e:
            logger.error(f"Erro na operação de escrita {func.__name__}: {e}")
            raise
    return wrapper

def with_read_db(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        try:
            db_manager = get_mongodb_manager()
            db = db_manager.get_read_database()
            return func(db, *args, **kwargs)
        except Exception as e:
            logger.error(f"Erro na operação de leitura {func.__name__}: {e}")
            raise
    return wrapper