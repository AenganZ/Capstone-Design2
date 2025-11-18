import os
import time
import json
import sqlite3
import asyncio
import httpx
import uuid
import requests
import osmnx as ox
from datetime import datetime, timedelta
from contextlib import asynccontextmanager
from typing import List, Dict, Any, Optional, Union

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect, Body, Query, Depends
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field, validator
from dotenv import load_dotenv
from image_generator import get_generator

load_dotenv()

DEEPL_API_KEY = os.getenv("DEEPL_API_KEY")
SAFE182_ESNTL_ID = os.getenv("SAFE182_ESNTL_ID", "")
SAFE182_AUTH_KEY = os.getenv("SAFE182_AUTH_KEY", "")
KAKAO_API_KEY = os.getenv("KAKAO_API_KEY")
KAKAO_JAVASCRIPT_KEY = os.getenv("KAKAO_JAVASCRIPT_KEY")
FIREBASE_CREDENTIALS = os.getenv("FIREBASE_CREDENTIALS", "./firebase_key.json")
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

os.makedirs("static", exist_ok=True)
app.mount("/static", StaticFiles(directory="static"), name="static")
manager = ConnectionManager()
api_manager = OptimizedAPIManager()

SAFE_URL = "https://www.safe182.go.kr/api/lcm/findChildList.do"
KAKAO_GEO = "https://dapi.kakao.com/v2/local/search/address.json"
ITS_CCTV_URL = "https://openapi.its.go.kr:9443/cctvInfo"
WEATHER_URL = "https://api.openweathermap.org/data/2.5/weather"

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
        ('emergency_contact', 'TEXT'),
        ('approval_status', 'TEXT DEFAULT "APPROVED"')
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

def log_system_event(level: str, category: str, message: str, component: str = None):
    """
    시스템 로그 저장
    level: INFO, WARNING, ERROR
    category: API, POLLING, GEOCODING 등
    message: 로그 메시지
    component: 선택적 컴포넌트명
    """
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO system_logs (level, category, component, message, timestamp)
            VALUES (?, ?, ?, ?, ?)
        ''', (
            level,
            category,
            component or "SYSTEM",
            message,
            datetime.now().isoformat()
        ))
        
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"시스템 로그 저장 실패: {e}")

def save_missing_person(person: MissingPerson):
    conn = sqlite3.connect('missing_persons.db')
    cursor = conn.cursor()
    
    current_time = datetime.now().isoformat()
    
    # Safe182 데이터는 자동 승인, REPORTER는 승인 대기
    approval_status = 'APPROVED' if person.source != 'REPORTER' else 'PENDING'
    
    cursor.execute('''
        INSERT OR REPLACE INTO missing_persons 
        (id, name, age, gender, location, description, photo_url, photo_base64, 
         priority, risk_factors, extracted_features, lat, lng, 
         created_at, updated_at, status, category, source, confidence_score,
         last_seen, clothing_description, medical_condition, emergency_contact, approval_status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', (
        person.id, person.name, person.age, person.gender, person.location,
        person.description, person.photo_url, person.photo_base64, person.priority,
        json.dumps(person.risk_factors, ensure_ascii=False),
        json.dumps(person.extracted_features, ensure_ascii=False),
        person.lat, person.lng, person.created_at, current_time, person.status, 
        person.category, person.source, person.confidence_score,
        person.last_seen, person.clothing_description, person.medical_condition,
        person.emergency_contact, approval_status
    ))
    
    conn.commit()
    conn.close()
    
    log_system_event("INFO", "DATABASE", f"실종자 저장: {person.name} ({person.id})")

