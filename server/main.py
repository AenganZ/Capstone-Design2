import os
import time
import json
import sqlite3
import asyncio
import httpx
import re
import base64
from datetime import datetime, timedelta
from contextlib import asynccontextmanager
from typing import List, Dict, Any, Optional, Union

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect, Body, Query, Depends
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field, validator
from dotenv import load_dotenv

load_dotenv()

SAFE182_ESNTL_ID = os.getenv("SAFE182_ESNTL_ID", "")
SAFE182_AUTH_KEY = os.getenv("SAFE182_AUTH_KEY", "")
KAKAO_API_KEY = os.getenv("KAKAO_API_KEY")
KAKAO_JAVASCRIPT_KEY = os.getenv("KAKAO_JAVASCRIPT_KEY")
FIREBASE_CREDENTIALS = os.getenv("FIREBASE_CREDENTIALS", "./firebase_key.json")
NER_SERVER_URL = os.getenv("NER_SERVER_URL", "http://localhost:8000")
ITS_CCTV_API_KEY = os.getenv("ITS_CCTV_API_KEY", "")
OPENWEATHER_API_KEY = os.getenv("OPENWEATHER_API_KEY", "")

class MissingPerson(BaseModel):
    id: str
    name: Optional[str] = None
    age: Optional[int] = None
    gender: Optional[str] = None
    location: Optional[str] = None
    description: Optional[str] = None
    photo_url: Optional[str] = None
    photo_base64: Optional[str] = None
    priority: str = "MEDIUM"
    risk_factors: List[str] = []
    ner_entities: Dict[str, List[str]] = {}
    extracted_features: Dict[str, List[str]] = {}
    lat: float = 36.3504
    lng: float = 127.3845
    created_at: str = ""
    status: str = "ACTIVE"
    category: Optional[str] = None
    updated_at: Optional[str] = None
    source: str = "SAFE182"
    confidence_score: Optional[float] = None
    last_seen: Optional[str] = None
    clothing_description: Optional[str] = None
    medical_condition: Optional[str] = None
    emergency_contact: Optional[str] = None

class FCMTokenRequest(BaseModel):
    token: str
    driver_id: str
    driver_name: Optional[str] = None
    platform: str = "flutter"
    device_info: Optional[str] = None
    location: Optional[Dict[str, float]] = None

class ReportRequest(BaseModel):
    person_id: str
    reporter_location: Dict[str, float]
    description: str
    photo_base64: Optional[str] = None
    reporter_id: Optional[str] = None
    confidence_level: str = "HIGH"
    timestamp: Optional[str] = None

class CCTVRequest(BaseModel):
    lat: float
    lng: float
    radius: int = 1000
    cctv_type: Optional[str] = None

class NotificationRequest(BaseModel):
    person_id: str
    message: str
    priority: str = "MEDIUM"
    target_tokens: List[str] = []
    test_mode: bool = False

class AnalyticsRequest(BaseModel):
    start_date: str
    end_date: str
    filters: Optional[Dict[str, Any]] = {}

class WeatherRequest(BaseModel):
    lat: float
    lng: float

class BatchUpdateRequest(BaseModel):
    person_ids: List[str]
    updates: Dict[str, Any]

class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []
        self.connection_info: Dict[WebSocket, Dict] = {}
    
    async def connect(self, websocket: WebSocket, client_type: str = "admin"):
        await websocket.accept()
        self.active_connections.append(websocket)
        self.connection_info[websocket] = {
            "type": client_type,
            "connected_at": datetime.now().isoformat(),
            "last_ping": datetime.now().isoformat()
        }
        print(f"{client_type} 연결됨. 총 {len(self.active_connections)}명")
    
    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)
            if websocket in self.connection_info:
                del self.connection_info[websocket]
        print(f"연결 해제됨. 총 {len(self.active_connections)}명")
    
    async def broadcast(self, message: dict, client_type: str = None):
        if not self.active_connections:
            return
        
        disconnected = []
        for connection in self.active_connections:
            try:
                if client_type and self.connection_info.get(connection, {}).get("type") != client_type:
                    continue
                await connection.send_text(json.dumps(message, ensure_ascii=False))
            except:
                disconnected.append(connection)
        
        for conn in disconnected:
            self.disconnect(conn)
    
    async def send_personal_message(self, websocket: WebSocket, message: dict):
        try:
            await websocket.send_text(json.dumps(message, ensure_ascii=False))
        except:
            self.disconnect(websocket)
    
    def get_connection_stats(self):
        admin_count = sum(1 for info in self.connection_info.values() if info.get("type") == "admin")
        driver_count = sum(1 for info in self.connection_info.values() if info.get("type") == "driver")
        return {"admin": admin_count, "driver": driver_count, "total": len(self.active_connections)}

class OptimizedAPIManager:
    def __init__(self):
        self.last_request_time = 0
        self.min_interval = 300
        self.cache_duration = 3600
        self.cached_data = {}
        self.cache_timestamp = 0
        self.request_count = 0
        self.error_count = 0
        
    def should_make_request(self) -> bool:
        current_time = time.time()
        return (current_time - self.last_request_time) >= self.min_interval
    
    def get_cached_data(self):
        current_time = time.time()
        if self.cached_data and (current_time - self.cache_timestamp) < self.cache_duration:
            return self.cached_data
        return None
    
    def update_cache(self, data):
        self.cached_data = data
        self.cache_timestamp = time.time()
        self.last_request_time = time.time()
        self.request_count += 1
    
    def record_error(self):
        self.error_count += 1
    
    def get_stats(self):
        return {
            "total_requests": self.request_count,
            "error_count": self.error_count,
            "success_rate": ((self.request_count - self.error_count) / max(self.request_count, 1)) * 100,
            "last_request": datetime.fromtimestamp(self.last_request_time).isoformat() if self.last_request_time else None,
            "cache_age": time.time() - self.cache_timestamp if self.cache_timestamp else 0
        }

firebase_admin = None
firebase_messaging = None

