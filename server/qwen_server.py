import os, json, re, time
from typing import List, Optional, Dict, Any
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
import torch
from transformers import AutoTokenizer, AutoModelForTokenClassification
import numpy as np

class RawDataList(BaseModel):
    raw_data_list: List[dict]

class ProcessedPerson(BaseModel):
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
    lat: float = 36.5
    lng: float = 127.8
    created_at: str = ""
    status: str = "ACTIVE"
    category: Optional[str] = None

class MissingPersonAI:
    def __init__(self):
        self.model = None
        self.tokenizer = None
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        print(f"Qwen 디바이스: {self.device}")
        self.load_model()
    
    def load_model(self):
        try:
            print("Qwen2.5-3B-Instruct 모델 로딩 중...")
            from transformers import AutoModelForCausalLM
            
            self.tokenizer = AutoTokenizer.from_pretrained(
                "Qwen/Qwen2.5-3B-Instruct",
                trust_remote_code=True
            )
            
            self.model = AutoModelForCausalLM.from_pretrained(
                "Qwen/Qwen2.5-3B-Instruct",
                torch_dtype=torch.float16 if self.device == "cuda" else torch.float32,
                device_map="auto",
                trust_remote_code=True
            )
            
            print("Qwen 모델 로딩 완료")
        except Exception as e:
            print(f"Qwen 모델 로드 실패: {e}")
            self.model = None
    
    def analyze_missing_person(self, description: str, age: Optional[int] = None, gender: Optional[str] = None) -> Dict[str, Any]:
        """Qwen으로 실종자 정보를 한 번에 분석"""
        if not self.model:
            return self._get_fallback_analysis(age, gender)
        
        if not description or not description.strip():
            return self._get_fallback_analysis(age, gender)
        
        try:
            prompt = f"""다음 실종자 정보를 분석하여 JSON 형식으로 출력하세요.

실종자 정보:
- 나이: {age}세
- 성별: {gender}
- 상세 설명: {description}

다음 JSON 형식으로 출력하세요:
{{
    "ner_entities": {{
        "diseases": ["질병1", "질병2"],
        "drugs": ["약물"],
        "clothing": ["의류"],
        "colors": ["색상"],
        "locations": ["위치"],
        "transport": ["교통수단"],
        "physical_features": ["신체특징"],
        "behaviors": ["행동"],
        "items": ["소지품"]
    }},
    "extracted_features": {{
        "physical": ["키 165cm", "마른 체형"],
        "clothing": ["상의 파란색 티셔츠", "하의 청바지"],
        "medical": ["치매 약 복용"],
        "behavior": ["혼자 외출", "배회"],
        "items": ["지갑 없음", "휴대폰 소지"],
        "additional": ["평상시 공원 산책"]
    }},
    "risk_factors": ["치매 관련 질환", "배회 위험", "독거 생활"],
    "category": "치매환자",
    "priority": "HIGH"
}}

category는 다음 중 하나: 미취학아동, 학령기아동, 성인, 고령자, 치매환자, 지적장애인, 자폐장애인, 정신장애인, 성인가출, 기타
priority는 다음 중 하나: HIGH, MEDIUM, LOW

규칙:
- 8세 이하, 80세 이상은 무조건 HIGH
- 치매환자는 무조건 HIGH
- 정신질환, 거동불편은 HIGH
- 나머지는 MEDIUM

반드시 유효한 JSON만 출력하세요."""

            messages = [
                {"role": "system", "content": "당신은 실종자 정보 분석 전문가입니다. JSON 형식으로만 응답하세요."},
                {"role": "user", "content": prompt}
            ]
            
            text_input = self.tokenizer.apply_chat_template(
                messages,
                tokenize=False,
                add_generation_prompt=True
            )
            
            model_inputs = self.tokenizer([text_input], return_tensors="pt").to(self.device)
            
            with torch.no_grad():
                generated_ids = self.model.generate(
                    model_inputs.input_ids,
                    max_new_tokens=1024,
                    temperature=0.3,
                    top_p=0.9,
                    do_sample=True
                )
            
            generated_ids = [
                output_ids[len(input_ids):] for input_ids, output_ids in zip(model_inputs.input_ids, generated_ids)
            ]
            
            response = self.tokenizer.batch_decode(generated_ids, skip_special_tokens=True)[0]
            
            response = response.strip()
            if "```json" in response:
                response = response.split("```json")[1].split("```")[0].strip()
            elif "```" in response:
                response = response.split("```")[1].split("```")[0].strip()
            
            result = json.loads(response)
            
            print(f"Qwen 분석 완료: category={result.get('category')}, priority={result.get('priority')}")
            
            return result
            
        except Exception as e:
            print(f"Qwen 분석 오류: {e}")
            import traceback
            traceback.print_exc()
            return self._get_fallback_analysis(age, gender)
        
    def translate_to_english(self, korean_text: str) -> str:
        """한글 의류 설명을 영어 구문으로 번역"""
        if not korean_text or not korean_text.strip():
            return ""
        
        if not self.model:
            return korean_text
        
        try:
            prompt = f"""Translate to English only. No explanations.

Korean: 검은 캡모자, 회색 후드티, 청바지
English: black baseball cap, gray hoodie, blue jeans

Korean: 비니, 패딩, 검은 바지
English: beanie, padded jacket, black pants

Korean: 야구 캡, 흰 티셔츠, 운동화
English: baseball cap, white t-shirt, wearing sneakers

Korean: {korean_text}
English:"""

            messages = [
                {
                    "role": "system", 
                    "content": "You translate Korean to English. Output only the English translation. No explanations."
                },
                {
                    "role": "user", 
                    "content": prompt
                }
            ]
            
            print(f"[번역 요청] {korean_text}")
            
            text = self.tokenizer.apply_chat_template(
                messages,
                tokenize=False,
                add_generation_prompt=True
            )
            
            model_inputs = self.tokenizer([text], return_tensors="pt").to(self.device)
            
            with torch.no_grad():
                generated_ids = self.model.generate(
                    **model_inputs,
                    max_new_tokens=100,
                    temperature=0.3,
                    top_p=0.9,
                    do_sample=True,
                    pad_token_id=self.tokenizer.pad_token_id,
                    eos_token_id=self.tokenizer.eos_token_id
                )
            
            generated_ids = [
                output_ids[len(input_ids):] 
                for input_ids, output_ids in zip(model_inputs.input_ids, generated_ids)
            ]
            
            response = self.tokenizer.batch_decode(generated_ids, skip_special_tokens=True)[0]
            
            english_text = response.strip().split('\n')[0].strip()
            
            for prefix in ["English:", "Translation:", "Output:", "Result:", "Korean:", "->", "："]:
                if english_text.startswith(prefix):
                    english_text = english_text[len(prefix):].strip()
            
            english_text = english_text.replace('"', '').replace("'", '')
            
            import re
            english_text = re.sub(r'\([^)]*\)', '', english_text)
            english_text = ' '.join(english_text.split())
            
            if not english_text or len(english_text) < 3:
                print(f"⚠️ 번역 결과 없음, 원본 사용")
                return korean_text
            
            if "translate" in english_text.lower() or "following" in english_text.lower():
                print(f"⚠️ 메타 설명 감지, 원본 사용")
                return korean_text
            
            print(f"[번역 결과] {english_text}")
            
            return english_text
            
        except Exception as e:
            print(f"번역 오류: {e}")
            return korean_text

    def _extract_keywords_from_sentence(self, sentence: str) -> str:
        """문장에서 키워드만 추출"""
        import re
        
        # 숫자+단위 추출 (178cm, 67kg 등)
        numbers = re.findall(r'\d+(?:cm|kg|m)', sentence)
        
        # 형용사 추출
        adjectives = []
        adj_patterns = [
            r'(slim|slender|muscular|thin|athletic|chubby)',
            r'(short|long|medium|straight|curly|wavy)\s+hair',
            r'(black|white|gray|blue|red|green|brown|yellow)\s+\w+',
        ]
        for pattern in adj_patterns:
            matches = re.findall(pattern, sentence, re.IGNORECASE)
            adjectives.extend(matches if isinstance(matches[0], str) else [' '.join(m) for m in matches])
        
        # 명사 추출
        nouns = []
        noun_patterns = [
            r'(hoodie|jacket|shirt|pants|joggers|jeans|dress|skirt)',
            r'(shoes|sneakers|boots|sandals)',
            r'(glasses|sunglasses)',
            r'(bag|backpack)',
        ]
        for pattern in noun_patterns:
            matches = re.findall(pattern, sentence, re.IGNORECASE)
            nouns.extend(matches)
        
        keywords = numbers + adjectives + nouns
        return ', '.join(keywords) if keywords else sentence
    
    def _get_fallback_analysis(self, age: Optional[int] = None, gender: Optional[str] = None) -> Dict[str, Any]:
        """Qwen 실패 시 기본 분석"""
        category = "기타"
        priority = "MEDIUM"
        
        if age:
            if age <= 8:
                category = "미취학아동"
                priority = "HIGH"
            elif age <= 18:
                category = "학령기아동"
            elif age >= 80:
                category = "고령자"
                priority = "HIGH"
            elif age >= 65:
                category = "고령자"
                priority = "HIGH"
        
        risk_factors = []
        if age:
            if age >= 80:
                risk_factors.append("고령자(80세 이상)")
            elif age >= 65:
                risk_factors.append("고령자(65세 이상)")
            elif age <= 10:
                risk_factors.append("어린이(10세 이하)")
        
        return {
            "ner_entities": {},
            "extracted_features": {
                "basic_info": [f"{age}세" if age else "", gender or ""],
            },
            "risk_factors": risk_factors,
            "category": category,
            "priority": priority
        }