def get_missing_persons(status: str = "ACTIVE", limit: int = None, offset: int = 0) -> List[Dict]:
    conn = sqlite3.connect('missing_persons.db')
    cursor = conn.cursor()
    
    query = '''
        SELECT id, name, age, gender, location, description, photo_url, photo_base64,
               priority, risk_factors, extracted_features, lat, lng,
               created_at, updated_at, status, category, source, confidence_score,
               last_seen, clothing_description, medical_condition, emergency_contact
        FROM missing_persons 
        WHERE status = ? AND (approval_status = 'APPROVED' OR source != 'REPORTER')
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
            person_dict['extracted_features'] = json.loads(person_dict.get('extracted_features') or '{}')
        except json.JSONDecodeError:
            person_dict['risk_factors'] = []
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
        from datetime import datetime, timedelta
        
        # 오늘 기준 3개월 전부터 오늘까지
        end_date_dt = datetime.now()
        start_date_dt = end_date_dt - timedelta(days=90)
        
        # findChildList API는 YYYY-MM-DD 형식 사용
        start_date = start_date_dt.strftime("%Y-%m-%d")  # ⭐ %Y%m%d → %Y-%m-%d
        end_date = end_date_dt.strftime("%Y-%m-%d")      # ⭐ %Y%m%d → %Y-%m-%d
        
        params = {
            "rowSize": 100, 
            "page": 1,
            "occrAdres": "대전",
            "detailDate1": start_date,  # ⭐ occrde1 → detailDate1
            "detailDate2": end_date      # ⭐ occrde2 → detailDate2
        }
        
        if SAFE182_ESNTL_ID and SAFE182_AUTH_KEY:
            params["esntlId"] = SAFE182_ESNTL_ID
            params["authKey"] = SAFE182_AUTH_KEY
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            start_time = time.time()
            response = await client.post(SAFE_URL, data=params)  # ⭐ 그냥 SAFE_URL 사용
            response_time = time.time() - start_time
            
            if response.status_code != 200:
                api_manager.record_error()
                log_system_event("ERROR", "SAFE182_API", f"API 오류: {response.status_code}")
                return []
            
            data = response.json()
            
            if isinstance(data, dict):
                if "list" in data:
                    persons_list = data["list"]
                else:
                    log_system_event("WARNING", "SAFE182_API", f"알 수 없는 응답 형식: {list(data.keys())}")
                    return []
            elif isinstance(data, list):
                persons_list = data
            else:
                log_system_event("WARNING", "SAFE182_API", "응답이 예상 형식이 아닙니다")
                return []
            
            await log_api_request("SAFE182", "POST", len(persons_list), True, response_time)
            print(f"Safe182에서 {len(persons_list)}명의 실종자 데이터를 가져왔습니다 ({start_date} ~ {end_date})")
            return persons_list
            
    except Exception as e:
        api_manager.record_error()
        await log_api_request("SAFE182", "POST", 0, False, 0, str(e))
        log_system_event("ERROR", "SAFE182_API", f"API 호출 실패: {e}")
        return []

def preprocess_address(address: str) -> str:
    if not address:
        return address
    
    import re
    
    original = address.strip()
    address = original
    
    address = re.sub(r'[@/\\]', ' ', address)
    address = re.sub(r'\s+', ' ', address).strip()
    
    building_patterns = [
        r'\s+[가-힣0-9]+아파트\b',
        r'\s+[가-힣0-9]+빌라\b',
        r'\s+[가-힣0-9]+타운\b',
        r'\s+[가-힣0-9]+맨션\b',
        r'\s+[가-힣0-9]+주택\b',
        r'\s+[가-힣0-9]+연립\b',
        r'\s+[가-힣0-9]+오피스텔\b',
    ]
    
    for pattern in building_patterns:
        address = re.sub(pattern, '', address)
    
    address = re.sub(r'\s+', ' ', address).strip()
    
    has_road_name = bool(re.search(r'[로길]\s*\d*[번]?[길]?\s*$', address))
    
    if not has_road_name:
        address = re.sub(r'\s+\d+-\d+\s*$', '', address)
        address = re.sub(r'\s+\d+\s*$', '', address)
    
    address = address.strip()
    
    if address != original and address:
        print(f"주소 전처리: '{original}' -> '{address}'")
    
    return address if address else original

async def geocode_address(address: str) -> Dict[str, float]:
    if not address or not KAKAO_API_KEY:
        return None
    
    import re
    
    original = address
    
    # 대전 지역이 아닌 주소 필터링
    non_daejeon_keywords = ['서울', '부산', '인천', '광주', '울산', '세종', '경기', '충남', '충북', '전남', '전북', '경남', '경북', '강원', '제주']
    if any(keyword in original for keyword in non_daejeon_keywords):
        if '대전' not in original:
            print(f"대전 지역이 아닌 주소 필터링: '{original}'")
            return None
    
    attempts = []
    
    # 1단계: 전처리된 주소
    cleaned = preprocess_address(address)
    attempts.append(("전처리", cleaned))
    
    # 2단계: 원본 주소
    attempts.append(("원본", original))
    
    # 3단계: 대전 구/동 패턴 매칭
    daejeon_patterns = [
        r'(동구|중구|서구|유성구|대덕구)\s*(.*?동)',
        r'^(둔산동|탄방동|궁동|봉명동|가양동|신성동|판암동|용운동|대동|은행동|선화동|목동|중촌동|법동|관평동|구즉동|노은동|전민동|복수동|오정동|가수원동)',
    ]
    
    for pattern in daejeon_patterns:
        match = re.search(pattern, original)
        if match:
            if len(match.groups()) == 2:
                gu, dong = match.groups()
                attempts.append(("구동", f"대전광역시 {gu} {dong}"))
            else:
                dong = match.group(1)
                dong_to_gu = {
                    '둔산동': '서구', '탄방동': '서구', '궁동': '유성구',
                    '봉명동': '유성구', '가양동': '동구', '신성동': '유성구',
                    '판암동': '동구', '용운동': '서구', '대동': '동구',
                    '은행동': '중구', '선화동': '중구', '목동': '중구',
                    '중촌동': '동구', '법동': '유성구', '관평동': '유성구',
                    '구즉동': '유성구', '노은동': '유성구', '전민동': '유성구',
                    '복수동': '서구', '오정동': '대덕구', '가수원동': '서구'
                }
                gu = dong_to_gu.get(dong, '중구')
                attempts.append(("동추론", f"대전광역시 {gu} {dong}"))
    
    # 4단계: 대전 랜드마크 키워드
    daejeon_landmarks = {
        '대전역': '대전광역시 동구 대전로',
        '서대전역': '대전광역시 서구 서대전로',
        '유성온천': '대전광역시 유성구 온천동',
        'KAIST': '대전광역시 유성구 대학로',
        '엑스포': '대전광역시 유성구 엑스포로',
        '한밭수목원': '대전광역시 서구 둔산대로',
        '보문산': '대전광역시 중구 보문로',
        '대청댐': '대전광역시 동구 대청호',
        '계룡산': '대전광역시 유성구 계룡산',
        '복합터미널': '대전광역시 동구 정동',
        '시외버스터미널': '대전광역시 동구 정동',
        '터미널': '대전광역시 동구 정동',
        '정부청사': '대전광역시 서구 청사로',
        '둔산': '대전광역시 서구 둔산동',
        '탄방': '대전광역시 서구 탄방동',
        '궁동': '대전광역시 유성구 궁동',
        '갑천': '대전광역시 서구 갑천',
        '대전천': '대전광역시 중구 대전천',
    }
    
    for keyword, full_address in daejeon_landmarks.items():
        if keyword in original:
            attempts.append(("랜드마크", full_address))
            break
    
    # 5단계: "대전" 단어 추가
    if "대전" not in original:
        attempts.append(("대전추가", f"대전광역시 {original}"))
        attempts.append(("대전추가2", f"대전 {original}"))
    
    # 6단계: 간단한 구 매칭
    simple_patterns = [
        (r'동구', '대전광역시 동구'),
        (r'중구', '대전광역시 중구'),
        (r'서구', '대전광역시 서구'),
        (r'유성', '대전광역시 유성구'),
        (r'대덕', '대전광역시 대덕구'),
    ]
    
    for pattern, prefix in simple_patterns:
        if re.search(pattern, original):
            clean_addr = re.sub(r'대전광역시|대전시|대전', '', original).strip()
            attempts.append(("구매칭", f"{prefix} {clean_addr}"))
    
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            for desc, test_addr in attempts:
                if not test_addr or len(test_addr) < 2:
                    continue
                
                response = await client.get(
                    KAKAO_GEO,
                    headers={"Authorization": f"KakaoAK {KAKAO_API_KEY}"},
                    params={"query": test_addr}
                )
                
                if response.status_code == 200:
                    data = response.json()
                    docs = data.get("documents", [])
                    
                    if docs:
                        address_name = docs[0].get("address_name", "")
                        if "대전" not in address_name and address_name:
                            print(f"대전이 아닌 좌표 결과 무시: '{original}' -> '{address_name}'")
                            continue
                        
                        result = {
                            "lat": float(docs[0]["y"]),
                            "lng": float(docs[0]["x"])
                        }
                        print(f"{desc}: '{original}' -> '{test_addr}' -> {result}")
                        return result
            
            print(f"대전 지역 좌표 찾기 실패: '{original}'")
            return None
            
    except Exception as e:
        print(f"지오코딩 오류: {e}")
        return None

def original_for_log(original, cleaned):
    """로그 출력용 헬퍼 함수"""
    if original == cleaned:
        return original
    return f"{original} -> {cleaned}"

async def fetch_cctv_data(lat: float, lng: float, radius: int):
    UTIC_CCTV_URL = "https://www.utic.go.kr/map/mapcctv.do"
    
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
        "Referer": "https://www.utic.go.kr/map/map.do?menu=cctv",
        "X-Requested-With": "XMLHttpRequest",
        "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
    }
    
    data = {
        "cctvSearchCondition": "E07001",
        "type": "E"
    }
    
    try:
        async with httpx.AsyncClient(verify=False) as client:
            start_time = time.time()
            response = await client.post(UTIC_CCTV_URL, headers=headers, data=data, timeout=15.0)
            response_time = time.time() - start_time
            
            if response.status_code == 200:
                cctvs = response.json()
                daejeon_cctvs = [c for c in cctvs if c.get("CENTERNAME") == "대전교통정보센터"]
                
                nearby_cctvs = []
                for cctv in daejeon_cctvs:
                    try:
                        cctv_lat = float(cctv.get("YCOORD", 0))
                        cctv_lng = float(cctv.get("XCOORD", 0))
                        
                        distance = ((cctv_lat - lat) ** 2 + (cctv_lng - lng) ** 2) ** 0.5 * 111000
                        
                        if distance <= radius:
                            nearby_cctvs.append(cctv)
                    except (ValueError, TypeError):
                        continue
                
                print(f"대전 CCTV {len(daejeon_cctvs)}개 중 반경 {radius}m 내 {len(nearby_cctvs)}개 검색 완료")
                await log_api_request("UTIC_CCTV", "POST", len(nearby_cctvs), True, response_time)
                return nearby_cctvs
            else:
                await log_api_request("UTIC_CCTV", "POST", 0, False, response_time, f"HTTP {response.status_code}")
                return []
                
    except Exception as e:
        print(f"UTIC CCTV API 오류: {e}")
        await log_api_request("UTIC_CCTV", "POST", 0, False, 0, str(e))
        log_system_event("ERROR", "UTIC_CCTV", f"요청 실패: {e}")
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

async def log_api_request(endpoint: str, method: str, count: int, success: bool, response_time: float, error: str = None):
    """API 요청 로그 저장"""
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        from datetime import datetime
        timestamp = datetime.now().isoformat()
        status_code = 200 if success else 500
        
        cursor.execute('''
            INSERT INTO api_requests (timestamp, endpoint, method, status_code, response_time)
            VALUES (?, ?, ?, ?, ?)
        ''', (timestamp, endpoint, method, status_code, response_time))
        
        conn.commit()
        conn.close()
        
    except Exception as e:
        print(f"API 로그 저장 실패: {e}")

async def start_optimized_polling():
    print("=" * 50)
    print("✅ Safe182 폴링 시작")
    print("=" * 50)
    
    # ✅ 첫 실행은 무조건 API 호출
    first_run = True
    
    while True:
        try:
            # ✅ 첫 실행은 캐시 무시
            if not first_run:
                cached_data = api_manager.get_cached_data()
                if cached_data:
                    print(f"💾 캐시된 데이터 사용 중 (5분 후 재확인)")
                    await asyncio.sleep(300)
                    continue
                
                if not api_manager.should_make_request():
                    print("⏳ API 호출 제한, 1분 후 재시도")
                    await asyncio.sleep(60)
                    continue
            
            first_run = False
            
            print("🔄 Safe182 API 호출 중...")
            log_system_event("INFO", "POLLING", "Safe182 API 폴링 시작")
            raw_data_list = await fetch_safe182_data()
            
            if not raw_data_list:
                print("⚠️  데이터 없음 (5분 후 재시도)")
                await asyncio.sleep(300)
                continue
            
            print(f"✅ Safe182에서 {len(raw_data_list)}명의 데이터 수신")
            
            api_manager.update_cache(raw_data_list)
            processed_data = raw_data_list

            if not processed_data:
                await asyncio.sleep(300)
                continue
            
            existing_ids = get_existing_person_ids()
            new_persons = []
            updated_persons = []
            
            for person_data in processed_data:
                person_data.setdefault('extracted_features', {})

                person = MissingPerson(**person_data)
                
                if person.location:
                    coord = await geocode_address(person.location)
                    if coord:
                        person.lat = coord["lat"]
                        person.lng = coord["lng"]
                    else:
                        person.lat = None
                        person.lng = None
                        log_system_event("WARNING", "GEOCODING", 
                                       f"좌표 변환 실패: {person.name}")
                
                save_missing_person(person)
                
                if person.id not in existing_ids:
                    new_persons.append(person)
                else:
                    updated_persons.append(person)
            
            if new_persons or updated_persons:
                print(f"📊 신규: {len(new_persons)}명, 갱신: {len(updated_persons)}명")
                log_system_event("INFO", "POLLING", 
                               f"데이터 업데이트: 신규 {len(new_persons)}명, 갱신 {len(updated_persons)}명")
                
                await manager.broadcast({
                    "type": "update",
                    "new": len(new_persons),
                    "updated": len(updated_persons)
                })
            
            print("⏰ 5분 후 다시 확인...")
            await asyncio.sleep(300)
            
        except Exception as e:
            print(f"❌ 폴링 오류: {e}")
            log_system_event("ERROR", "POLLING", f"폴링 오류: {e}")
            import traceback
            traceback.print_exc()
            await asyncio.sleep(60)

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

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket, "admin")
    try:
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)
            
            if message.get("type") == "ping":
                await manager.send_personal_message(websocket, {
                    "type": "pong", 
                    "timestamp": datetime.now().isoformat()
                })
            elif message.get("type") == "request_stats":
                stats = await get_real_time_stats()
                await manager.send_personal_message(websocket, {
                    "type": "stats_update", 
                    "data": stats
                })
                
    except WebSocketDisconnect:
        manager.disconnect(websocket)
        print("WebSocket 연결 해제")

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

@app.post("/api/missing_persons")
async def create_missing_person(request: Dict[str, Any] = Body(...)):
    try:
        print(f"신고 접수 요청 받음: {request}")
        
        missing_person_data = request.get("missing_person", {})
        photo_data = request.get("photo_data")
        
        if photo_data:
            if not photo_data.startswith('data:'):
                photo_data = f"data:image/jpeg;base64,{photo_data}"
            print(f"사진 데이터 길이: {len(photo_data)}자")
        else:
            print("사진 데이터 없음")

        person_id = str(uuid.uuid4())
        current_time = datetime.now().isoformat()
        
        missing_person = MissingPerson(
            id=person_id,
            name=missing_person_data.get("name"),
            age=missing_person_data.get("age"),
            gender=missing_person_data.get("gender"),
            location=missing_person_data.get("location"),
            description=missing_person_data.get("description"),
            photo_base64=photo_data,
            priority="HIGH",
            created_at=current_time,
            updated_at=current_time,
            source="REPORTER",
            category=_categorize_by_age(missing_person_data.get("age", 0)),
            last_seen=missing_person_data.get("missing_datetime"),
            emergency_contact=missing_person_data.get("reporter_phone")
        )
        
        if missing_person.location:
            coord = await geocode_address(missing_person.location)
            if coord:
                missing_person.lat = coord["lat"]
                missing_person.lng = coord["lng"]
        
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        # ✅ 24개 컬럼, 24개 값
        cursor.execute('''
            INSERT INTO missing_persons (
                id, name, age, gender, location, description, photo_url, photo_base64,
                priority, risk_factors, extracted_features, lat, lng,
                created_at, updated_at, status, category, source, confidence_score,
                last_seen, clothing_description, medical_condition, emergency_contact,
                approval_status
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            missing_person.id, 
            missing_person.name, 
            missing_person.age, 
            missing_person.gender,
            missing_person.location, 
            missing_person.description, 
            missing_person.photo_url,
            missing_person.photo_base64, 
            missing_person.priority,
            json.dumps(missing_person.risk_factors),
            json.dumps(missing_person.extracted_features or {}),
            missing_person.lat, 
            missing_person.lng,
            missing_person.created_at, 
            missing_person.updated_at,
            "ACTIVE", 
            missing_person.category, 
            missing_person.source,
            missing_person.confidence_score, 
            missing_person.last_seen,
            missing_person.clothing_description, 
            missing_person.medical_condition,
            missing_person.emergency_contact,
            "PENDING"
        ))
        
        conn.commit()
        conn.close()
        
        log_system_event("INFO", "REPORT", f"새로운 실종자 신고: {missing_person.name}")
        
        await manager.broadcast({
            "type": "new_report_pending",
            "person": missing_person.model_dump()
        })
        
        return {
            "success": True,
            "message": "실종자 신고가 접수되었습니다.",
            "person_id": person_id
        }
        
    except Exception as e:
        print(f"❌ 신고 접수 오류: {e}")
        import traceback
        traceback.print_exc()
        log_system_event("ERROR", "REPORT", f"신고 접수 실패: {e}")
        raise HTTPException(status_code=500, detail=str(e))

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
    