async def init_firebase():
    global firebase_admin, firebase_messaging
    
    if not FIREBASE_CREDENTIALS:
        print("FIREBASE_CREDENTIALS 환경변수가 설정되지 않았습니다")
        print(".env 파일에 FIREBASE_CREDENTIALS=./firebase_key.json 추가하세요")
        return False
    
    if not os.path.exists(FIREBASE_CREDENTIALS):
        print(f"Firebase 키 파일을 찾을 수 없습니다: {FIREBASE_CREDENTIALS}")
        print("Firebase Console에서 서비스 계정 키를 다운로드하세요")
        return False
    
    try:
        import firebase_admin
        from firebase_admin import credentials, messaging
        
        try:
            existing_app = firebase_admin.get_app()
            firebase_admin.delete_app(existing_app)
            print("기존 Firebase 앱 삭제됨")
        except ValueError:
            pass
        
        cred = credentials.Certificate(FIREBASE_CREDENTIALS)
        app = firebase_admin.initialize_app(cred)
        firebase_messaging = messaging
        
        with open(FIREBASE_CREDENTIALS, 'r') as f:
            data = json.load(f)
        
        print("Firebase 초기화 성공")
        print(f"프로젝트 ID: {data.get('project_id', 'Unknown')}")
        print(f"클라이언트 이메일: {data.get('client_email', 'Unknown')}")
        
        return True
        
    except Exception as e:
        print(f"Firebase 초기화 실패: {e}")
        print("다음을 확인하세요:")
        print("1. firebase_key.json 파일이 유효한지")
        print("2. Firebase 프로젝트가 활성화되어 있는지")
        print("3. 서비스 계정에 적절한 권한이 있는지")
        return False

@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_database()
    firebase_initialized = await init_firebase()
    
    if firebase_initialized:
        print("Firebase 사용 가능")
    else:
        print("Firebase 사용 불가 - FCM 기능 제한됨")
    
    await check_ner_server()
    await init_background_tasks()
    
    polling_task = asyncio.create_task(start_optimized_polling())
    cleanup_task = asyncio.create_task(cleanup_old_data())
    analytics_task = asyncio.create_task(update_analytics())
    
    yield
    
    polling_task.cancel()
    cleanup_task.cancel()
    analytics_task.cancel()

app = FastAPI(
    title="실종자 요청 처리 시스템", 
    description="대전 이동 안전망 시스템 - 실종자 관리 및 알림 서비스",
    version="2.0.0",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

manager = ConnectionManager()
api_manager = OptimizedAPIManager()

SAFE_URL = "https://www.safe182.go.kr/api/lcm/amberList.do"
KAKAO_GEO = "https://dapi.kakao.com/v2/local/search/address.json"
ITS_CCTV_URL = "https://www.its.go.kr/opendata/bizdata/safdriveInfoSvc"
WEATHER_URL = "https://api.openweathermap.org/data/2.5/weather"

async def check_ner_server():
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(f"{NER_SERVER_URL}/api/health")
            if response.status_code == 200:
                print("NER 서버 연결 확인됨")
                return True
    except Exception as e:
        print(f"NER 서버 연결 실패: {e}")
        print("ner_server.py를 먼저 실행해주세요")
    return False

async def init_background_tasks():
    print("백그라운드 작업 초기화 중...")
    await create_indexes()
    await migrate_legacy_data()
    print("백그라운드 작업 초기화 완료")

async def create_indexes():
    conn = sqlite3.connect('missing_persons.db')
    cursor = conn.cursor()
    
    try:
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_missing_persons_status ON missing_persons(status)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_missing_persons_priority ON missing_persons(priority)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_missing_persons_created_at ON missing_persons(created_at)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_fcm_tokens_active ON fcm_tokens(active)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_notifications_sent_at ON notifications(sent_at)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_sighting_reports_reported_at ON sighting_reports(reported_at)')
        print("데이터베이스 인덱스 생성 완료")
    except Exception as e:
        print(f"인덱스 생성 오류: {e}")
    
    conn.commit()
    conn.close()

async def migrate_legacy_data():
    print("레거시 데이터 마이그레이션 확인 중...")

async def init_database():
    conn = sqlite3.connect('missing_persons.db')
    cursor = conn.cursor()
    
    cursor.execute("PRAGMA table_info(missing_persons)")
    columns = [column[1] for column in cursor.fetchall()]
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS missing_persons (
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
            ner_entities TEXT,
            extracted_features TEXT,
            lat REAL,
            lng REAL,
            created_at TEXT,
            updated_at TEXT,
            status TEXT DEFAULT 'ACTIVE',
            category TEXT,
            source TEXT DEFAULT 'SAFE182',
            confidence_score REAL,
            last_seen TEXT,
            clothing_description TEXT,
            medical_condition TEXT,
            emergency_contact TEXT
        )
    ''')
    
    new_columns = [
        ('photo_base64', 'TEXT'),
        ('extracted_features', 'TEXT'),
        ('category', 'TEXT'),
        ('updated_at', 'TEXT'),
        ('source', 'TEXT DEFAULT "SAFE182"'),
        ('confidence_score', 'REAL'),
        ('last_seen', 'TEXT'),
        ('clothing_description', 'TEXT'),
        ('medical_condition', 'TEXT'),
        ('emergency_contact', 'TEXT')
    ]
    
    for column_name, column_type in new_columns:
        if column_name not in columns:
            try:
                cursor.execute(f'ALTER TABLE missing_persons ADD COLUMN {column_name} {column_type}')
                print(f"{column_name} 컬럼이 추가되었습니다.")
            except sqlite3.OperationalError as e:
                if "duplicate column name" not in str(e):
                    raise e
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS api_requests (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            request_time TEXT,
            endpoint TEXT,
            method TEXT,
            result_count INTEGER,
            success INTEGER,
            response_time REAL,
            error_message TEXT
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS fcm_tokens (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            token TEXT UNIQUE,
            user_id TEXT,
            driver_name TEXT,
            platform TEXT,
            device_info TEXT,
            registered_at TEXT,
            last_active TEXT,
            is_test INTEGER DEFAULT 0,
            active INTEGER DEFAULT 1,
            location_lat REAL,
            location_lng REAL
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            person_id TEXT,
            message TEXT,
            priority TEXT,
            sent_at TEXT,
            target_count INTEGER,
            success_count INTEGER,
            failure_count INTEGER,
            error_message TEXT,
            notification_type TEXT DEFAULT 'MISSING_PERSON',
            FOREIGN KEY (person_id) REFERENCES missing_persons (id)
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS sighting_reports (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            person_id TEXT,
            reporter_id TEXT,
            reporter_lat REAL,
            reporter_lng REAL,
            description TEXT,
            photo_base64 TEXT,
            confidence_level TEXT,
            reported_at TEXT,
            verified_at TEXT,
            status TEXT DEFAULT 'PENDING',
            verification_notes TEXT,
            FOREIGN KEY (person_id) REFERENCES missing_persons (id)
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS system_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            level TEXT,
            component TEXT,
            message TEXT,
            data TEXT
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS analytics_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cache_key TEXT UNIQUE,
            data TEXT,
            created_at TEXT,
            expires_at TEXT
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS driver_locations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            driver_id TEXT,
            lat REAL,
            lng REAL,
            accuracy REAL,
            speed REAL,
            heading REAL,
            timestamp TEXT,
            is_active INTEGER DEFAULT 1
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS cctv_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cctv_id TEXT,
            name TEXT,
            address TEXT,
            lat REAL,
            lng REAL,
            status TEXT,
            type TEXT,
            operator TEXT,
            stream_url TEXT,
            last_updated TEXT
        )
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS weather_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            lat REAL,
            lng REAL,
            weather_data TEXT,
            cached_at TEXT
        )
    ''')
    
    conn.commit()
    conn.close()
    print("데이터베이스 초기화 및 마이그레이션이 완료되었습니다.")

