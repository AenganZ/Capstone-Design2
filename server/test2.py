import requests
import json
import os
from datetime import datetime, timedelta
from dotenv import load_dotenv

load_dotenv()

# --------------------------------------------------------------------------------------
# 유틸
# --------------------------------------------------------------------------------------

def mask(s: str, keep: int = 4) -> str:
    if not s:
        return ""
    return f"{s[:keep]}***"

def parse_possible_date(s: str):
    """YYYYMMDD 또는 YYYY-MM-DD를 파싱"""
    if not s:
        return None
    s = str(s).strip()
    for fmt in ("%Y%m%d", "%Y-%m-%d"):
        try:
            return datetime.strptime(s, fmt)
        except Exception:
            pass
    return None

def pick_date_field(rec: dict):
    """응답 레코드에서 발생일자 후보 키를 추정"""
    for k in ["occrde", "occrYmd", "occrDate", "occrDt", "occr_ymd"]:
        if k in rec and rec.get(k):
            return k
    for k, v in rec.items():
        sv = str(v)
        if (len(sv) == 8 and sv.isdigit()) or (len(sv) == 10 and sv[4] == "-" and sv[7] == "-"):
            if parse_possible_date(sv):
                return k
    return None

def safe_json(response):
    """JSON 아닐 때 대비"""
    try:
        return response.json()
    except Exception:
        return None

def pretty(obj):
    try:
        return json.dumps(obj, ensure_ascii=False, indent=2)
    except Exception:
        return str(obj)

def encode_params(d: dict):
    """
    requests에 반복키(writngTrgetDscds 등)를 정확히 전달하기 위해
    dict -> list[tuple]로 평탄화
    """
    items = []
    for k, v in d.items():
        if v is None:
            continue
        if isinstance(v, (list, tuple)):
            for vv in v:
                if vv is None:
                    continue
                items.append((k, str(vv)))
        else:
            items.append((k, str(v)))
    return items

# --------------------------------------------------------------------------------------
# API 호출
# --------------------------------------------------------------------------------------

def test_api_with_params(params_name: str, params: dict, url: str):
    """대전 + 최근 3개월 고정 파라미터로 API 테스트"""
    print("\n" + "=" * 100)
    print(f"테스트: {params_name}")
    print("=" * 100)
    print("요청 URL:", url)
    print("파라미터:")
    for key, value in params.items():
        if key in ["esntlId", "authKey"]:
            print(f"  {key}: {mask(value)}")
        else:
            print(f"  {key}: {value}")

    try:
        response = requests.post(url, data=encode_params(params), timeout=30)

        if response.status_code != 200:
            print(f"❌ HTTP {response.status_code}")
            text = response.text.strip()
            if text:
                print("응답 본문(앞 500자):")
                print(text[:500])
            return None

        data = safe_json(response)
        if data is None:
            print("❌ JSON 파싱 실패 (XML/HTML 응답 가능). 앞 500자 미리보기:")
            print(response.text[:500])
            return None

        result_code = data.get("result", "N/A")
        result_msg = data.get("msg", "N/A")

        print(f"\n응답 코드: {result_code}")
        print(f"응답 메시지: {result_msg}")

        if result_code != "00":
            print("❌ API 오류 코드")
            return None

        persons = data.get("list") or []
        if not persons:
            print("⚠️  데이터 없음")
            return []

        print(f"✅ 결과 {len(persons)}건")

        # 간단 프리뷰
        today = datetime.now()
        for i, p in enumerate(persons[:10], start=1):
            name = p.get("nm") or p.get("name") or "?"
            target = p.get("writngTrgetDscd") or p.get("trgtCd") or "-"
            sex = p.get("sexdstnDscd") or p.get("sex") or "-"
            date_key = pick_date_field(p)
            date_str = p.get(date_key) if date_key else None
            out = f"  - {i:02d}) {name} | 대상:{target} | 성별:{sex}"
            if date_str:
                dt = parse_possible_date(date_str)
                if dt:
                    days_ago = (today - dt).days
                    out += f" | 발생:{date_str} ({days_ago}일 전)"
                else:
                    out += f" | 발생:{date_str}"
            print(out)

        if len(persons) > 10:
            print(f"  ... (이하 {len(persons) - 10}건 생략)")

        return persons

    except Exception as e:
        print(f"❌ 예외: {e}")
        return None

# --------------------------------------------------------------------------------------
# 메인: '대전 + 최근 3개월' 고정
# --------------------------------------------------------------------------------------

def main():
    esntl_id = os.getenv("SAFE182_ESNTL_ID", "")
    auth_key = os.getenv("SAFE182_AUTH_KEY", "")
    use_icm = os.getenv("USE_ICM_ENDPOINT", "false").lower() in ("1", "true", "yes", "y")

    if not esntl_id or not auth_key:
        print("=" * 100)
        print("❌ API 인증정보가 없습니다!")
        print("=" * 100)
        print("\n.env 파일에 설정하세요:")
        print("SAFE182_ESNTL_ID=your_id")
        print("SAFE182_AUTH_KEY=your_key")
        print("USE_ICM_ENDPOINT=true  # (선택) icm 엔드포인트 사용 시")
        return

    base_url = "https://www.safe182.go.kr/api/icm/findChildList.do" if use_icm \
        else "https://www.safe182.go.kr/api/lcm/findChildList.do"

    print("=" * 100)
    print("Safe182 findChildList 대전 + 최근 3개월 테스트")
    print("=" * 100)
    print(f"테스트 시각: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"엔드포인트: {base_url}")

    # 오늘 기준 3개월(≈90일) 전 ~ 오늘
    today = datetime.now()
    days_90_ago = today - timedelta(days=90)
    date_hyphen_start = days_90_ago.strftime("%Y-%m-%d")
    date_hyphen_end = today.strftime("%Y-%m-%d")

    # 고정 파라미터
    params = {
        "esntlId": esntl_id,
        "authKey": auth_key,
        "rowSize": "100",        # 문서상 최대 100
        "page": "1",
        "xmlUseYN": "N",         # JSON 응답
        "occrAdres": "대전",      # 발생장소=대전
        "detailDate1": date_hyphen_start,  # 시작일(YYYY-MM-DD)
        "detailDate2": date_hyphen_end,    # 종료일(YYYY-MM-DD)
        # 필요 시 대상코드 사용 (주석 해제)
        # "writngTrgetDscds": ["010", "060", "070"],  # 010:정상아동, 060:지적장애인, 070:치매질환자
    }

    _ = test_api_with_params("대전 + 최근 3개월", params, base_url)

if __name__ == "__main__":
    main()
