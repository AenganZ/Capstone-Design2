import requests
import json
from datetime import datetime

def test_amber_list_api():
    url = 'https://www.safe182.go.kr/api/lcm/amberList.do'
    
    params = {
        'esntlId': '10000843',
        'authKey': '5a44c53f2b0e45e6',
        'rowSize': '10',
        'page': '1'
    }
    
    print("=" * 80)
    print("API 요청 시작")
    print("=" * 80)
    print(f"요청 시간: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"요청 URL: {url}")
    print(f"요청 메소드: POST")
    print("\n[요청 파라미터]")
    for key, value in params.items():
        print(f"  {key}: {value}")
    
    print("\n" + "-" * 80)
    print("API 호출 중...")
    print("-" * 80 + "\n")
    
    try:
        response = requests.post(url, data=params)
        
        print("[응답 정보]")
        print(f"상태 코드: {response.status_code}")
        print(f"응답 시간: {response.elapsed.total_seconds()}초")
        print(f"Content-Type: {response.headers.get('Content-Type', 'N/A')}")
        
        print("\n[응답 헤더]")
        for key, value in response.headers.items():
            print(f"  {key}: {value}")
        
        print("\n" + "=" * 80)
        print("응답 본문 (Raw JSON)")
        print("=" * 80)
        print(response.text)
        
        print("\n" + "=" * 80)
        print("응답 본문 (파싱된 데이터)")
        print("=" * 80)
        
        data = response.json()
        
        print(f"\n응답 코드 (result): {data.get('result', 'N/A')}")
        print(f"메시지 (msg): {data.get('msg', 'N/A')}")
        print(f"전체 개시글 수 (totalCount): {data.get('totalCount', 'N/A')}")
        
        if 'list' in data and data['list']:
            print(f"리스트 개수: {len(data['list'])}")
            
            for idx, item in enumerate(data['list'], 1):
                print("\n" + "=" * 80)
                print(f"항목 {idx}")
                print("=" * 80)
                
                fields = [
                    ('occrde', '발생일시'),
                    ('nm', '성명'),
                    ('ageNow', '현재나이'),
                    ('age', '당시나이'),
                    ('sexdstnDscd', '성별'),
                    ('writngTrgetDscd', '대상구분'),
                    ('occrAdres', '발생장소'),
                    ('height', '키'),
                    ('bdwgh', '몸무게'),
                    ('frmDscd', '체격'),
                    ('faceshpeDscd', '얼굴형'),
                    ('hairshpeDscd', '머리모양'),
                    ('haircolrDscd', '머리색상'),
                    ('alldressingDscd', '옷차림'),
                    ('tknphotolength', '사진크기')
                ]
                
                for field_key, field_name in fields:
                    value = item.get(field_key, '-')
                    print(f"{field_name}: {value}")
                
                print("\n[전체 필드]")
                for key, value in item.items():
                    print(f"  {key}: {value}")
        else:
            print("리스트가 비어있거나 존재하지 않습니다.")
        
        print("\n" + "=" * 80)
        print("API 요청 완료")
        print("=" * 80)
        
        return data
        
    except requests.exceptions.RequestException as e:
        print(f"\n[오류 발생]")
        print(f"요청 실패: {str(e)}")
        return None
    except json.JSONDecodeError as e:
        print(f"\n[오류 발생]")
        print(f"JSON 파싱 실패: {str(e)}")
        print(f"응답 내용: {response.text}")
        return None
    except Exception as e:
        print(f"\n[오류 발생]")
        print(f"예상치 못한 오류: {str(e)}")
        return None

if __name__ == "__main__":
    result = test_amber_list_api()