def log_system_event(level: str, component: str, message: str, data: dict = None):
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO system_logs (timestamp, level, component, message, data)
            VALUES (?, ?, ?, ?, ?)
        ''', (
            datetime.now().isoformat(),
            level,
            component,
            message,
            json.dumps(data, ensure_ascii=False) if data else None
        ))
        
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"시스템 로그 저장 실패: {e}")

def save_missing_person(person: MissingPerson):
    conn = sqlite3.connect('missing_persons.db')
    cursor = conn.cursor()
    
    current_time = datetime.now().isoformat()
    
    cursor.execute('''
        INSERT OR REPLACE INTO missing_persons 
        (id, name, age, gender, location, description, photo_url, photo_base64, 
         priority, risk_factors, ner_entities, extracted_features, lat, lng, 
         created_at, updated_at, status, category, source, confidence_score,
         last_seen, clothing_description, medical_condition, emergency_contact)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', (
        person.id, person.name, person.age, person.gender, person.location,
        person.description, person.photo_url, person.photo_base64, person.priority,
        json.dumps(person.risk_factors, ensure_ascii=False),
        json.dumps(person.ner_entities, ensure_ascii=False),
        json.dumps(person.extracted_features, ensure_ascii=False),
        person.lat, person.lng, person.created_at, current_time, person.status, 
        person.category, person.source, person.confidence_score,
        person.last_seen, person.clothing_description, person.medical_condition,
        person.emergency_contact
    ))
    
    conn.commit()
    conn.close()
    
    log_system_event("INFO", "DATABASE", f"실종자 저장: {person.name} ({person.id})")

def get_missing_persons(status: str = "ACTIVE", limit: int = None, offset: int = 0) -> List[Dict]:
    conn = sqlite3.connect('missing_persons.db')
    cursor = conn.cursor()
    
    query = '''
        SELECT id, name, age, gender, location, description, photo_url, photo_base64,
               priority, risk_factors, ner_entities, extracted_features, lat, lng,
               created_at, updated_at, status, category, source, confidence_score,
               last_seen, clothing_description, medical_condition, emergency_contact
        FROM missing_persons 
        WHERE status = ?
        ORDER BY priority DESC, created_at DESC
    '''
    
    params = [status]
    
    if limit:
        query += " LIMIT ? OFFSET ?"
        params.extend([limit, offset])
    
    cursor.execute(query, params)
    
    columns = [description[0] for description in cursor.description]
    persons = []
    
    for row in cursor.fetchall():
        person_dict = dict(zip(columns, row))
        
        try:
            person_dict['risk_factors'] = json.loads(person_dict.get('risk_factors') or '[]')
            person_dict['ner_entities'] = json.loads(person_dict.get('ner_entities') or '{}')
            person_dict['extracted_features'] = json.loads(person_dict.get('extracted_features') or '{}')
        except json.JSONDecodeError:
            person_dict['risk_factors'] = []
            person_dict['ner_entities'] = {}
            person_dict['extracted_features'] = {}
        
        persons.append(person_dict)
    
    conn.close()
    return persons

def get_existing_person_ids() -> set:
    conn = sqlite3.connect('missing_persons.db')
    cursor = conn.cursor()
    
    cursor.execute('SELECT id FROM missing_persons WHERE status = "ACTIVE"')
    ids = {row[0] for row in cursor.fetchall()}
    
    conn.close()
    return ids

async def fetch_safe182_data():
    try:
        params = {}
        if SAFE182_ESNTL_ID and SAFE182_AUTH_KEY:
            params = {
                "esntlId": SAFE182_ESNTL_ID,
                "authKey": SAFE182_AUTH_KEY
            }
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            start_time = time.time()
            response = await client.get(SAFE_URL, params=params)
            response_time = time.time() - start_time
            
            if response.status_code != 200:
                api_manager.record_error()
                log_system_event("ERROR", "SAFE182_API", f"API 오류: {response.status_code}")
                return []
            
            data = response.json()
            
            if not isinstance(data, list):
                log_system_event("WARNING", "SAFE182_API", "응답이 예상 형식이 아닙니다")
                return []
            
            await log_api_request("SAFE182", "GET", len(data), True, response_time)
            print(f"Safe182에서 {len(data)}명의 실종자 데이터를 가져왔습니다")
            return data
            
    except Exception as e:
        api_manager.record_error()
        await log_api_request("SAFE182", "GET", 0, False, 0, str(e))
        log_system_event("ERROR", "SAFE182_API", f"API 호출 실패: {e}")
        return []

async def send_to_ner_server(raw_data_list: List[Dict]) -> List[Dict]:
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            start_time = time.time()
            response = await client.post(
                f"{NER_SERVER_URL}/api/process_missing_persons",
                json={"raw_data_list": raw_data_list}
            )
            response_time = time.time() - start_time
            
            if response.status_code == 200:
                processed_data = response.json()
                await log_api_request("NER_SERVER", "POST", len(processed_data), True, response_time)
                print(f"NER 서버에서 {len(processed_data)}명의 데이터를 처리했습니다")
                return processed_data
            else:
                await log_api_request("NER_SERVER", "POST", 0, False, response_time, f"HTTP {response.status_code}")
                print(f"NER 서버 오류: {response.status_code}")
                return []
                
    except Exception as e:
        await log_api_request("NER_SERVER", "POST", 0, False, 0, str(e))
        log_system_event("ERROR", "NER_SERVER", f"연결 실패: {e}")
        return []

async def geocode_address(address: str) -> Dict[str, float]:
    if not address or not KAKAO_API_KEY:
        return {"lat": 36.3504, "lng": 127.3845}
    
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(
                KAKAO_GEO,
                headers={"Authorization": f"KakaoAK {KAKAO_API_KEY}"},
                params={"query": address}
            )
            
            if response.status_code == 200:
                data = response.json()
                documents = data.get("documents", [])
                
                if documents:
                    coord = documents[0]
                    result = {
                        "lat": float(coord["y"]),
                        "lng": float(coord["x"])
                    }
                    log_system_event("DEBUG", "GEOCODING", f"주소 변환 성공: {address} -> {result}")
                    return result
    except Exception as e:
        log_system_event("ERROR", "GEOCODING", f"지오코딩 실패 ({address}): {e}")
    
    return {"lat": 36.3504, "lng": 127.3845}