class TranslateRequest(BaseModel):
    text: str

def process_base64_image(base64_string: str) -> str:
    if not base64_string:
        return None
    
    try:
        if base64_string.startswith('data:'):
            return base64_string
        
        return f"data:image/jpeg;base64,{base64_string}"
    except Exception as e:
        print(f"이미지 처리 오류: {e}")
        return None

def process_missing_person(raw_data: dict, ner_model: MissingPersonAI) -> ProcessedPerson:
    import hashlib
    
    # etcSpfeatr을 주요 설명으로 사용
    description = raw_data.get("etcSpfeatr", "") or ""
    photo_base64 = raw_data.get("tknphotoFile", "") or ""
    
    name = raw_data.get('nm', '이름없음')
    print(f"NER 서버에서 처리 중: {name}")
    
    age = None
    try:
        age_value = raw_data.get("ageNow") or raw_data.get("age")
        if age_value:
            age = int(age_value)
    except (ValueError, TypeError):
        pass
    
    gender = raw_data.get("sexdstnDscd", "")
    
    # 고유 ID 생성
    unique_key = f"{name}_{age}_{gender}_{raw_data.get('occrde', '')}_{raw_data.get('occrAdres', '')}"
    person_id = raw_data.get("msspsnIdntfccd") or hashlib.md5(unique_key.encode()).hexdigest()

    # etcSpfeatr이 있으면 NER 처리
    ner_entities = {}
    extracted_features = {
        "basic_info": [],
        "appearance": [],
        "clothing": [],
        "behavior": [],
        "health": [],
        "items": [],
        "transport": [],
        "additional": []
    }
    
    print(f"Qwen으로 분석 중: {name}")
    analysis = ner_model.analyze_missing_person(description, age, gender)

    ner_entities = analysis.get("ner_entities", {})
    extracted_features = analysis.get("extracted_features", {})
    risk_factors = analysis.get("risk_factors", [])
    category = analysis.get("category", "기타")
    priority = analysis.get("priority", "MEDIUM")

    if description and description.strip():
        if "추가정보" not in extracted_features:
            extracted_features["추가정보"] = []
        etcSpfeatr_lines = [line.strip() for line in description.split('\n') if line.strip()]
        extracted_features["추가정보"].extend(etcSpfeatr_lines)
    
    # 사진 처리
    photo_url = None
    print(f"[디버그] 사진 데이터 길이: {len(photo_base64) if photo_base64 else 0}")  # 여기 추가
    print(f"[디버그] 사진 데이터 시작 문자: {photo_base64[:20] if photo_base64 and len(photo_base64) > 20 else 'NONE'}")  # 여기 추가

    if photo_base64 and len(photo_base64) > 50:
        try:
            if photo_base64.startswith('data:'):
                photo_url = photo_base64
            elif photo_base64.startswith('/9j/'):
                photo_url = f"data:image/jpeg;base64,{photo_base64}"
            elif photo_base64.startswith('iVBORw0'):
                photo_url = f"data:image/png;base64,{photo_base64}"
            else:
                photo_url = f"data:image/jpeg;base64,{photo_base64}"
            print(f"[디버그] photo_url 생성 성공: {len(photo_url) if photo_url else 0}자")  # 여기 추가
        except Exception as e:
            print(f"사진 처리 오류: {e}")
            photo_url = None
    else:
        print(f"[디버그] 사진 데이터 없음 또는 너무 짧음")
    
    # 최종 description 생성 (화면 표시용)
    final_description = description if description else f"{age}세 {gender}"
    
    return ProcessedPerson(
        id=str(person_id),
        name=name,
        age=age,
        gender=gender,
        location=raw_data.get("occrAdres"),
        description=final_description,
        photo_url=photo_url,
        photo_base64=photo_base64,
        priority=priority,
        risk_factors=risk_factors,
        ner_entities=ner_entities,
        extracted_features=extracted_features,
        category=category,
        created_at=datetime.now().isoformat()
    )

