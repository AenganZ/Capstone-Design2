import os
import json
import torch
import re
from typing import Dict, Any, Optional
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from transformers import AutoTokenizer, AutoModelForCausalLM, BitsAndBytesConfig

BASE_MODEL_NAME = "K-intelligence/Midm-2.0-Mini-Instruct"


class PredictionRequest(BaseModel):
    person: Dict[str, Any]
    environment: Dict[str, Dict[str, Any]]
    lat: float
    lon: float


class PredictionResponse(BaseModel):
    success: bool
    prediction: Optional[Dict[str, Dict[str, Any]]] = None
    error: Optional[str] = None


class MovementPredictor:
    def __init__(self, model_path: str = "./movement_predictor_model_v2"):
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        print(f"🚀 디바이스: {self.device}")
        self.model = None
        self.tokenizer = None
        self.load_model()

    def load_model(self):
        try:
            print(f"📦 베이스 Midm-2.0 로딩")
            
            self.tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL_NAME, trust_remote_code=True)
            
            if self.tokenizer.pad_token is None:
                self.tokenizer.pad_token = self.tokenizer.eos_token
                self.tokenizer.pad_token_id = self.tokenizer.eos_token_id

            bnb_config = BitsAndBytesConfig(
                load_in_4bit=True,
                bnb_4bit_quant_type="nf4",
                bnb_4bit_compute_dtype=torch.bfloat16,
                bnb_4bit_use_double_quant=True,
            )

            self.model = AutoModelForCausalLM.from_pretrained(
                BASE_MODEL_NAME,
                quantization_config=bnb_config,
                trust_remote_code=True,
                torch_dtype=torch.bfloat16,
            )
            
            self.model.eval()
            print("✅ 완료")
            
        except Exception as e:
            print(f"❌ {e}")
            raise

    def create_prompt(self, person: Dict, environment: Dict) -> str:
        p_cat = person.get('category', '기타')
        p_age = person.get('age', 30)
        p_sex = person.get('sex', 'M')
        sex_kor = "남성" if p_sex == "M" else "여성"
        
        # 환경 강조
        env_lines = []
        for d in ["north", "east", "south", "west"]:
            e = environment.get(d, {})
            parts = []
            
            road = e.get('road_type', '없음')
            if road != '없음':
                parts.append(f"도로:{road}")
            
            land = e.get('land_use', '없음')
            if land != '없음':
                parts.append(f"토지:{land}")
            
            poi = e.get('poi', [])
            if poi and poi != ['없음']:
                parts.append(f"POI:{','.join(poi)}")
            
            hazard = e.get('hazard', [])
            if hazard and hazard != ['없음']:
                parts.append(f"⚠️위험:{','.join(hazard)}")
            
            env_lines.append(f"• {d.upper()}: {' | '.join(parts) if parts else '특이사항 없음'}")
        
        env_str = "\n".join(env_lines)
        
        prompt = f"""실종자 이동 경로 예측 (환경 분석 필수!)

【실종자】
분류: {p_cat} / 나이: {p_age}세 / 성별: {sex_kor}

【각 방향 환경 - 반드시 고려할 것】
{env_str}

【분석 규칙】
✓ 공원/학교 → 아동·고령자 선호
✓ 하천/급경사/대형교차로 → 위험 회피
✓ 대로/버스/지하철 → 가출 성인 선호
✓ 상업지역 → 가출 선호, 주거지역 → 가출 회피

반드시 위 환경 차이를 반영하여 JSON 출력:
{{"north":{{"prob":숫자,"reason":"환경근거"}},"east":{{"prob":숫자,"reason":"환경근거"}},"south":{{"prob":숫자,"reason":"환경근거"}},"west":{{"prob":숫자,"reason":"환경근거"}}}}"""
        
        return prompt

    def predict(self, person: Dict, environment: Dict) -> Dict[str, Dict[str, Any]]:
        if self.model is None:
            raise Exception("모델 미로드")

        # 환경 동일성 체크
        envs = [environment.get(d, {}) for d in ["north", "east", "south", "west"]]
        
        all_same = all(
            env.get('road_type') == envs[0].get('road_type') and
            env.get('land_use') == envs[0].get('land_use') and
            env.get('poi') == envs[0].get('poi') and
            env.get('hazard') == envs[0].get('hazard')
            for env in envs
        )
        
        if all_same:
            print("⚠️  환경 동일 → 균등 분포")
            return {
                "north": {"prob": 25.0, "reason": "사방 환경 동일"},
                "east": {"prob": 25.0, "reason": "사방 환경 동일"},
                "south": {"prob": 25.0, "reason": "사방 환경 동일"},
                "west": {"prob": 25.0, "reason": "사방 환경 동일"},
            }

        print("\n=== 환경 입력 (차이 있음) ===")
        for d in ["north", "east", "south", "west"]:
            print(f"{d}: {environment.get(d, {})}")
        print("=" * 50)

        for attempt in range(2):
            try:
                prompt = self.create_prompt(person, environment)
                
                messages = [
                    {"role": "system", "content": "환경 차이를 반영하여 JSON 출력"},
                    {"role": "user", "content": prompt},
                ]

                text = self.tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
                enc = self.tokenizer(text, return_tensors="pt", return_token_type_ids=False)
                inputs = {
                    "input_ids": enc["input_ids"].to(self.device),
                    "attention_mask": enc["attention_mask"].to(self.device),
                }

                print(f"🤖 추론 {attempt+1}/2")

                with torch.no_grad():
                    outputs = self.model.generate(
                        input_ids=inputs["input_ids"],
                        attention_mask=inputs["attention_mask"],
                        max_new_tokens=600,
                        temperature=0.5,
                        top_p=0.9,
                        do_sample=True,
                        pad_token_id=self.tokenizer.pad_token_id,
                    )

                response_text = self.tokenizer.decode(
                    outputs[0][inputs["input_ids"].shape[1]:],
                    skip_special_tokens=True,
                )

                print(f"📝 응답: {response_text}")
                
                prediction = self.parse_response(response_text)
                
                if prediction:
                    print(f"✅ 성공")
                    for d in ["north", "east", "south", "west"]:
                        print(f"   {d}: {prediction[d]['prob']}% - {prediction[d]['reason'][:30]}")
                    return prediction
                        
            except Exception as e:
                print(f"❌ {e}")
        
        raise Exception("2번 실패")

    def parse_response(self, text: str) -> Optional[Dict]:
        text = text.strip().replace("'", '"')
        text = re.sub(r'```[\w]*', '', text).replace('```', '')
        
        # 개별 추출 (더 안전)
        result = {}
        for d in ["north", "east", "south", "west"]:
            prob_match = re.search(rf'"{d}"[^}}]*?"prob"[^:]*?:\s*([\d.]+)', text)
            reason_match = re.search(rf'"{d}"[^}}]*?"reason"[^:]*?:\s*"([^"]*)"', text)
            
            if prob_match:
                prob_val = float(prob_match.group(1))
                if prob_val < 1.5:  # 0~1 사이면 100 곱하기
                    prob_val *= 100
                
                result[d] = {
                    "prob": int(prob_val),
                    "reason": reason_match.group(1) if reason_match else "분석 결과"
                }
        
        # 4방향 안 채워졌으면 균등 분배
        if len(result) < 4:
            missing = [d for d in ["north", "east", "south", "west"] if d not in result]
            for d in missing:
                result[d] = {"prob": 25, "reason": "정보 부족"}
        
        return self.normalize(result) if len(result) == 4 else None
    
    def normalize(self, pred: Dict) -> Dict:
        total = sum(pred[d]["prob"] for d in ["north", "east", "south", "west"])
        if total == 0:
            for d in ["north", "east", "south", "west"]:
                pred[d]["prob"] = 25.0
        else:
            for d in ["north", "east", "south", "west"]:
                pred[d]["prob"] = round(pred[d]["prob"] * 100.0 / total, 1)
        
        for d in ["north", "east", "south", "west"]:
            if "reason" not in pred[d] or not pred[d]["reason"]:
                pred[d]["reason"] = "분석"

            reason = pred[d]["reason"]

            reason = reason.replace('. ', '.\n')
            reason = reason.replace('。 ', '。\n')

            if len(reason) > 200:
                reason = reason[:197] + "..."

            pred[d]["reason"] = reason
        
        return pred


app = FastAPI(title="이동 경로 예측 서버")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

predictor = MovementPredictor()


@app.post("/api/predict_movement", response_model=PredictionResponse)
async def predict_movement(request: PredictionRequest):
    try:
        prediction = predictor.predict(request.person, request.environment)
        return PredictionResponse(success=True, prediction=prediction)
    except Exception as e:
        print(f"실패: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/health")
async def health_check():
    return {"status": "healthy", "model_loaded": predictor.model is not None}


@app.get("/")
async def root():
    return {"message": "이동 경로 예측 서버", "port": 8002}


if __name__ == "__main__":
    import uvicorn
    print("🚀 서버 시작 (포트 8002)")
    uvicorn.run(app, host="0.0.0.0", port=8002, reload=False)