async def fetch_cctv_data(lat: float, lng: float, radius: int = 1000):
    if not ITS_CCTV_API_KEY:
        log_system_event("WARNING", "CCTV_API", "API 키가 설정되지 않았습니다")
        return []
    
    async with httpx.AsyncClient() as client:
        params = {
            "apiKey": ITS_CCTV_API_KEY,
            "type": "도로유형",
            "cctvType": "실시간스트리밍",
            "minX": lng - 0.01,
            "maxX": lng + 0.01,
            "minY": lat - 0.01,
            "maxY": lat + 0.01,
            "getType": "json"
        }
        
        try:
            start_time = time.time()
            response = await client.get(ITS_CCTV_URL, params=params, timeout=30.0)
            response_time = time.time() - start_time
            
            if response.status_code == 200:
                data = response.json()
                result = data.get("data", [])
                await log_api_request("CCTV_API", "GET", len(result), True, response_time)
                return result
            else:
                await log_api_request("CCTV_API", "GET", 0, False, response_time, f"HTTP {response.status_code}")
                return []
                
        except Exception as e:
            await log_api_request("CCTV_API", "GET", 0, False, 0, str(e))
            log_system_event("ERROR", "CCTV_API", f"요청 실패: {e}")
            return []

async def fetch_weather_data(lat: float, lng: float):
    if not OPENWEATHER_API_KEY:
        return None
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                WEATHER_URL,
                params={
                    "lat": lat,
                    "lon": lng,
                    "appid": OPENWEATHER_API_KEY,
                    "units": "metric",
                    "lang": "kr"
                }
            )
            
            if response.status_code == 200:
                return response.json()
            
    except Exception as e:
        log_system_event("ERROR", "WEATHER_API", f"날씨 정보 요청 실패: {e}")
    
    return None

async def send_fcm_notification(person: MissingPerson, custom_message: str = None):
    if not firebase_messaging:
        log_system_event("WARNING", "FCM", "Firebase가 초기화되지 않았습니다")
        return False
    
    conn = sqlite3.connect('missing_persons.db')
    cursor = conn.cursor()
    
    cursor.execute('SELECT token FROM fcm_tokens WHERE active = 1')
    tokens = [row[0] for row in cursor.fetchall()]
    
    if not tokens:
        log_system_event("WARNING", "FCM", "등록된 FCM 토큰이 없습니다")
        conn.close()
        return False
    
    message_data = {
        "type": "missing_person_alert",
        "person_id": person.id,
        "name": person.name or "이름없음",
        "age": str(person.age) if person.age else "",
        "gender": person.gender or "",
        "location": person.location or "",
        "description": person.description or "",
        "priority": person.priority,
        "photo_base64": person.photo_base64 or "",
        "lat": str(person.lat) if person.lat else "",
        "lng": str(person.lng) if person.lng else "",
        "category": person.category or "",
        "risk_factors": json.dumps(person.risk_factors, ensure_ascii=False)
    }
    
    notification_title = f"실종자 발견 요청 ({person.priority})"
    notification_body = custom_message or f"{person.name or '이름없음'}님을 찾고 있습니다"
    
    message = firebase_messaging.MulticastMessage(
        data=message_data,
        tokens=tokens,
        android=firebase_messaging.AndroidConfig(
            priority='high',
            notification=firebase_messaging.AndroidNotification(
                title=notification_title,
                body=notification_body,
                icon='ic_notification',
                color='#FF0000',
                sound='default'
            )
        ),
        apns=firebase_messaging.APNSConfig(
            payload=firebase_messaging.APNSPayload(
                aps=firebase_messaging.Aps(
                    alert=firebase_messaging.ApsAlert(
                        title=notification_title,
                        body=notification_body
                    ),
                    sound='default',
                    badge=1
                )
            )
        )
    )
    
    try:
        response = firebase_messaging.send_multicast(message)
        
        cursor.execute('''
            INSERT INTO notifications 
            (person_id, message, priority, sent_at, target_count, success_count, failure_count)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (
            person.id,
            notification_body,
            person.priority,
            datetime.now().isoformat(),
            len(tokens),
            response.success_count,
            response.failure_count
        ))
        
        conn.commit()
        conn.close()
        
        log_system_event("INFO", "FCM", f"알림 전송: 성공 {response.success_count}개, 실패 {response.failure_count}개")
        
        await manager.broadcast({
            "type": "fcm_sent",
            "person_id": person.id,
            "success_count": response.success_count,
            "failure_count": response.failure_count,
            "total_tokens": len(tokens)
        })
        
        return response.success_count > 0
        
    except Exception as e:
        cursor.execute('''
            INSERT INTO notifications 
            (person_id, message, priority, sent_at, target_count, success_count, failure_count, error_message)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            person.id,
            notification_body,
            person.priority,
            datetime.now().isoformat(),
            len(tokens),
            0,
            len(tokens),
            str(e)
        ))
        
        conn.commit()
        conn.close()
        
        log_system_event("ERROR", "FCM", f"전송 실패: {e}")
        return False

async def log_api_request(endpoint: str, method: str, result_count: int, success: bool, response_time: float, error_message: str = None):
    conn = sqlite3.connect('missing_persons.db')
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO api_requests (request_time, endpoint, method, result_count, success, response_time, error_message)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', (
        datetime.now().isoformat(),
        endpoint,
        method,
        result_count,
        1 if success else 0,
        response_time,
        error_message
    ))
    conn.commit()
    conn.close()