app = FastAPI(title="QWEN 서버")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

ner_model = MissingPersonAI()

@app.post("/api/translate")
async def translate_korean_to_english(request: TranslateRequest):
    """한글을 영어로 번역"""
    try:
        translation = ner_model.translate_to_english(request.text)
        return {
            "success": True,
            "original": request.text,
            "translation": translation
        }
    except Exception as e:
        print(f"번역 API 오류: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/process_missing_persons")
async def process_missing_persons_endpoint(request: RawDataList):
    try:
        print(f"NER 서버: {len(request.raw_data_list)}명의 실종자 데이터 처리 시작")
        
        processed_persons = []
        for raw_data in request.raw_data_list:
            processed_person = process_missing_person(raw_data, ner_model)
            processed_persons.append(processed_person.model_dump())
        
        print(f"NER 서버: {len(processed_persons)}명의 데이터 처리 완료")
        return processed_persons
        
    except Exception as e:
        print(f"NER 처리 오류: {e}")
        raise HTTPException(status_code=500, detail=f"NER 처리 실패: {str(e)}")

@app.get("/api/health")
async def health_check():
    return {
        "status": "healthy",
        "model_loaded": ner_model.model is not None,
        "timestamp": datetime.now().isoformat()
    }

@app.get("/")
async def root():
    return {"message": "NER 처리 서버가 실행 중입니다", "port": 8000}

if __name__ == "__main__":
    import uvicorn
    print("NER 서버를 시작합니다 (포트 8000)")
    uvicorn.run(app, host="0.0.0.0", port=8000, reload=False)