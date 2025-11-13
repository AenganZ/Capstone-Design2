from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
import folium
import requests
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
import os

app = FastAPI()

# ---------------------
# 1️⃣ 설정
# ---------------------
API_KEY = "J2MCgxEdNtsWgwc7LQyWldEJ42TmBIzhX6hlvZskihQ"  # ITS 국가교통정보센터 발급키
os.makedirs("templates", exist_ok=True)

# ---------------------
# 2️⃣ 대전 CCTV 데이터 수집 함수
# ---------------------
def fetch_cctv_data():
    url = f"https://www.utic.go.kr/guide/utisRefCctv.do?serviceKey={API_KEY}&numOfRows=100&type=json"
    r = requests.get(url, verify=False)
    if r.status_code != 200:
        print("[ERROR] ITS API 요청 실패:", r.status_code)
        return []

    data = r.json().get("response", {}).get("data", [])
    # 대전 지역 필터링 (위도·경도 기준)
    daejeon = []
    for cctv in data:
        lat = float(cctv.get("coordy", 0))
        lon = float(cctv.get("coordx", 0))
        if 36.25 <= lat <= 36.5 and 127.3 <= lon <= 127.5:
            daejeon.append({
                "name": cctv.get("cctvname", "Unknown"),
                "url": cctv.get("cctvurl"),
                "lat": lat,
                "lon": lon
            })
    return daejeon

# ---------------------
# 3️⃣ CCTV API 엔드포인트
# ---------------------
@app.get("/api/cctv_list")
def get_cctv_list():
    cctvs = fetch_cctv_data()
    return JSONResponse(content=cctvs)

# ---------------------
# 4️⃣ 지도 페이지
# ---------------------
@app.get("/", response_class=HTMLResponse)
async def map_page(request: Request):
    m = folium.Map(location=[36.35, 127.38], zoom_start=12)
    cctvs = fetch_cctv_data()

    for cctv in cctvs:
        popup_html = f"""
        <div style="width:260px">
            <b>{cctv['name']}</b><br>
            <video width="250" height="180" controls autoplay muted>
                <source src="{cctv['url']}" type="application/vnd.apple.mpegurl">
                Your browser does not support the video tag.
            </video>
        </div>
        """
        folium.Marker(
            location=[cctv['lat'], cctv['lon']],
            popup=folium.Popup(popup_html, max_width=270),
            tooltip=cctv['name']
        ).add_to(m)

    map_path = "templates/map.html"
    m.save(map_path)
    with open(map_path, encoding="utf-8") as f:
        return HTMLResponse(content=f.read())

# ---------------------
# 5️⃣ 정적 파일 (필요 시)
# ---------------------
app.mount("/static", StaticFiles(directory="static"), name="static")

# ---------------------
# 6️⃣ 실행 명령
# ---------------------
# uvicorn dashboard:app --reload