async def start_optimized_polling():
    print("최적화된 폴링 시작")
    
    while True:
        try:
            cached_data = api_manager.get_cached_data()
            if cached_data:
                print(f"캐시된 데이터 사용 중 (나이: {time.time() - api_manager.cache_timestamp:.0f}초)")
                await asyncio.sleep(300)
                continue
            
            if not api_manager.should_make_request():
                await asyncio.sleep(60)
                continue
            
            log_system_event("INFO", "POLLING", "Safe182 API 폴링 시작")
            raw_data_list = await fetch_safe182_data()
            
            if not raw_data_list:
                await asyncio.sleep(300)
                continue
            
            api_manager.update_cache(raw_data_list)
            
            processed_data = await send_to_ner_server(raw_data_list)
            if not processed_data:
                await asyncio.sleep(300)
                continue
            
            existing_ids = get_existing_person_ids()
            new_persons = []
            updated_persons = []
            
            for person_data in processed_data:
                person = MissingPerson(**person_data)
                
                coord = await geocode_address(person.location)
                person.lat = coord["lat"]
                person.lng = coord["lng"]
                
                save_missing_person(person)
                
                if person.id not in existing_ids:
                    new_persons.append(person)
                else:
                    updated_persons.append(person)
            
            if new_persons or updated_persons:
                log_system_event("INFO", "POLLING", f"데이터 업데이트: 신규 {len(new_persons)}명, 갱신 {len(updated_persons)}명")
                
                await manager.broadcast({
                    "type": "data_update",
                    "new_count": len(new_persons),
                    "updated_count": len(updated_persons),
                    "timestamp": datetime.now().isoformat()
                })
                
                for person in new_persons:
                    if person.priority in ["HIGH", "URGENT"]:
                        await send_fcm_notification(person)
            
            await asyncio.sleep(900)
            
        except Exception as e:
            log_system_event("ERROR", "POLLING", f"폴링 오류: {e}")
            await asyncio.sleep(300)

async def cleanup_old_data():
    while True:
        try:
            await asyncio.sleep(3600)
            
            conn = sqlite3.connect('missing_persons.db')
            cursor = conn.cursor()
            
            one_week_ago = (datetime.now() - timedelta(days=7)).isoformat()
            one_month_ago = (datetime.now() - timedelta(days=30)).isoformat()
            
            cursor.execute('DELETE FROM api_requests WHERE request_time < ?', (one_week_ago,))
            cursor.execute('DELETE FROM system_logs WHERE timestamp < ?', (one_week_ago,))
            cursor.execute('DELETE FROM analytics_cache WHERE expires_at < ?', (datetime.now().isoformat(),))
            cursor.execute('DELETE FROM driver_locations WHERE timestamp < ? AND is_active = 0', (one_month_ago,))
            
            deleted_count = cursor.rowcount
            conn.commit()
            conn.close()
            
            if deleted_count > 0:
                log_system_event("INFO", "CLEANUP", f"오래된 데이터 {deleted_count}건 정리 완료")
            
        except Exception as e:
            log_system_event("ERROR", "CLEANUP", f"데이터 정리 실패: {e}")

async def update_analytics():
    while True:
        try:
            await asyncio.sleep(1800)
            
            conn = sqlite3.connect('missing_persons.db')
            cursor = conn.cursor()
            
            today = datetime.now().date().isoformat()
            
            cursor.execute('SELECT COUNT(*) FROM missing_persons WHERE status = "ACTIVE"')
            total_active = cursor.fetchone()[0]
            
            cursor.execute('SELECT COUNT(*) FROM missing_persons WHERE priority = "HIGH" AND status = "ACTIVE"')
            high_priority = cursor.fetchone()[0]
            
            cursor.execute('SELECT COUNT(*) FROM fcm_tokens WHERE active = 1')
            active_drivers = cursor.fetchone()[0]
            
            cursor.execute('SELECT COUNT(*) FROM sighting_reports WHERE DATE(reported_at) = ?', (today,))
            today_reports = cursor.fetchone()[0]
            
            analytics_data = {
                "total_active": total_active,
                "high_priority": high_priority,
                "active_drivers": active_drivers,
                "today_reports": today_reports,
                "timestamp": datetime.now().isoformat()
            }
            
            cache_key = f"analytics_daily_{today}"
            expires_at = (datetime.now() + timedelta(hours=1)).isoformat()
            
            cursor.execute('''
                INSERT OR REPLACE INTO analytics_cache (cache_key, data, created_at, expires_at)
                VALUES (?, ?, ?, ?)
            ''', (cache_key, json.dumps(analytics_data), datetime.now().isoformat(), expires_at))
            
            conn.commit()
            conn.close()
            
            await manager.broadcast({
                "type": "analytics_update",
                "data": analytics_data
            })
            
        except Exception as e:
            log_system_event("ERROR", "ANALYTICS", f"분석 데이터 업데이트 실패: {e}")

@app.websocket("/ws/admin")
async def websocket_admin_endpoint(websocket: WebSocket):
    await manager.connect(websocket, "admin")
    try:
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)
            
            if message.get("type") == "ping":
                await manager.send_personal_message(websocket, {"type": "pong", "timestamp": datetime.now().isoformat()})
            elif message.get("type") == "request_stats":
                stats = await get_real_time_stats()
                await manager.send_personal_message(websocket, {"type": "stats_update", "data": stats})
                
    except WebSocketDisconnect:
        manager.disconnect(websocket)

@app.websocket("/ws/driver/{driver_id}")
async def websocket_driver_endpoint(websocket: WebSocket, driver_id: str):
    await manager.connect(websocket, "driver")
    try:
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)
            
            if message.get("type") == "location_update":
                await update_driver_location(driver_id, message.get("location", {}))
            elif message.get("type") == "sighting_report":
                await handle_sighting_report(message)
                
    except WebSocketDisconnect:
        manager.disconnect(websocket)

async def get_real_time_stats():
    conn = sqlite3.connect('missing_persons.db')
    cursor = conn.cursor()
    
    cursor.execute('SELECT COUNT(*) FROM missing_persons WHERE status = "ACTIVE"')
    total_active = cursor.fetchone()[0]
    
    cursor.execute('SELECT COUNT(*) FROM missing_persons WHERE priority = "HIGH" AND status = "ACTIVE"')
    high_priority = cursor.fetchone()[0]
    
    cursor.execute('SELECT COUNT(*) FROM fcm_tokens WHERE active = 1')
    active_drivers = cursor.fetchone()[0]
    
    cursor.execute('SELECT COUNT(*) FROM notifications WHERE DATE(sent_at) = DATE("now")')
    today_notifications = cursor.fetchone()[0]
    
    conn.close()
    
    return {
        "total_active": total_active,
        "high_priority": high_priority,
        "active_drivers": active_drivers,
        "today_notifications": today_notifications,
        "api_stats": api_manager.get_stats(),
        "connection_stats": manager.get_connection_stats()
    }

async def update_driver_location(driver_id: str, location: dict):
    if not location.get("lat") or not location.get("lng"):
        return
    
    conn = sqlite3.connect('missing_persons.db')
    cursor = conn.cursor()
    
    cursor.execute('''
        INSERT INTO driver_locations 
        (driver_id, lat, lng, accuracy, speed, heading, timestamp, is_active)
        VALUES (?, ?, ?, ?, ?, ?, ?, 1)
    ''', (
        driver_id,
        location.get("lat"),
        location.get("lng"),
        location.get("accuracy", 0),
        location.get("speed", 0),
        location.get("heading", 0),
        datetime.now().isoformat()
    ))
    
    cursor.execute('UPDATE fcm_tokens SET location_lat = ?, location_lng = ?, last_active = ? WHERE user_id = ?',
                   (location.get("lat"), location.get("lng"), datetime.now().isoformat(), driver_id))
    
    conn.commit()
    conn.close()

