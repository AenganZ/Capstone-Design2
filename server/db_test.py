# migrate_db.py (새 파일 생성)
import sqlite3

conn = sqlite3.connect('missing_persons.db')
cursor = conn.cursor()

# 기존 테이블 백업
cursor.execute('''
    CREATE TABLE IF NOT EXISTS missing_persons_backup AS 
    SELECT * FROM missing_persons
''')

# 새 테이블 생성 (phi_entities 사용)
cursor.execute('''
    CREATE TABLE missing_persons_new (
        id TEXT PRIMARY KEY,
        name TEXT,
        age INTEGER,
        gender TEXT,
        location TEXT,
        description TEXT,
        photo_url TEXT,
        photo_base64 TEXT,
        priority TEXT,
        risk_factors TEXT,
        phi_entities TEXT,  -- 변경됨!
        extracted_features TEXT,
        lat REAL,
        lng REAL,
        created_at TEXT,
        updated_at TEXT,
        status TEXT,
        category TEXT,
        source TEXT DEFAULT 'SAFE182',
        confidence_score REAL,
        last_seen TEXT,
        clothing_description TEXT,
        medical_condition TEXT,
        emergency_contact TEXT,
        approval_status TEXT DEFAULT 'PENDING',
        rejection_reason TEXT
    )
''')

# 데이터 복사 (ner_entities → phi_entities)
cursor.execute('''
    INSERT INTO missing_persons_new 
    SELECT id, name, age, gender, location, description, photo_url, photo_base64,
           priority, risk_factors, ner_entities, extracted_features, lat, lng,
           created_at, updated_at, status, category, source, confidence_score,
           last_seen, clothing_description, medical_condition, emergency_contact,
           approval_status, rejection_reason
    FROM missing_persons
''')

# 기존 테이블 삭제
cursor.execute('DROP TABLE missing_persons')

# 새 테이블 이름 변경
cursor.execute('ALTER TABLE missing_persons_new RENAME TO missing_persons')

conn.commit()
conn.close()

print("마이그레이션 완료!")