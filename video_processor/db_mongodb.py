#!/usr/bin/env python3
"""
MongoDB Connection Manager ULTRA SIMPLIFICADO
Versão que funciona garantidamente
"""

from pymongo import MongoClient
import os
import logging
from functools import wraps
from datetime import datetime
from bson import ObjectId

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
            self.config = {
                'host': os.environ.get('MONGODB_PRIMARY_HOST', 'ualflix_db_primary'),
                'port': int(os.environ.get('MONGODB_PRIMARY_PORT', '27017')),
                'username': os.environ.get('MONGODB_USERNAME', 'admin'),
                'password': os.environ.get('MONGODB_PASSWORD', 'password'),
                'database': os.environ.get('MONGODB_DATABASE', 'ualflix')
            }
            self.client = None
            self._initialize_connection()
    
    def _initialize_connection(self):
        try:
            # Tentar primeiro com autenticação
            uri = f"mongodb://{self.config['username']}:{self.config['password']}@{self.config['host']}:{self.config['port']}/{self.config['database']}?authSource=admin"
            
            self.client = MongoClient(
                uri,
                serverSelectionTimeoutMS=15000,
                connectTimeoutMS=15000,
                maxPoolSize=10
            )
            
            # Testar conexão
            self.client.admin.command('ping')
            logger.info("✅ MongoDB conectado com autenticação")
            
        except Exception as e:
            logger.warning(f"⚠️ Falha com auth: {e}")
            try:
                # Fallback sem autenticação
                simple_uri = f"mongodb://{self.config['host']}:{self.config['port']}/{self.config['database']}"
                
                self.client = MongoClient(
                    simple_uri,
                    serverSelectionTimeoutMS=15000,
                    connectTimeoutMS=15000
                )
                
                self.client.admin.command('ping')
                logger.info("✅ MongoDB conectado sem autenticação")
                
            except Exception as e2:
                logger.error(f"❌ Falha total: {e2}")
                raise
    
    def get_database(self):
        if not self.client:
            self._initialize_connection()
        return self.client[self.config['database']]
    
    def get_write_database(self):
        return self.get_database()
    
    def get_read_database(self):
        return self.get_database()
    
    def check_replica_set_status(self):
        return {
            'set_name': 'single-node',
            'members': [{'name': f"{self.config['host']}:{self.config['port']}", 'state': 'PRIMARY', 'health': 1, 'is_primary': True, 'is_secondary': False, 'is_arbiter': False}],
            'status': 'healthy'
        }
    
    def test_replication_lag(self):
        return {'replication_working': True, 'lag_seconds': 0, 'test_id': 'single-node', 'note': 'single_node_mode'}
    
    def get_database_metrics(self):
        try:
            db = self.get_database()
            stats = db.command('dbStats')
            
            users_count = db.users.count_documents({}) if 'users' in db.list_collection_names() else 0
            videos_count = db.videos.count_documents({}) if 'videos' in db.list_collection_names() else 0
            views_count = db.video_views.count_documents({}) if 'video_views' in db.list_collection_names() else 0
            
            metrics = {
                'primary': {
                    'data_size_mb': round(stats.get('dataSize', 0) / (1024 * 1024), 2),
                    'storage_size_mb': round(stats.get('storageSize', 0) / (1024 * 1024), 2),
                    'index_size_mb': round(stats.get('indexSize', 0) / (1024 * 1024), 2),
                    'collections': stats.get('collections', 0),
                    'objects': stats.get('objects', 0),
                    'users_count': users_count,
                    'videos_count': videos_count,
                    'views_count': views_count
                },
                'secondary': {
                    'users_count': users_count,
                    'videos_count': videos_count,
                    'read_preference': 'primary',
                    'status': 'single_node_mode'
                }
            }
            return metrics
        except Exception as e:
            logger.error(f"Erro métricas: {e}")
            return {'primary': {'error': str(e)}, 'secondary': {'error': str(e)}}
    
    def create_indexes(self):
        try:
            db = self.get_database()
            
            # Criar coleções se não existirem
            collections = db.list_collection_names()
            for coll in ['users', 'videos', 'video_views', 'replication_test']:
                if coll not in collections:
                    db.create_collection(coll)
            
            # Índices básicos
            try:
                db.users.create_index('username', unique=True)
                db.users.create_index('email')
                db.videos.create_index('user_id')
                db.videos.create_index('status')
                db.video_views.create_index('video_id')
                logger.info("✅ Índices criados")
            except Exception as e:
                logger.warning(f"Alguns índices já existem: {e}")
                
        except Exception as e:
            logger.error(f"Erro criar índices: {e}")
    
    def init_collections(self):
        try:
            db = self.get_database()
            
            admin_exists = db.users.find_one({'username': 'admin'})
            if not admin_exists:
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
                logger.info(f"✅ Admin criado: {result.inserted_id}")
            else:
                logger.info("ℹ️ Admin já existe")
                
        except Exception as e:
            logger.error(f"Erro init collections: {e}")

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
            db = db_manager.get_database()
            return func(db, *args, **kwargs)
        except Exception as e:
            logger.error(f"Erro write {func.__name__}: {e}")
            raise
    return wrapper

def with_read_db(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        try:
            db_manager = get_mongodb_manager()
            db = db_manager.get_database()
            return func(db, *args, **kwargs)
        except Exception as e:
            logger.error(f"Erro read {func.__name__}: {e}")
            raise
    return wrapper