async def handle_sighting_report(message: dict):
    report_data = ReportRequest(**message.get("data", {}))
    
    conn = sqlite3.connect('missing_persons.db')
    cursor = conn.cursor()
    
    cursor.execute('''
        INSERT INTO sighting_reports 
        (person_id, reporter_id, reporter_lat, reporter_lng, description, photo_base64, 
         confidence_level, reported_at, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'PENDING')
    ''', (
        report_data.person_id,
        report_data.reporter_id,
        report_data.reporter_location.get("lat"),
        report_data.reporter_location.get("lng"),
        report_data.description,
        report_data.photo_base64,
        report_data.confidence_level,
        datetime.now().isoformat()
    ))
    
    conn.commit()
    conn.close()
    
    await manager.broadcast({
        "type": "new_sighting_report",
        "person_id": report_data.person_id,
        "location": report_data.reporter_location,
        "confidence": report_data.confidence_level,
        "timestamp": datetime.now().isoformat()
    })

@app.get("/api/missing_persons")
async def get_missing_persons_api(
    status: str = "ACTIVE",
    priority: str = None,
    category: str = None,
    limit: int = Query(None, ge=1, le=1000),
    offset: int = Query(0, ge=0)
):
    try:
        persons = get_missing_persons(status, limit, offset)
        
        if priority:
            persons = [p for p in persons if p.get("priority") == priority]
        
        if category:
            persons = [p for p in persons if p.get("category") == category]
        
        return {"persons": persons, "count": len(persons), "total": len(get_missing_persons(status))}
    except Exception as e:
        log_system_event("ERROR", "API", f"실종자 목록 조회 실패: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/person/{person_id}")
async def get_person_detail(person_id: str):
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT id, name, age, gender, location, description, photo_url, photo_base64,
                   priority, risk_factors, ner_entities, extracted_features, lat, lng,
                   created_at, updated_at, status, category, source, confidence_score,
                   last_seen, clothing_description, medical_condition, emergency_contact
            FROM missing_persons WHERE id = ?
        ''', (person_id,))
        
        row = cursor.fetchone()
        
        if not row:
            raise HTTPException(status_code=404, detail="실종자를 찾을 수 없습니다")
        
        columns = [desc[0] for desc in cursor.description]
        person_dict = dict(zip(columns, row))
        
        try:
            person_dict['risk_factors'] = json.loads(person_dict.get('risk_factors') or '[]')
            person_dict['ner_entities'] = json.loads(person_dict.get('ner_entities') or '{}')
            person_dict['extracted_features'] = json.loads(person_dict.get('extracted_features') or '{}')
        except json.JSONDecodeError:
            person_dict['risk_factors'] = []
            person_dict['ner_entities'] = {}
            person_dict['extracted_features'] = {}
        
        cursor.execute('SELECT COUNT(*) FROM sighting_reports WHERE person_id = ?', (person_id,))
        person_dict['sighting_count'] = cursor.fetchone()[0]
        
        cursor.execute('''
            SELECT reporter_lat, reporter_lng, description, confidence_level, reported_at 
            FROM sighting_reports WHERE person_id = ? ORDER BY reported_at DESC LIMIT 5
        ''', (person_id,))
        
        sightings = []
        for sighting_row in cursor.fetchall():
            sightings.append({
                "lat": sighting_row[0],
                "lng": sighting_row[1],
                "description": sighting_row[2],
                "confidence": sighting_row[3],
                "reported_at": sighting_row[4]
            })
        
        person_dict['recent_sightings'] = sightings
        
        conn.close()
        return person_dict
        
    except HTTPException:
        raise
    except Exception as e:
        log_system_event("ERROR", "API", f"실종자 상세 조회 실패: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/register_token")
async def register_fcm_token(request: FCMTokenRequest):
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        current_time = datetime.now().isoformat()
        
        cursor.execute('''
            INSERT OR REPLACE INTO fcm_tokens 
            (token, user_id, driver_name, platform, device_info, registered_at, last_active, 
             location_lat, location_lng, active)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
        ''', (
            request.token,
            request.driver_id,
            request.driver_name,
            request.platform,
            request.device_info,
            current_time,
            current_time,
            request.location.get("lat") if request.location else None,
            request.location.get("lng") if request.location else None
        ))
        
        conn.commit()
        conn.close()
        
        log_system_event("INFO", "FCM", f"토큰 등록: {request.driver_name} ({request.driver_id})")
        
        await manager.broadcast({
            "type": "driver_registered",
            "driver_id": request.driver_id,
            "driver_name": request.driver_name,
            "timestamp": current_time
        })
        
        return {"status": "success", "message": "토큰이 등록되었습니다"}
        
    except Exception as e:
        log_system_event("ERROR", "FCM", f"토큰 등록 실패: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/report_sighting")
async def report_sighting(request: ReportRequest):
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        current_time = datetime.now().isoformat()
        
        cursor.execute('''
            INSERT INTO sighting_reports 
            (person_id, reporter_id, reporter_lat, reporter_lng, description, photo_base64, 
             confidence_level, reported_at, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'PENDING')
        ''', (
            request.person_id,
            request.reporter_id,
            request.reporter_location.get("lat"),
            request.reporter_location.get("lng"),
            request.description,
            request.photo_base64,
            request.confidence_level,
            current_time
        ))
        
        report_id = cursor.lastrowid
        conn.commit()
        conn.close()
        
        log_system_event("INFO", "SIGHTING", f"목격 신고 접수: {request.person_id} by {request.reporter_id}")
        
        await manager.broadcast({
            "type": "new_sighting_report",
            "report_id": report_id,
            "person_id": request.person_id,
            "location": request.reporter_location,
            "confidence": request.confidence_level,
            "description": request.description,
            "timestamp": current_time
        })
        
        return {"status": "success", "message": "목격 신고가 접수되었습니다", "report_id": report_id}
        
    except Exception as e:
        log_system_event("ERROR", "SIGHTING", f"목격 신고 실패: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/active_tokens")
async def get_active_tokens():
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT token, user_id, driver_name, platform, device_info, registered_at, 
                   last_active, location_lat, location_lng
            FROM fcm_tokens WHERE active = 1 ORDER BY last_active DESC
        ''')
        
        tokens = []
        for row in cursor.fetchall():
            tokens.append({
                "token": row[0],
                "driver_id": row[1],
                "driver_name": row[2],
                "platform": row[3],
                "device_info": row[4],
                "registered_at": row[5],
                "last_active": row[6],
                "location": {
                    "lat": row[7],
                    "lng": row[8]
                } if row[7] and row[8] else None
            })
        
        conn.close()
        return {"tokens": tokens, "count": len(tokens)}
        
    except Exception as e:
        log_system_event("ERROR", "API", f"토큰 목록 조회 실패: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/send_notification")
