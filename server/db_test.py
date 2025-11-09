import sqlite3
import os

def reset_database():
    db_path = 'missing_persons.db'
    
    print("=" * 80)
    print("데이터베이스 초기화")
    print("=" * 80)
    
    if not os.path.exists(db_path):
        print(f"\n⚠️ 데이터베이스 파일이 없습니다: {db_path}")
        print("서버를 먼저 실행해서 데이터베이스를 생성하세요.")
        return
    
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        cursor.execute("SELECT COUNT(*) FROM missing_persons WHERE status = 'ACTIVE'")
        before_count = cursor.fetchone()[0]
        
        print(f"\n현재 활성 실종자: {before_count}명")
        print("\n데이터베이스를 초기화합니다...")
        print("(모든 실종자 데이터가 삭제됩니다)")
        
        response = input("\n계속하시겠습니까? (yes/no): ")
        if response.lower() != 'yes':
            print("\n취소되었습니다.")
            conn.close()
            return
        
        cursor.execute("DELETE FROM missing_persons")
        conn.commit()
        
        cursor.execute("SELECT COUNT(*) FROM missing_persons")
        after_count = cursor.fetchone()[0]
        
        conn.close()
        
        print(f"\n✅ 데이터베이스 초기화 완료")
        print(f"삭제된 레코드: {before_count}개")
        print(f"현재 레코드: {after_count}개")
        print("\n다음 단계:")
        print("1. 서버를 재시작하세요")
        print("2. 관리자 대시보드에서 '수동 업데이트' 버튼을 클릭하세요")
        print("3. Safe182에서 최신 데이터를 다시 가져옵니다")
        
    except sqlite3.Error as e:
        print(f"\n❌ 데이터베이스 오류: {e}")
    except Exception as e:
        print(f"\n❌ 오류: {e}")

def view_database():
    db_path = 'missing_persons.db'
    
    print("=" * 80)
    print("데이터베이스 내용 확인")
    print("=" * 80)
    
    if not os.path.exists(db_path):
        print(f"\n⚠️ 데이터베이스 파일이 없습니다: {db_path}")
        return
    
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT id, name, age, gender, location, created_at, status 
            FROM missing_persons 
            WHERE status = 'ACTIVE'
            ORDER BY created_at DESC
        """)
        
        persons = cursor.fetchall()
        
        print(f"\n활성 실종자: {len(persons)}명\n")
        
        if persons:
            for idx, person in enumerate(persons, 1):
                person_id, name, age, gender, location, created_at, status = person
                print(f"[{idx}] {name} ({age}세, {gender})")
                print(f"    위치: {location}")
                print(f"    등록: {created_at}")
                print(f"    ID: {person_id[:16]}...")
                print()
        else:
            print("등록된 실종자가 없습니다.")
        
        conn.close()
        
    except sqlite3.Error as e:
        print(f"\n❌ 데이터베이스 오류: {e}")

if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1:
        if sys.argv[1] == "reset":
            reset_database()
        elif sys.argv[1] == "view":
            view_database()
        else:
            print("사용법:")
            print("  python db_manager.py view   - 데이터베이스 내용 확인")
            print("  python db_manager.py reset  - 데이터베이스 초기화")
    else:
        print("=" * 80)
        print("데이터베이스 관리 도구")
        print("=" * 80)
        print("\n1. 데이터베이스 내용 확인")
        print("2. 데이터베이스 초기화")
        print("0. 종료")
        
        choice = input("\n선택: ")
        
        if choice == "1":
            view_database()
        elif choice == "2":
            reset_database()
        else:
            print("종료합니다.")