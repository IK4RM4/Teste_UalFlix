#!/usr/bin/env python3
"""
Script de Migra√ß√£o PostgreSQL -> MongoDB para UALFlix
Migra dados existentes do PostgreSQL para MongoDB
"""

import psycopg2
import pymongo
from datetime import datetime
import os
import sys

# Configura√ß√µes PostgreSQL (origem)
PG_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'ualflix',
    'user': 'postgres',
    'password': 'password'
}

# Configura√ß√µes MongoDB (destino)
MONGO_URI = "mongodb://localhost:27017/"
MONGO_DB = "ualflix"

def connect_postgresql():
    """Conecta ao PostgreSQL"""
    try:
        conn = psycopg2.connect(**PG_CONFIG)
        return conn
    except Exception as e:
        print(f"Erro ao conectar PostgreSQL: {e}")
        return None

def connect_mongodb():
    """Conecta ao MongoDB"""
    try:
        client = pymongo.MongoClient(MONGO_URI)
        db = client[MONGO_DB]
        return client, db
    except Exception as e:
        print(f"Erro ao conectar MongoDB: {e}")
        return None, None

def migrate_users(pg_conn, mongo_db):
    """Migra tabela users para collection users"""
    print("Ì¥Ñ Migrando utilizadores...")
    
    cursor = pg_conn.cursor()
    cursor.execute("SELECT id, username, email, password, is_admin, created_at FROM users")
    
    users = []
    for row in cursor.fetchall():
        user = {
            'pg_id': row[0],  # Manter ID original para refer√™ncias
            'username': row[1],
            'email': row[2],
            'password': row[3],
            'is_admin': row[4] if row[4] is not None else False,
            'created_at': row[5] if row[5] else datetime.now(),
            'updated_at': datetime.now()
        }
        users.append(user)
    
    if users:
        result = mongo_db.users.insert_many(users)
        print(f"‚úÖ {len(result.inserted_ids)} utilizadores migrados")
        return {user['pg_id']: user_id for user, user_id in zip(users, result.inserted_ids)}
    
    return {}

def migrate_videos(pg_conn, mongo_db, user_mapping):
    """Migra tabela videos para collection videos"""
    print("Ì¥Ñ Migrando v√≠deos...")
    
    cursor = pg_conn.cursor()
    cursor.execute("""
        SELECT id, title, description, filename, url, duration, 
               file_path, thumbnail_path, upload_date, view_count, 
               status, user_id 
        FROM videos
    """)
    
    videos = []
    for row in cursor.fetchall():
        # Mapear user_id do PostgreSQL para ObjectId do MongoDB
        mongo_user_id = user_mapping.get(row[11]) if row[11] else None
        
        video = {
            'pg_id': row[0],
            'title': row[1],
            'description': row[2] if row[2] else '',
            'filename': row[3],
            'url': row[4],
            'duration': row[5] if row[5] else 0,
            'file_path': row[6],
            'thumbnail_path': row[7],
            'upload_date': row[8] if row[8] else datetime.now(),
            'view_count': row[9] if row[9] else 0,
            'status': row[10] if row[10] else 'active',
            'user_id': mongo_user_id
        }
        videos.append(video)
    
    if videos:
        result = mongo_db.videos.insert_many(videos)
        print(f"‚úÖ {len(result.inserted_ids)} v√≠deos migrados")
        return {video['pg_id']: video_id for video, video_id in zip(videos, result.inserted_ids)}
    
    return {}

def migrate_video_views(pg_conn, mongo_db, user_mapping, video_mapping):
    """Migra tabela video_views para collection video_views"""
    print("Ì¥Ñ Migrando visualiza√ß√µes...")
    
    cursor = pg_conn.cursor()
    cursor.execute("""
        SELECT id, video_id, user_id, view_date, watch_duration 
        FROM video_views
    """)
    
    views = []
    for row in cursor.fetchall():
        mongo_user_id = user_mapping.get(row[2]) if row[2] else None
        mongo_video_id = video_mapping.get(row[1]) if row[1] else None
        
        if mongo_video_id:  # S√≥ migrar se o v√≠deo existe
            view = {
                'pg_id': row[0],
                'video_id': mongo_video_id,
                'user_id': mongo_user_id,
                'view_date': row[3] if row[3] else datetime.now(),
                'watch_duration': row[4] if row[4] else 0
            }
            views.append(view)
    
    if views:
        result = mongo_db.video_views.insert_many(views)
        print(f"‚úÖ {len(result.inserted_ids)} visualiza√ß√µes migradas")

def main():
    print("Ìæ¨ UALFlix - Migra√ß√£o PostgreSQL -> MongoDB")
    print("=" * 50)
    
    # Conectar √†s bases de dados
    pg_conn = connect_postgresql()
    if not pg_conn:
        print("‚ùå Falha na conex√£o PostgreSQL")
        sys.exit(1)
    
    mongo_client, mongo_db = connect_mongodb()
    if not mongo_db:
        print("‚ùå Falha na conex√£o MongoDB")
        sys.exit(1)
    
    try:
        # Limpar collections MongoDB (opcional)
        print("ÔøΩÔøΩ Limpando collections MongoDB...")
        mongo_db.users.delete_many({})
        mongo_db.videos.delete_many({})
        mongo_db.video_views.delete_many({})
        
        # Executar migra√ß√µes
        user_mapping = migrate_users(pg_conn, mongo_db)
        video_mapping = migrate_videos(pg_conn, mongo_db, user_mapping)
        migrate_video_views(pg_conn, mongo_db, user_mapping, video_mapping)
        
        print("\n‚úÖ Migra√ß√£o conclu√≠da com sucesso!")
        print(f"Ì≥ä Utilizadores: {len(user_mapping)}")
        print(f"Ì≥ä V√≠deos: {len(video_mapping)}")
        
        # Verificar dados migrados
        print("\nÌ≥ã Verifica√ß√£o final:")
        print(f"Users no MongoDB: {mongo_db.users.count_documents({})}")
        print(f"Videos no MongoDB: {mongo_db.videos.count_documents({})}")
        print(f"Views no MongoDB: {mongo_db.video_views.count_documents({})}")
        
    except Exception as e:
        print(f"‚ùå Erro durante migra√ß√£o: {e}")
        sys.exit(1)
    
    finally:
        pg_conn.close()
        mongo_client.close()

if __name__ == "__main__":
    main()
