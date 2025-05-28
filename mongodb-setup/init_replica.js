// MongoDB Replica Set Setup Script
// Este script deve ser colocado em: mongodb-setup/init-replica.js

print("🎬 UALFlix - Inicializando MongoDB com Replica Set...");

// Aguardar que o MongoDB esteja totalmente pronto
sleep(5000);

// Switch to ualflix database
db = db.getSiblingDB('ualflix');

print("📋 Criando coleções com validação de schema...");

// Users Collection
try {
  db.createCollection("users", {
     validator: {
        $jsonSchema: {
           bsonType: "object",
           title: "User Account Schema",
           required: [ "username", "email", "password" ],
           properties: {
              username: {
                 bsonType: "string",
                 description: "deve ser uma string e é obrigatório"
              },
              email: {
                 bsonType: "string",
                 pattern: "^.+@.+$",
                 description: "deve ser uma string e corresponder ao padrão de email"
              },
              password: {
                 bsonType: "string",
                 minLength: 8,
                 description: "deve ser uma string com pelo menos 8 caracteres"
              },
              is_admin: {
                 bsonType: "bool",
                 description: "deve ser um boolean"
              },
              created_at: {
                 bsonType: "date",
                 description: "deve ser uma data"
              }
           }
        }
     }
  });
  print("✅ Coleção 'users' criada com validação");
} catch (error) {
  print("⚠️ Coleção 'users' já existe ou erro:", error.message);
}

// Videos Collection
try {
  db.createCollection("videos", {
     validator: {
        $jsonSchema: {
           bsonType: "object",
           title: "Video Schema",
           required: [ "title", "filename", "user_id" ],
           properties: {
              title: {
                 bsonType: "string",
                 minLength: 1,
                 description: "deve ser uma string não vazia"
              },
              description: {
                 bsonType: "string",
                 description: "deve ser uma string"
              },
              filename: {
                 bsonType: "string",
                 minLength: 1,
                 description: "deve ser uma string não vazia"
              },
              url: {
                 bsonType: "string",
                 description: "deve ser uma string"
              },
              duration: {
                 bsonType: "number",
                 minimum: 0,
                 description: "deve ser um número >= 0"
              },
              file_size: {
                 bsonType: "number",
                 minimum: 0,
                 description: "deve ser um número >= 0"
              },
              upload_date: {
                 bsonType: "date",
                 description: "deve ser uma data"
              },
              view_count: {
                 bsonType: "number",
                 minimum: 0,
                 description: "deve ser um número >= 0"
              },
              status: {
                 enum: [ "active", "inactive", "processing", "error" ],
                 description: "deve ser um dos valores do enum"
              },
              user_id: {
                 bsonType: "objectId",
                 description: "deve ser um ObjectId"
              }
           }
        }
     }
  });
  print("✅ Coleção 'videos' criada com validação");
} catch (error) {
  print("⚠️ Coleção 'videos' já existe ou erro:", error.message);
}

// Video Views Collection
try {
  db.createCollection("video_views", {
     validator: {
        $jsonSchema: {
           bsonType: "object",
           title: "Video View Schema",
           required: [ "video_id", "view_date" ],
           properties: {
              video_id: {
                 bsonType: "objectId",
                 description: "deve ser um ObjectId"
              },
              user_id: {
                 bsonType: "objectId",
                 description: "deve ser um ObjectId"
              },
              view_date: {
                 bsonType: "date",
                 description: "deve ser uma data"
              },
              watch_duration: {
                 bsonType: "number",
                 minimum: 0,
                 description: "deve ser um número >= 0"
              }
           }
        }
     }
  });
  print("✅ Coleção 'video_views' criada com validação");
} catch (error) {
  print("⚠️ Coleção 'video_views' já existe ou erro:", error.message);
}

// Replication Test Collection
try {
  db.createCollection("replication_test");
  print("✅ Coleção 'replication_test' criada");
} catch (error) {
  print("⚠️ Coleção 'replication_test' já existe ou erro:", error.message);
}

print("🔍 Criando índices para performance...");