async def send_custom_notification(request: NotificationRequest):
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        cursor.execute('SELECT * FROM missing_persons WHERE id = ?', (request.person_id,))
        person_row = cursor.fetchone()
        
        if not person_row:
            raise HTTPException(status_code=404, detail="실종자를 찾을 수 없습니다")
        
        columns = [desc[0] for desc in cursor.description]
        person_dict = dict(zip(columns, person_row))
        person = MissingPerson(**person_dict)
        
        success = await send_fcm_notification(person, request.message)
        
        conn.close()
        
        return {
            "status": "success" if success else "failed",
            "message": "알림이 전송되었습니다" if success else "알림 전송에 실패했습니다"
        }
        
    except HTTPException:
        raise
    except Exception as e:
        log_system_event("ERROR", "NOTIFICATION", f"사용자 정의 알림 전송 실패: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/search_cctv")
async def search_cctv(request: CCTVRequest):
    try:
        cctv_data = await fetch_cctv_data(request.lat, request.lng, request.radius)
        
        processed_cctvs = []
        for cctv in cctv_data:
            processed_cctv = {
                "id": cctv.get("roadsectionid", f"cctv_{len(processed_cctvs)}"),
                "name": cctv.get("cctvname", "CCTV"),
                "address": f"{cctv.get('coordy', '')}, {cctv.get('coordx', '')}",
                "distance": 0,
                "status": "정상" if cctv.get("cctvresolution") else "점검중",
                "type": cctv.get("cctvtype", "교통감시"),
                "operator": "한국도로공사",
                "stream_url": cctv.get("cctvurl", ""),
                "coords": {
                    "lat": float(cctv.get("coordy", 0)),
                    "lng": float(cctv.get("coordx", 0))
                },
                "resolution": cctv.get("cctvresolution", ""),
                "format": cctv.get("cctvformat", "")
            }
            processed_cctvs.append(processed_cctv)
        
        return {"cctvs": processed_cctvs, "count": len(processed_cctvs)}
        
    except Exception as e:
        log_system_event("ERROR", "CCTV", f"CCTV 검색 오류: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/weather")
async def get_weather(lat: float, lng: float):
    try:
        weather_data = await fetch_weather_data(lat, lng)
        
        if not weather_data:
            raise HTTPException(status_code=404, detail="날씨 정보를 가져올 수 없습니다")
        
        return {
            "temperature": weather_data.get("main", {}).get("temp"),
            "description": weather_data.get("weather", [{}])[0].get("description"),
            "humidity": weather_data.get("main", {}).get("humidity"),
            "wind_speed": weather_data.get("wind", {}).get("speed"),
            "visibility": weather_data.get("visibility", 0) / 1000
        }
        
    except HTTPException:
        raise
    except Exception as e:
        log_system_event("ERROR", "WEATHER", f"날씨 정보 조회 실패: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/statistics")
async def get_statistics():
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        cursor.execute('SELECT COUNT(*) FROM missing_persons WHERE status = "ACTIVE"')
        total_active = cursor.fetchone()[0]
        
        cursor.execute('SELECT COUNT(*) FROM missing_persons WHERE priority = "HIGH" AND status = "ACTIVE"')
        high_priority = cursor.fetchone()[0]
        
        cursor.execute('SELECT COUNT(*) FROM api_requests WHERE DATE(request_time) = DATE("now")')
        today_requests = cursor.fetchone()[0]
        
        cursor.execute('SELECT COUNT(*) FROM api_requests WHERE success = 1 AND DATE(request_time) = DATE("now")')
        today_success = cursor.fetchone()[0]
        
        cursor.execute('SELECT COUNT(*) FROM notifications WHERE DATE(sent_at) = DATE("now")')
        today_notifications = cursor.fetchone()[0]
        
        cursor.execute('SELECT COUNT(*) FROM fcm_tokens WHERE active = 1')
        active_drivers = cursor.fetchone()[0]
        
        cursor.execute('SELECT COUNT(*) FROM sighting_reports WHERE DATE(reported_at) = DATE("now")')
        today_reports = cursor.fetchone()[0]
        
        cursor.execute('''
            SELECT priority, COUNT(*) 
            FROM missing_persons 
            WHERE status = "ACTIVE" 
            GROUP BY priority
        ''')
        priority_stats = dict(cursor.fetchall())
        
        cursor.execute('''
            SELECT category, COUNT(*) 
            FROM missing_persons 
            WHERE status = "ACTIVE" AND category IS NOT NULL 
            GROUP BY category
        ''')
        category_stats = dict(cursor.fetchall())
        
        conn.close()
        
        success_rate = (today_success / max(today_requests, 1)) * 100
        
        return {
            "total_active": total_active,
            "high_priority": high_priority,
            "active_drivers": active_drivers,
            "today_notifications": today_notifications,
            "today_reports": today_reports,
            "api_stats": {
                "total_requests": today_requests,
                "success_requests": today_success,
                "success_rate": round(success_rate, 2)
            },
            "priority_distribution": priority_stats,
            "category_distribution": category_stats,
            "system_stats": api_manager.get_stats()
        }
        
    except Exception as e:
        log_system_event("ERROR", "STATISTICS", f"통계 조회 실패: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/analytics")
async def get_analytics(request: AnalyticsRequest = Depends()):
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        start_date = request.start_date
        end_date = request.end_date
        
        cursor.execute('''
            SELECT DATE(created_at) as date, COUNT(*) as count
            FROM missing_persons 
            WHERE created_at BETWEEN ? AND ?
            GROUP BY DATE(created_at)
            ORDER BY date
        ''', (start_date, end_date))
        
        daily_missing = [{"date": row[0], "count": row[1]} for row in cursor.fetchall()]
        
        cursor.execute('''
            SELECT DATE(sent_at) as date, COUNT(*) as count, AVG(success_count) as avg_success
            FROM notifications 
            WHERE sent_at BETWEEN ? AND ?
            GROUP BY DATE(sent_at)
            ORDER BY date
        ''', (start_date, end_date))
        
        daily_notifications = [{"date": row[0], "count": row[1], "avg_success": row[2]} for row in cursor.fetchall()]
        
        cursor.execute('''
            SELECT DATE(reported_at) as date, COUNT(*) as count
            FROM sighting_reports 
            WHERE reported_at BETWEEN ? AND ?
            GROUP BY DATE(reported_at)
            ORDER BY date
        ''', (start_date, end_date))
        
        daily_reports = [{"date": row[0], "count": row[1]} for row in cursor.fetchall()]
        
        conn.close()
        
        return {
            "daily_missing_persons": daily_missing,
            "daily_notifications": daily_notifications,
            "daily_sighting_reports": daily_reports,
            "period": {"start": start_date, "end": end_date}
        }
        
    except Exception as e:
        log_system_event("ERROR", "ANALYTICS", f"분석 데이터 조회 실패: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/batch_update")