def _categorize_by_age(age: int) -> str:
    if age <= 6:
        return '미취학아동'
    elif age <= 18:
        return '학령기아동'
    elif age >= 65:
        return '치매환자'
    else:
        return '성인가출'

@app.get("/api/person/{person_id}")
async def get_person_detail(person_id: str):
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT id, name, age, gender, location, description, photo_url, photo_base64,
                   priority, risk_factors, extracted_features, lat, lng,
                   created_at, updated_at, status, category, source, confidence_score,
                   last_seen, clothing_description, medical_condition, emergency_contact,
                   approval_status, rejection_reason
            FROM missing_persons WHERE id = ?
        ''', (person_id,))
        
        row = cursor.fetchone()
        
        if not row:
            conn.close()
            raise HTTPException(status_code=404, detail="실종자를 찾을 수 없습니다")
        
        columns = [description[0] for description in cursor.description]
        person = dict(zip(columns, row))
        
        try:
            person['risk_factors'] = json.loads(person.get('risk_factors') or '[]')
            person['extracted_features'] = json.loads(person.get('extracted_features') or '{}')
        except:
            pass
        
        conn.close()
        
        print(f"API 응답: approval_status={person.get('approval_status')}, rejection_reason={person.get('rejection_reason')}")  # 디버깅 로그
        
        return person
        
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
            conn.close()
            raise HTTPException(status_code=404, detail="실종자를 찾을 수 없습니다")
        
        columns = [desc[0] for desc in cursor.description]
        person_dict = dict(zip(columns, person_row))
        
        try:
            if isinstance(person_dict.get('risk_factors'), str):
                person_dict['risk_factors'] = json.loads(person_dict['risk_factors']) if person_dict['risk_factors'] else []
            if isinstance(person_dict.get('extracted_features'), str):
                person_dict['extracted_features'] = json.loads(person_dict['extracted_features']) if person_dict['extracted_features'] else {}
        except json.JSONDecodeError as e:
            print(f"JSON 파싱 오류: {e}")
            person_dict['risk_factors'] = []
            person_dict['extracted_features'] = {}
        
        person = MissingPerson(**person_dict)
        
        success = await send_fcm_notification(person, request.message)
        
        conn.close()
        
        # WebSocket으로 실시간 알림 전송
        await manager.broadcast({
            "type": "new_missing_person_notification",
            "person": {
                "id": person.id,
                "name": person.name,
                "age": person.age,
                "gender": person.gender,
                "location": person.location,
                "description": person.description,
                "photo_base64": person.photo_base64,
                "priority": person.priority,
                "category": person.category,
                "extracted_features": person.extracted_features,
                "risk_factors": person.risk_factors,
                "lat": person.lat,
                "lng": person.lng,
            },
            "message": request.message,
            "target_count": len(request.target_tokens) if request.target_tokens else 0
        })
        
        return {
            "status": "success" if success else "failed",
            "message": "알림이 전송되었습니다" if success else "알림 전송에 실패했습니다",
            "target_count": len(request.target_tokens) if request.target_tokens else 0
        }
        
    except HTTPException:
        raise
    except Exception as e:
        log_system_event("ERROR", "NOTIFICATION", f"사용자 정의 알림 전송 실패: {e}")
        print(f"알림 전송 오류 상세: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/search_cctv")
async def search_cctv(request: CCTVRequest):
    try:
        cctv_data = await fetch_cctv_data(request.lat, request.lng, request.radius)
        
        processed_cctvs = []
        for cctv in cctv_data:
            cctv_id = cctv.get("CCTVID", "")
            cctv_name = cctv.get("CCTVNAME", "CCTV")
            kind = cctv.get("KIND", "E")
            ip = cctv.get("CCTVIP", "")
            ch = cctv.get("CH", "")
            cid = cctv.get("ID", "")
            passwd = cctv.get("PASSWD", "")
            
            stream_url = (
                f"https://www.utic.go.kr/jsp/map/cctvStream.jsp?"
                f"cctvid={cctv_id}&cctvname={cctv_name}"
                f"&kind={kind}&cctvip={ip}&cctvch={ch}"
                f"&id={cid}&cctvpasswd={passwd}"
            )
            
            processed_cctv = {
                "id": cctv_id,
                "name": cctv_name,
                "address": cctv.get("LOCATION", ""),
                "distance": 0,
                "status": "정상",
                "type": "교통감시",
                "operator": "대전교통정보센터",
                "stream_url": stream_url,
                "coords": {
                    "lat": float(cctv.get("YCOORD", 0)),
                    "lng": float(cctv.get("XCOORD", 0))
                }
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
        
        existing_ids = get_existing_person_ids()
        new_count = 0
        updated_count = 0
        
        for person_data in raw_data_list:
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
    
    firebase_status = "healthy" if firebase_messaging else "unhealthy"
    
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "components": {
            "database": db_status,
            "firebase": firebase_status,
            "api_manager": "healthy"
        },
        "version": "2.0.0",
        "uptime": time.time() - api_manager.last_request_time if api_manager.last_request_time else 0
    }

@app.post("/api/missing_persons/{person_id}/approve")
async def approve_missing_person(person_id: str):
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        cursor.execute('''
            UPDATE missing_persons 
            SET approval_status = 'APPROVED', 
                updated_at = ?
            WHERE id = ? AND source = 'REPORTER'
        ''', (datetime.now().isoformat(), person_id))
        
        if cursor.rowcount == 0:
            conn.close()
            raise HTTPException(status_code=404, detail="실종자를 찾을 수 없습니다")
        
        conn.commit()
        
        cursor.execute('SELECT * FROM missing_persons WHERE id = ?', (person_id,))
        person = cursor.fetchone()
        conn.close()
        
        if person and person[7]:
            try:
                print(f"SDXL 이미지 생성 시작: {person_id}")
                
                generator = get_generator()
                
                clean_base64 = person[7]
                if clean_base64.startswith('data:'):
                    clean_base64 = clean_base64.split(',')[1]
                
                clothing_description = person[5] or "일반적인 옷차림"
                age = person[2] or 30
                gender = person[3] or "남자"
                
                generated_base64 = generator.generate_missing_person_image(
                    original_photo_base64=clean_base64,
                    description=clothing_description,
                    age=age,
                    gender=gender
                )
                
                if generated_base64:
                    # 검증 추가
                    if generated_base64 and generated_base64.startswith('/9j/'):
                        print(f"올바른 이미지 생성, DB 업데이트")
                        
                        conn = sqlite3.connect('missing_persons.db')
                        cursor = conn.cursor()
                        cursor.execute('''
                            UPDATE missing_persons 
                            SET photo_base64 = ?, updated_at = ?
                            WHERE id = ?
                        ''', (generated_base64, datetime.now().isoformat(), person_id))
                        conn.commit()
                        conn.close()
                        
                        log_system_event("INFO", "IMAGE_GEN", f"SDXL 이미지 생성 완료: {person_id}")
                    else:
                        print(f"생성된 base64가 비정상적, 원본 유지")
                        print(f"시작 문자: {generated_base64[:50] if generated_base64 else 'None'}")
                else:
                    print(f"이미지 생성 실패, 원본 사용")
                    
            except Exception as e:
                print(f"이미지 생성 프로세스 오류: {e}")
                import traceback
                traceback.print_exc()
        
        log_system_event("INFO", "APPROVAL", f"실종자 승인: {person_id}")
        
        await manager.broadcast({
            "type": "person_approved",
            "person_id": person_id
        })
        
        return {"success": True, "message": "실종자가 승인되었습니다"}
        
    except Exception as e:
        log_system_event("ERROR", "APPROVAL", f"승인 실패: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/missing_persons/{person_id}/reject")
async def reject_missing_person(person_id: str, reason: str = Body(None)):
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        print(f"거절 처리: person_id={person_id}, reason={reason}")  # 디버깅 로그
        
        cursor.execute('''
            UPDATE missing_persons 
            SET approval_status = 'REJECTED',
                rejection_reason = ?,
                status = 'INACTIVE',
                updated_at = ?
            WHERE id = ? AND source = 'REPORTER'
        ''', (reason, datetime.now().isoformat(), person_id))
        
        print(f"업데이트된 행 수: {cursor.rowcount}")  # 디버깅 로그
        
        if cursor.rowcount == 0:
            conn.close()
            raise HTTPException(status_code=404, detail="실종자를 찾을 수 없습니다")
        
        conn.commit()
        conn.close()
        
        log_system_event("INFO", "APPROVAL", f"실종자 거절: {person_id}, 사유: {reason}")
        
        await manager.broadcast({
            "type": "person_rejected",
            "person_id": person_id
        })
        
        return {"success": True, "message": "실종자 신고가 거절되었습니다"}
        
    except Exception as e:
        log_system_event("ERROR", "APPROVAL", f"거절 실패: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/missing_persons/{person_id}")
async def delete_missing_person(person_id: str):
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        cursor.execute('''
            UPDATE missing_persons 
            SET status = 'DELETED', updated_at = ?
            WHERE id = ?
        ''', (datetime.now().isoformat(), person_id))
        
        if cursor.rowcount == 0:
            conn.close()
            raise HTTPException(status_code=404, detail="실종자를 찾을 수 없습니다")
        
        conn.commit()
        conn.close()
        
        log_system_event("INFO", "DELETE", f"실종자 삭제: {person_id}")
        
        await manager.broadcast({
            "type": "person_deleted",
            "person_id": person_id
        })
        
        return {"success": True, "message": "실종자가 삭제되었습니다"}
        
    except Exception as e:
        log_system_event("ERROR", "DELETE", f"삭제 실패: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# 5. 대기 중인 신고 목록 조회 API 추가
@app.get("/api/pending_reports")
async def get_pending_reports():
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        # approval_status 컬럼이 있는지 확인
        cursor.execute("PRAGMA table_info(missing_persons)")
        columns = [col[1] for col in cursor.fetchall()]
        
        if 'approval_status' in columns:
            # approval_status 컬럼이 있으면 사용
            cursor.execute('''
                SELECT id, name, age, gender, location, description, photo_base64,
                       created_at, last_seen, emergency_contact, category
                FROM missing_persons 
                WHERE source = 'REPORTER' AND approval_status = 'PENDING'
                ORDER BY created_at DESC
            ''')
        else:
            # approval_status 컬럼이 없으면 source만으로 필터링
            cursor.execute('''
                SELECT id, name, age, gender, location, description, photo_base64,
                       created_at, last_seen, emergency_contact, category
                FROM missing_persons 
                WHERE source = 'REPORTER' AND status = 'ACTIVE'
                ORDER BY created_at DESC
            ''')
        
        columns_names = [description[0] for description in cursor.description]
        reports = []
        
        for row in cursor.fetchall():
            report_dict = dict(zip(columns_names, row))
            reports.append(report_dict)
        
        conn.close()
        
        return {"reports": reports, "count": len(reports)}
        
    except Exception as e:
        log_system_event("ERROR", "API", f"대기 신고 조회 실패: {e}")
        print(f"Error in get_pending_reports: {e}")  # 디버깅용
        import traceback
        traceback.print_exc()  # 상세 에러 출력
        raise HTTPException(status_code=500, detail=str(e))
    
@app.get("/api/sighting_reports")
async def get_sighting_reports(status: str = "all"):
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        if status == "all":
            cursor.execute('''
                SELECT 
                    sr.id,
                    sr.person_id,
                    sr.reporter_id,
                    sr.reporter_lat as lat,
                    sr.reporter_lng as lng,
                    sr.description,
                    sr.photo_base64 as report_photo,
                    sr.confidence_level,
                    sr.status,
                    sr.reported_at as created_at,
                    mp.name as person_name,
                    mp.photo_base64 as person_photo
                FROM sighting_reports sr
                LEFT JOIN missing_persons mp ON sr.person_id = mp.id
                ORDER BY sr.reported_at DESC
                LIMIT 100
            ''')
        else:
            cursor.execute('''
                SELECT 
                    sr.id,
                    sr.person_id,
                    sr.reporter_id,
                    sr.reporter_lat as lat,
                    sr.reporter_lng as lng,
                    sr.description,
                    sr.photo_base64 as report_photo,
                    sr.confidence_level,
                    sr.status,
                    sr.reported_at as created_at,
                    mp.name as person_name,
                    mp.photo_base64 as person_photo
                FROM sighting_reports sr
                LEFT JOIN missing_persons mp ON sr.person_id = mp.id
                WHERE sr.status = ?
                ORDER BY sr.reported_at DESC
                LIMIT 100
            ''', (status,))
        
        reports = cursor.fetchall()
        columns = [desc[0] for desc in cursor.description]
        
        report_list = []
        for row in reports:
            report_dict = dict(zip(columns, row))
            report_list.append(report_dict)
        
        conn.close()
        
        return {
            "reports": report_list,
            "count": len(report_list)
        }
        
    except Exception as e:
        print(f"목격 신고 조회 오류: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/sighting_report/{report_id}")
async def get_sighting_report_by_id(report_id: int):
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        cursor.execute('SELECT * FROM sighting_reports WHERE id = ?', (report_id,))
        report = cursor.fetchone()
        
        if not report:
            conn.close()
            raise HTTPException(status_code=404, detail="신고를 찾을 수 없습니다")
        
        columns = [desc[0] for desc in cursor.description]
        report_dict = dict(zip(columns, report))
        
        conn.close()
        
        return report_dict
        
    except Exception as e:
        print(f"신고 조회 오류: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.patch("/api/sighting_report/{report_id}/status")
async def update_report_status(report_id: int, status: str):
    try:
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        # 신고 정보 가져오기
        cursor.execute('SELECT person_id FROM sighting_reports WHERE id = ?', (report_id,))
        report = cursor.fetchone()
        
        if not report:
            conn.close()
            raise HTTPException(status_code=404, detail="신고를 찾을 수 없습니다")
        
        person_id = report[0]
        
        # 상태 업데이트
        cursor.execute('''
            UPDATE sighting_reports 
            SET status = ?
            WHERE id = ?
        ''', (status, report_id))
        
        # CONFIRMED 상태가 되면 실종자도 "찾음" 상태로 변경
        if status == 'CONFIRMED':
            cursor.execute('''
                UPDATE missing_persons 
                SET status = 'FOUND', updated_at = CURRENT_TIMESTAMP
                WHERE id = ?
            ''', (person_id,))
            
            log_system_event("UPDATE", "MISSING_PERSON", f"실종자 {person_id} - 목격 확인됨으로 상태 변경")
            
            # WebSocket으로 실시간 알림
            await manager.broadcast({
                "type": "person_found",
                "person_id": person_id,
                "report_id": report_id,
                "message": "실종자가 발견되었습니다!"
            })
        
        conn.commit()
        conn.close()
        
        log_system_event("UPDATE", "SIGHTING_REPORT", f"신고 #{report_id} 상태 변경: {status}")
        
        return {
            "status": "success",
            "message": "확인됨" if status == 'CONFIRMED' else "상태가 업데이트되었습니다",
            "report_id": report_id,
            "new_status": status,
            "person_found": status == 'CONFIRMED'
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"신고 상태 업데이트 오류: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/sighting_report/{report_id}")
async def delete_sighting_report(report_id: int):
    try:
        print(f"신고 삭제 요청: ID {report_id}")
        
        conn = sqlite3.connect('missing_persons.db')
        cursor = conn.cursor()
        
        cursor.execute('SELECT id, person_id, status FROM sighting_reports WHERE id = ?', (report_id,))
        existing = cursor.fetchone()
        
        if not existing:
            conn.close()
            print(f"신고 {report_id}를 찾을 수 없음")
            raise HTTPException(status_code=404, detail=f"신고 #{report_id}를 찾을 수 없습니다")
        
        print(f"신고 찾음: {existing}")
        
        cursor.execute('DELETE FROM sighting_reports WHERE id = ?', (report_id,))
        deleted_count = cursor.rowcount
        
        conn.commit()
        conn.close()
        
        print(f"신고 {report_id} 삭제 완료 (삭제된 행: {deleted_count})")
        
        log_system_event("DELETE", "SIGHTING_REPORT", f"신고 #{report_id} 삭제됨")
        
        await manager.broadcast({
            "type": "sighting_report_deleted",
            "report_id": report_id
        })
        
        return {
            "status": "success",
            "message": "신고가 삭제되었습니다",
            "report_id": report_id,
            "deleted_count": deleted_count
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"신고 삭제 오류: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))
    
@app.get("/api/all_cctvs")
async def get_all_cctvs():
    UTIC_CCTV_URL = "https://www.utic.go.kr/map/mapcctv.do"
    
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
        "Referer": "https://www.utic.go.kr/map/map.do?menu=cctv",
        "X-Requested-With": "XMLHttpRequest",
        "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
    }
    
    data = {
        "cctvSearchCondition": "E07001",
        "type": "E"
    }
    
    try:
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.post(UTIC_CCTV_URL, headers=headers, data=data, timeout=15.0)
            
            if response.status_code == 200:
                cctvs = response.json()
                daejeon_cctvs = [c for c in cctvs if c.get("CENTERNAME") == "대전교통정보센터"]
                
                processed_cctvs = []
                for cctv in daejeon_cctvs:
                    cctv_id = cctv.get("CCTVID", "")
                    cctv_name = cctv.get("CCTVNAME", "CCTV")
                    kind = cctv.get("KIND", "E")
                    ip = cctv.get("CCTVIP", "")
                    ch = cctv.get("CH", "")
                    cid = cctv.get("ID", "")
                    passwd = cctv.get("PASSWD", "")
                    
                    stream_url = (
                        f"https://www.utic.go.kr/jsp/map/cctvStream.jsp?"
                        f"cctvid={cctv_id}&cctvname={cctv_name}"
                        f"&kind={kind}&cctvip={ip}&cctvch={ch}"
                        f"&id={cid}&cctvpasswd={passwd}"
                    )
                    
                    try:
                        lat = float(cctv.get("YCOORD", 0))
                        lng = float(cctv.get("XCOORD", 0))
                        if lat and lng:
                            processed_cctvs.append({
                                "id": cctv_id,
                                "name": cctv_name,
                                "address": cctv.get("LOCATION", ""),
                                "stream_url": stream_url,
                                "coords": {"lat": lat, "lng": lng}
                            })
                    except (ValueError, TypeError):
                        continue
                
                return {"cctvs": processed_cctvs, "count": len(processed_cctvs)}
            else:
                return {"cctvs": [], "count": 0}
                
    except Exception as e:
        print(f"전체 CCTV 로드 오류: {e}")
        return {"cctvs": [], "count": 0}
    
@app.get("/favicon.ico")
async def favicon():
    return FileResponse("static/favicon.ico")

@app.post("/api/get_environment")
async def get_environment(request: dict):
    """실종 위치 기준 동서남북 환경 분석"""
    try:
        lat = request.get("lat")
        lon = request.get("lon")
        
        print(f"🗺️  환경 분석: ({lat}, {lon})")
        
        # 500m 반경
        radius = 500
        
        # 각 방향별 환경
        directions = {
            "north": {"angle": 0, "lat_offset": 0.0045, "lon_offset": 0},
            "east": {"angle": 90, "lat_offset": 0, "lon_offset": 0.006},
            "south": {"angle": 180, "lat_offset": -0.0045, "lon_offset": 0},
            "west": {"angle": 270, "lat_offset": 0, "lon_offset": -0.006}
        }
        
        result = {}
        
        for direction, offset in directions.items():
            target_lat = lat + offset["lat_offset"]
            target_lon = lon + offset["lon_offset"]
            
            try:
                # 해당 방향 지점 반경 200m OSM 데이터
                tags = {
                    'highway': True,
                    'landuse': True,
                    'amenity': True,
                    'natural': True,
                    'building': True
                }
                
                gdf = ox.features_from_point((target_lat, target_lon), tags=tags, dist=200)
                
                # 도로 타입
                road_type = "골목길"
                if not gdf.empty and 'highway' in gdf.columns:
                    highways = gdf['highway'].dropna()
                    if len(highways) > 0:
                        hw = str(highways.iloc[0])
                        if 'primary' in hw or 'trunk' in hw:
                            road_type = "대로"
                        elif 'secondary' in hw or 'tertiary' in hw:
                            road_type = "이차로"
                
                # 토지 이용
                land_use = "주거지역"
                if not gdf.empty and 'landuse' in gdf.columns:
                    landuses = gdf['landuse'].dropna()
                    if len(landuses) > 0:
                        lu = str(landuses.iloc[0])
                        if 'commercial' in lu or 'retail' in lu:
                            land_use = "상업지역"
                        elif 'industrial' in lu:
                            land_use = "공업지역"
                        elif 'park' in lu or 'recreation' in lu:
                            land_use = "공원"
                
                # POI
                poi = []
                if not gdf.empty and 'amenity' in gdf.columns:
                    amenities = gdf['amenity'].dropna().unique()
                    for a in amenities[:3]:
                        if 'school' in str(a):
                            poi.append("학교")
                        elif 'hospital' in str(a):
                            poi.append("병원")
                        elif 'bus' in str(a):
                            poi.append("버스정류장")
                        elif 'park' in str(a):
                            poi.append("공원")
                        elif 'convenience' in str(a) or 'shop' in str(a):
                            poi.append("편의점")
                
                if not poi:
                    poi = ["없음"]
                
                # 위험 요소
                hazard = []
                if not gdf.empty and 'natural' in gdf.columns:
                    naturals = gdf['natural'].dropna()
                    if any('water' in str(n) or 'river' in str(n) for n in naturals):
                        hazard.append("하천")
                
                if not gdf.empty and 'highway' in gdf.columns:
                    highways = gdf['highway'].dropna()
                    if any('motorway' in str(h) or 'trunk' in str(h) for h in highways):
                        hazard.append("대형교차로")
                
                if not hazard:
                    hazard = ["없음"]
                
                result[direction] = {
                    "road_type": road_type,
                    "land_use": land_use,
                    "poi": poi,
                    "hazard": hazard,
                    "slope": "평지"
                }
                
            except Exception as e:
                print(f"⚠️  {direction} 방향 데이터 없음: {e}")
                result[direction] = {
                    "road_type": "골목길",
                    "land_use": "주거지역",
                    "poi": ["없음"],
                    "hazard": ["없음"],
                    "slope": "평지"
                }
        
        print(f"✅ 환경 분석 완료")
        return {"success": True, "environment": result}
        
    except Exception as e:
        print(f"❌ 환경 분석 오류: {e}")
        return {"success": False, "error": str(e)}
    
def translate_to_english(text: str) -> str:
    """DeepL로 한글을 영어로 번역"""
    if not text or not text.strip():
        return ""
    
    # 이미 영어면 그대로 반환
    if all(ord(c) < 128 for c in text if c.isalpha()):
        return text
    
    try:
        print(f"[DeepL] 번역 시도: {text}")
        
        url = "https://api-free.deepl.com/v2/translate"
        params = {
            "auth_key": DEEPL_API_KEY,
            "text": text,
            "source_lang": "KO",
            "target_lang": "EN-US"
        }
        
        response = requests.post(url, data=params, timeout=10)
        response.raise_for_status()
        
        result = response.json()
        translated = result["translations"][0]["text"]
        
        print(f"[DeepL] 번역 완료: {translated}")
        return translated
        
    except requests.exceptions.RequestException as e:
        print(f"DeepL API 오류: {e}")
        print(f"   원문 사용: {text}")
        return text
    except Exception as e:
        print(f"번역 실패: {e}")
        return text

@app.get("/")
async def get_admin_dashboard():
    import os
    print("📁 현재 작업 디렉터리:", os.getcwd())
    
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
    print(f"카카오 API 키 설정 상태: {'설정됨' if KAKAO_JAVASCRIPT_KEY else '미설정'}")
    print(f"Firebase 설정 상태: {'설정됨' if FIREBASE_CREDENTIALS else '미설정'}")
    print(f"ITS CCTV API 설정 상태: {'설정됨' if ITS_CCTV_API_KEY else '미설정'}")
    print("=" * 50)
    uvicorn.run(app, host="0.0.0.0", port=8001, reload=False)