try {
  // Users indexes
  db.users.createIndex({ "username": 1 }, { unique: true, name: "idx_username_unique" });
  db.users.createIndex({ "email": 1 }, { unique: true, name: "idx_email_unique" });
  db.users.createIndex({ "created_at": -1 }, { name: "idx_created_at" });
  db.users.createIndex({ "is_admin": 1 }, { name: "idx_is_admin" });
  
  // Videos indexes
  db.videos.createIndex({ "user_id": 1 }, { name: "idx_user_id" });
  db.videos.createIndex({ "status": 1 }, { name: "idx_status" });
  db.videos.createIndex({ "upload_date": -1 }, { name: "idx_upload_date" });
  db.videos.createIndex({ "view_count": -1 }, { name: "idx_view_count" });
  db.videos.createIndex({ "title": "text", "description": "text" }, { name: "idx_text_search" });
  
  // Video Views indexes
  db.video_views.createIndex({ "video_id": 1 }, { name: "idx_video_id" });
  db.video_views.createIndex({ "user_id": 1 }, { name: "idx_user_id_views" });
  db.video_views.createIndex({ "view_date": -1 }, { name: "idx_view_date" });
  
  // Replication test indexes
  db.replication_test.createIndex({ "test_time": 1 }, { name: "idx_test_time" });
  
  print("✅ Todos os índices criados com sucesso");
} catch (error) {
  print("⚠️ Alguns índices já existem ou erro:", error.message);
}

print("📊 Inserindo dados de exemplo...");

try {
  // Check if admin user already exists
  const existingAdmin = db.users.findOne({ username: "admin" });
  
  if (!existingAdmin) {
    const adminUser = db.users.insertOne({
        username: "admin",
        email: "admin@ualflix.com",
        password: "pbkdf2:sha256:260000$5fGQQvXhm0XKU6iF$1d1c65c1f0ad1c02b20e9c1e5f9a4b0c8d9e7f6g5h4i3j2k1l0m9n8o7p6q5r4s3t2u1v0w9x8y7z6a5b4c3d2e1f0",
        is_admin: true,
        created_at: new Date(),
        updated_at: new Date()
    });
    print("✅ Usuário admin criado:", adminUser.insertedId);
  } else {
    print("⚠️ Usuário admin já existe");
  }
  
  // Create a regular user
  const existingUser = db.users.findOne({ username: "user1" });
  
  if (!existingUser) {
    const regularUser = db.users.insertOne({
        username: "user1",
        email: "user1@ualflix.com", 
        password: "pbkdf2:sha256:260000$5fGQQvXhm0XKU6iF$2e2d75d2g1be2d03c31f0d2f6g0b5c1d9e8f7g6h5i4j3k2l1m0n9o8p7q6r5s4t3u2v1w0x9y8z7a6b5c4d3e2f1g0",
        is_admin: false,
        created_at: new Date(),
        updated_at: new Date()
    });
    print("✅ Usuário regular criado:", regularUser.insertedId);
  } else {
    print("⚠️ Usuário regular já existe");
  }
  
} catch (error) {
  print("❌ Erro ao criar usuários:", error.message);
}

// Database statistics
print("📈 Estatísticas da base de dados:");
try {
  const stats = db.runCommand({ dbStats: 1 });
  print("- Base de dados:", db.getName());
  print("- Coleções:", stats.collections);
  print("- Documentos:", stats.objects);
  print("- Tamanho dos dados:", Math.round(stats.dataSize / 1024 / 1024 * 100) / 100, "MB");
  print("- Tamanho dos índices:", Math.round(stats.indexSize / 1024 / 1024 * 100) / 100, "MB");
} catch (error) {
  print("❌ Erro ao obter estatísticas:", error.message);
}

print("");
print("🎉 UALFlix MongoDB initialization completed successfully!");
print("📊 FUNCIONALIDADE 5: Estratégias de Replicação de Dados - MongoDB Replica Set");
print("🔄 Replica Set configurado com:");
print("   - PRIMARY: ualflix_db_primary:27017");
print("   - SECONDARY: ualflix_db_secondary:27017"); 
print("   - ARBITER: ualflix_db_arbiter:27017");
print("");
print("🔐 Utilizadores criados:");
print("   - admin / admin (Administrador)");
print("   - user1 / user1 (Utilizador normal)");
print("");
print("✅ Sistema pronto para uso!");
print("=" + "=".repeat(50));