async def batch_update_persons(request: BatchUpdateRequest):
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        updated_count = 0
        current_time = datetime.now().isoformat()
        
        for person_id in request.person_ids:
            update_fields = []
            update_values = []
            
            for field, value in request.updates.items():
                if field in ['status', 'priority', 'category', 'description']:
                    update_fields.append(f"{field} = ?")
                    update_values.append(value)
            
            if update_fields:
                update_fields.append("updated_at = ?")
                update_values.append(current_time)
                update_values.append(person_id)
                
                query = f"UPDATE missing_persons SET {', '.join(update_fields)} WHERE id = ?"
                cursor.execute(query, update_values)
                
                if cursor.rowcount > 0:
                    updated_count += 1
        
        conn.commit()
        conn.close()
        
        log_system_event("INFO", "BATCH_UPDATE", f"일괄 업데이트: {updated_count}명")
        
        await manager.broadcast({
            "type": "batch_update_completed",
            "updated_count": updated_count,
            "person_ids": request.person_ids,
            "timestamp": current_time
        })
        
        return {
            "status": "success",
            "updated_count": updated_count,
            "message": f"{updated_count}명의 정보가 업데이트되었습니다"
        }
        
    except Exception as e:
        log_system_event("ERROR", "BATCH_UPDATE", f"일괄 업데이트 실패: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/system_logs")
async def get_system_logs(
    level: str = None,
    component: str = None,
    limit: int = Query(100, ge=1, le=1000)
):
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        query = "SELECT timestamp, level, component, message, data FROM system_logs"
        params = []
        conditions = []
        
        if level:
            conditions.append("level = ?")
            params.append(level)
        
        if component:
            conditions.append("component = ?")
            params.append(component)
        
        if conditions:
            query += " WHERE " + " AND ".join(conditions)
        
        query += " ORDER BY timestamp DESC LIMIT ?"
        params.append(limit)
        
        cursor.execute(query, params)
        
        logs = []
        for row in cursor.fetchall():
            log_entry = {
                "timestamp": row[0],
                "level": row[1],
                "component": row[2],
                "message": row[3],
                "data": json.loads(row[4]) if row[4] else None
            }
            logs.append(log_entry)
        
        conn.close()
        return {"logs": logs, "count": len(logs)}
        
    except Exception as e:
        log_system_event("ERROR", "SYSTEM_LOGS", f"시스템 로그 조회 실패: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/force_update")
async def force_update():
    try:
        log_system_event("INFO", "MANUAL_UPDATE", "수동 업데이트 요청")
        
        raw_data_list = await fetch_safe182_data()
        if not raw_data_list:
            return {"status": "error", "message": "Safe182 API에서 데이터를 가져올 수 없습니다"}
        
        processed_data = await send_to_ner_server(raw_data_list)
        if not processed_data:
            return {"status": "error", "message": "NER 서버에서 데이터 처리에 실패했습니다"}
        
        existing_ids = get_existing_person_ids()
        new_count = 0
        updated_count = 0
        
        for person_data in processed_data:
            person = MissingPerson(**person_data)
            
            coord = await geocode_address(person.location)
            person.lat = coord["lat"]
            person.lng = coord["lng"]
            
            if person.id not in existing_ids:
                new_count += 1
            else:
                updated_count += 1
            
            save_missing_person(person)
        
        api_manager.update_cache(raw_data_list)
        
        log_system_event("INFO", "MANUAL_UPDATE", f"업데이트 완료: 신규 {new_count}명, 갱신 {updated_count}명")
        
        return {
            "status": "success", 
            "message": f"업데이트 완료: 신규 {new_count}명, 갱신 {updated_count}명",
            "new": new_count,
            "updated": updated_count,
            "timestamp": datetime.now().isoformat()
        }
        
    except Exception as e:
        log_system_event("ERROR", "MANUAL_UPDATE", f"업데이트 실패: {e}")
        raise HTTPException(status_code=500, detail=f"업데이트 실패: {str(e)}")

@app.get("/api/health")
async def health_check():
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        cursor.execute('SELECT 1')
        db_status = "healthy"
        conn.close()
    except:
        db_status = "unhealthy"
    
    ner_status = "healthy" if await check_ner_server() else "unhealthy"
    firebase_status = "healthy" if firebase_messaging else "unhealthy"
    
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "components": {
            "database": db_status,
            "ner_server": ner_status,
            "firebase": firebase_status,
            "api_manager": "healthy"
        },
        "version": "2.0.0",
        "uptime": time.time() - api_manager.last_request_time if api_manager.last_request_time else 0
    }

@app.get("/")
async def get_admin_dashboard():
    if not KAKAO_JAVASCRIPT_KEY:
        print("경고: KAKAO_JAVASCRIPT_KEY가 설정되지 않았습니다. .env 파일을 확인하세요.")
        kakao_key = "YOUR_KAKAO_API_KEY"
    else:
        kakao_key = KAKAO_JAVASCRIPT_KEY
    
    try:
        with open("dashboard.html", "r", encoding="utf-8") as f:
            html_content = f.read()
        
        html_content = html_content.replace("YOUR_KAKAO_API_KEY", kakao_key)
        
        return HTMLResponse(html_content)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="dashboard.html 파일을 찾을 수 없습니다")

if __name__ == "__main__":
    import uvicorn
    print("대전 이동 안전망 시스템을 시작합니다")
    print("=" * 50)
    print("포트: 8001")
    print("먼저 ner_server.py (포트 8000)가 실행되어 있는지 확인하세요")
    print(f"카카오 API 키 설정 상태: {'설정됨' if KAKAO_JAVASCRIPT_KEY else '미설정'}")
    print(f"Firebase 설정 상태: {'설정됨' if FIREBASE_CREDENTIALS else '미설정'}")
    print(f"ITS CCTV API 설정 상태: {'설정됨' if ITS_CCTV_API_KEY else '미설정'}")
    print("=" * 50)
    uvicorn.run(app, host="0.0.0.0", port=8001, reload=False)