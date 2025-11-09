import requests
import json
import os
from datetime import datetime, timedelta
from dotenv import load_dotenv

load_dotenv()

def test_api_with_params(params_name, params):
    """특정 파라미터 조합으로 API 테스트"""
    url = 'https://www.safe182.go.kr/api/lcm/amberList.do'
    
    print("\n" + "=" * 80)
    print(f"테스트: {params_name}")
    print("=" * 80)
    print("파라미터:")
    for key, value in params.items():
        if key in ['esntlId', 'authKey']:
            print(f"  {key}: {value[:4]}***")
        else:
            print(f"  {key}: {value}")
    
    try:
        response = requests.post(url, data=params, timeout=30)
        
        if response.status_code != 200:
            print(f"❌ HTTP {response.status_code}")
            return None
        
        data = response.json()
        result_code = data.get('result', 'N/A')
        result_msg = data.get('msg', 'N/A')
        
        print(f"\n응답 코드: {result_code}")
        print(f"응답 메시지: {result_msg}")
        
        if result_code != '00':
            print(f"❌ API 오류")
            return None
        
        if 'list' not in data or not data['list']:
            print("❌ 실종자 없음")
            return []
        
        persons = data['list']
        print(f"✅ 실종자 {len(persons)}명 발견")
        
        # 날짜 분석
        today = datetime.now()
        for person in persons:
            name = person.get('nm', '?')
            occrde = person.get('occrde', '')
            
            if occrde and len(occrde) >= 8:
                try:
                    person_date = datetime.strptime(occrde, '%Y%m%d')
                    days_ago = (today - person_date).days
                    print(f"  - {name}: {occrde} ({days_ago}일 전)")
                except:
                    print(f"  - {name}: {occrde}")
        
        return persons
        
    except Exception as e:
        print(f"❌ 오류: {e}")
        return None

def main():
    esntl_id = os.getenv("SAFE182_ESNTL_ID", "")
    auth_key = os.getenv("SAFE182_AUTH_KEY", "")
    
    if not esntl_id or not auth_key:
        print("=" * 80)
        print("❌ API 인증정보가 없습니다!")
        print("=" * 80)
        print("\n.env 파일에 설정하세요:")
        print("SAFE182_ESNTL_ID=your_id")
        print("SAFE182_AUTH_KEY=your_key")
        return
    
    print("=" * 80)
    print("Safe182 API 파라미터 조합 테스트")
    print("=" * 80)
    print(f"테스트 시각: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    # 날짜 계산
    today = datetime.now()
    days_90_ago = today - timedelta(days=90)
    
    date_yyyymmdd_start = days_90_ago.strftime("%Y%m%d")
    date_yyyymmdd_end = today.strftime("%Y%m%d")
    date_hyphen_start = days_90_ago.strftime("%Y-%m-%d")
    date_hyphen_end = today.strftime("%Y-%m-%d")
    
    # 기본 파라미터
    base_params = {
        'esntlId': esntl_id,
        'authKey': auth_key,
        'rowSize': '100',
        'page': '1',
        'occrAdres': '대전'
    }
    
    # 테스트 1: 파라미터 없이 (대전만)
    test1 = base_params.copy()
    result1 = test_api_with_params("테스트 1: 날짜 파라미터 없음 (대전만)", test1)
    
    # 테스트 2: occrde1, occrde2 (YYYYMMDD)
    test2 = base_params.copy()
    test2['occrde1'] = date_yyyymmdd_start
    test2['occrde2'] = date_yyyymmdd_end
    result2 = test_api_with_params("테스트 2: occrde1/occrde2 (YYYYMMDD)", test2)
    
    # 테스트 3: detailDate1, detailDate2 (YYYY-MM-DD)
    test3 = base_params.copy()
    test3['detailDate1'] = date_hyphen_start
    test3['detailDate2'] = date_hyphen_end
    result3 = test_api_with_params("테스트 3: detailDate1/detailDate2 (YYYY-MM-DD)", test3)
    
    # 테스트 4: detailDate1, detailDate2 (YYYYMMDD)
    test4 = base_params.copy()
    test4['detailDate1'] = date_yyyymmdd_start
    test4['detailDate2'] = date_yyyymmdd_end
    result4 = test_api_with_params("테스트 4: detailDate1/detailDate2 (YYYYMMDD)", test4)
    
    # 테스트 5: startDate, endDate (YYYY-MM-DD)
    test5 = base_params.copy()
    test5['startDate'] = date_hyphen_start
    test5['endDate'] = date_hyphen_end
    result5 = test_api_with_params("테스트 5: startDate/endDate (YYYY-MM-DD)", test5)
    
    # 테스트 6: 대전 제외하고 날짜만
    test6 = {
        'esntlId': esntl_id,
        'authKey': auth_key,
        'rowSize': '100',
        'page': '1',
        'detailDate1': date_hyphen_start,
        'detailDate2': date_hyphen_end
    }
    result6 = test_api_with_params("테스트 6: 대전 제외 + detailDate1/2", test6)
    
    # 테스트 7: rowSize 증가
    test7 = base_params.copy()
    test7['rowSize'] = '500'
    result7 = test_api_with_params("테스트 7: rowSize 500 (대전만)", test7)
    
    # 테스트 8: 전국 조회
    test8 = {
        'esntlId': esntl_id,
        'authKey': auth_key,
        'rowSize': '100',
        'page': '1'
    }
    result8 = test_api_with_params("테스트 8: 전국 조회 (지역 필터 없음)", test8)
    
    # 결과 요약
    print("\n" + "=" * 80)
    print("테스트 결과 요약")
    print("=" * 80)
    
    results = [
        ("테스트 1: 대전만", result1),
        ("테스트 2: occrde1/2", result2),
        ("테스트 3: detailDate1/2 (하이픈)", result3),
        ("테스트 4: detailDate1/2 (숫자)", result4),
        ("테스트 5: startDate/endDate", result5),
        ("테스트 6: 대전 제외", result6),
        ("테스트 7: rowSize 500", result7),
        ("테스트 8: 전국", result8)
    ]
    
    for name, result in results:
        if result is None:
            status = "❌ 실패"
        elif len(result) == 0:
            status = "⚠️  데이터 없음"
        else:
            status = f"✅ {len(result)}명"
        print(f"{name}: {status}")
    
    print("\n" + "=" * 80)
    print("결론")
    print("=" * 80)
    
    # 어느 테스트가 제일 많은 데이터를 가져왔는지 확인
    max_result = None
    max_count = 0
    max_name = ""
    
    for name, result in results:
        if result and len(result) > max_count:
            max_count = len(result)
            max_result = result
            max_name = name
    
    if max_count > 0:
        print(f"\n가장 많은 데이터를 가져온 테스트: {max_name} ({max_count}명)")
        print("\n⚠️ 모든 테스트가 동일한 결과를 반환하면 API가 날짜 필터를 지원하지 않을 수 있습니다.")
    else:
        print("\n❌ 모든 테스트가 실패하거나 데이터가 없습니다.")
        print("가능한 원인:")
        print("  1. API 인증 문제")
        print("  2. 최근 3개월간 대전에 실종자가 없음")
        print("  3. API 서비스 장애")

if __name__ == "__main__":
    main()