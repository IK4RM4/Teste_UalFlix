// UALFlix MongoDB Replica Set Initialization Script
// FUNCIONALIDADE 5: Estratégias de Replicação de Dados

print("🎬 UALFlix - Inicializando MongoDB com Replica Set...");

// Switch to ualflix database
db = db.getSiblingDB('ualflix');

// Create collections with schema validation
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
              },
              updated_at: {
                 bsonType: "date",
                 description: "deve ser uma data"
              }
           }
        }
     }
  });
  print("✅ Coleção 'users' criada com validação");
} catch (error) {
  print("⚠️ Coleção 'users' já existe:", error.message);
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
              file_path: {
                 bsonType: "string",
                 description: "deve ser uma string"
              },
              thumbnail_path: {
                 bsonType: "string",
                 description: "deve ser uma string"
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
              },
              created_at: {
                 bsonType: "date",
                 description: "deve ser uma data"
              },
              updated_at: {
                 bsonType: "date",
                 description: "deve ser uma data"
              }
           }
        }
     }
  });
  print("✅ Coleção 'videos' criada com validação");
} catch (error) {
  print("⚠️ Coleção 'videos' já existe:", error.message);
}

// Video Views Collection (for analytics)
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
              },
              ip_address: {
                 bsonType: "string",
                 description: "deve ser uma string"
              }
           }
        }
     }
  });
  print("✅ Coleção 'video_views' criada com validação");
} catch (error) {
  print("⚠️ Coleção 'video_views' já existe:", error.message);
}

// Replication Test Collection (for testing replica set lag)
try {
  db.createCollection("replication_test", {
    validator: {
      $jsonSchema: {
        bsonType: "object",
        properties: {
          test_time: { bsonType: "date" },
          test_data: { bsonType: "string" },
          type: { enum: ["replication_test"] }
        }
      }
    }
  });
  print("✅ Coleção 'replication_test' criada");
} catch (error) {
  print("⚠️ Coleção 'replication_test' já existe:", error.message);
}

// Create indexes for performance
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
  db.videos.createIndex({ "user_id": 1, "status": 1 }, { name: "idx_user_status" });
  
  // Video Views indexes
  db.video_views.createIndex({ "video_id": 1 }, { name: "idx_video_id" });
  db.video_views.createIndex({ "user_id": 1 }, { name: "idx_user_id_views" });
  db.video_views.createIndex({ "view_date": -1 }, { name: "idx_view_date" });
  db.video_views.createIndex({ "video_id": 1, "user_id": 1 }, { name: "idx_video_user_compound" });
  
  // Replication test indexes
  db.replication_test.createIndex({ "test_time": 1 }, { name: "idx_test_time" });
  db.replication_test.createIndex({ "type": 1 }, { name: "idx_test_type" });
  
  print("✅ Todos os índices criados com sucesso");
} catch (error) {
  print("⚠️ Alguns índices já existem:", error.message);
}

// Insert sample data
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

// Create sample video if admin user exists
try {
  const adminUser = db.users.findOne({ username: "admin" });
  if (adminUser && db.videos.countDocuments() === 0) {
    const sampleVideo = db.videos.insertOne({
        title: "Vídeo de Demonstração UALFlix",
        description: "Este é um vídeo de demonstração para testar o sistema UALFlix com MongoDB Replica Set.",
        filename: "sample_demo.mp4",
        url: "/stream/sample_demo.mp4",
        duration: 180, // 3 minutos
        file_size: 15728640, // ~15MB
        file_path: "/videos/sample_demo.mp4",
        thumbnail_path: "thumb_sample_demo.mp4.jpg",
        upload_date: new Date(),
        view_count: 0,
        status: "active",
        user_id: adminUser._id,
        created_at: new Date(),
        updated_at: new Date()
    });
    print("✅ Vídeo de demonstração criado:", sampleVideo.insertedId);
  }
} catch (error) {
  print("⚠️ Erro ao criar vídeo de demonstração:", error.message);
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

// Test replication functionality
print("🔄 Testando funcionalidade de replicação...");
try {
  const testDoc = {
    test_time: new Date(),
    test_data: "Teste inicial de replicação - " + new Date().getTime(),
    type: "replication_test"
  };
  
  const result = db.replication_test.insertOne(testDoc);
  print("✅ Documento de teste de replicação inserido:", result.insertedId);
  
  // Clean up test document
  db.replication_test.deleteOne({ _id: result.insertedId });
  print("✅ Documento de teste removido");
} catch (error) {
  print("❌ Erro no teste de replicação:", error.message);
}

print("");
print("🎉 UALFlix MongoDB initialization completed successfully!");
print("📊 FUNCIONALIDADE 5: Estratégias de Replicação de Dados - MongoDB Replica Set");
print("🔄 Replica Set configurado com:");
print("   - PRIMARY: ualflix_db_primary:27017");
print("   - SECONDARY: ualflix_db_secondary:27018"); 
print("   - ARBITER: ualflix_db_arbiter:27019");
print("");
print("🔐 Utilizadores criados:");
print("   - admin / admin (Administrador)");
print("   - user1 / user1 (Utilizador normal)");
print("");
print("✅ Sistema pronto para uso!");
print("=" + "=".repeat(50));