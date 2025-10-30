import os
import io
import base64
import torch
import cv2
import numpy as np
import requests
from PIL import Image, ImageDraw
from diffusers import StableDiffusionXLInpaintPipeline, AutoencoderKL
import mediapipe as mp

class MissingPersonImageGenerator:
    def __init__(self):
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        print(f"이미지 생성 디바이스: {self.device}")
        
        self.inpaint_pipeline = None
        self.face_detection = None
        
    def initialize_models(self):
        try:
            print("SDXL Inpaint 파이프라인 로딩 중...")
            
            self.inpaint_pipeline = StableDiffusionXLInpaintPipeline.from_pretrained(
                "diffusers/stable-diffusion-xl-1.0-inpainting-0.1",
                torch_dtype=torch.float16
            ).to(self.device)
            
            self.inpaint_pipeline.enable_model_cpu_offload()
            
            print("Face Detection 초기화 중...")
            self.face_detection = mp.solutions.face_detection.FaceDetection(
                model_selection=1,
                min_detection_confidence=0.5
            )
            
            print("모델 로딩 완료")
            return True
            
        except Exception as e:
            print(f"모델 초기화 오류: {e}")
            return False
    
    def base64_to_image(self, base64_string: str) -> Image.Image:
        if base64_string.startswith('data:'):
            base64_string = base64_string.split(',')[1]
        
        image_data = base64.b64decode(base64_string)
        image = Image.open(io.BytesIO(image_data)).convert('RGB')
        return image
    
    def image_to_base64(self, image: Image.Image) -> str:
        """이미지를 base64로 변환 (JPEG)"""
        buffered = io.BytesIO()
        
        # RGBA를 RGB로 변환
        if image.mode in ('RGBA', 'LA', 'P'):
            rgb_image = Image.new('RGB', image.size, (255, 255, 255))
            rgb_image.paste(image, mask=image.split()[-1] if image.mode == 'RGBA' else None)
            image = rgb_image
        elif image.mode != 'RGB':
            image = image.convert('RGB')
        
        # JPEG로 저장
        image.save(buffered, format="JPEG", quality=95, optimize=True)
        
        # base64 인코딩
        img_bytes = buffered.getvalue()
        img_str = base64.b64encode(img_bytes).decode('utf-8')
        
        print(f"[이미지 변환] base64 길이: {len(img_str)}")
        print(f"[이미지 변환] 시작 문자: {img_str[:30]}")
        
        if not img_str.startswith('/9j/'):
            print(f"❌ 경고: JPEG base64가 /9j/로 시작하지 않음!")
            return None
        
        print(f"✅ 올바른 JPEG base64 생성됨")
        return img_str
    
    def detect_face_core_region(self, image: Image.Image):
        """얼굴 핵심 부분만 감지 (눈/코/입만, 안경/모자 제외)"""
        image_np = np.array(image)
        image_rgb = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
        
        results = self.face_detection.process(image_rgb)
        
        if not results.detections:
            print("⚠️ 얼굴 감지 실패")
            return None
        
        h, w = image_np.shape[:2]
        detection = results.detections[0]
        bbox = detection.location_data.relative_bounding_box
        
        x = int(bbox.xmin * w)
        y = int(bbox.ymin * h)
        width = int(bbox.width * w)
        height = int(bbox.height * h)
        
        # 얼굴 영역 축소 (안경/모자 제외하고 눈/코/입만)
        shrink_ratio = 0.2  # 20% 축소
        x_shrink = int(width * shrink_ratio / 2)
        y_shrink = int(height * shrink_ratio / 2)
        
        x = x + x_shrink
        y = y + y_shrink
        width = width - x_shrink * 2
        height = height - y_shrink * 2
        
        # 상단 더 축소 (이마/머리카락/모자 제외)
        y_top_shrink = int(height * 0.15)
        y = y + y_top_shrink
        height = height - y_top_shrink
        
        x = max(0, x)
        y = max(0, y)
        width = max(width, 50)
        height = max(height, 50)
        
        print(f"✅ 얼굴 핵심 부분만 감지: ({x}, {y}, {width}, {height})")
        
        return (x, y, width, height)
    
    def create_body_mask(self, image: Image.Image, face_bbox):
        """얼굴 핵심 부분만 보호하는 마스크 생성 (안경/모자는 생성 가능)"""
        # 흰색 = 생성할 영역, 검은색 = 유지할 영역
        mask = Image.new('L', image.size, 255)
        
        if face_bbox:
            x, y, w, h = face_bbox
            draw = ImageDraw.Draw(mask)
            
            # 작은 타원형으로 눈/코/입만 보호
            draw.ellipse([x, y, x + w, y + h], fill=0)
            
            print(f"✅ 얼굴 핵심만 보호 (안경/모자 제외)")
        
        return mask
    
    def parse_accessories(self, description: str) -> dict:
        """설명에서 악세서리 정보 추출"""
        desc_lower = description.lower()
        
        accessories = {
            "has_glasses": False,
            "has_hat": False,
            "glasses_desc": "",
            "hat_desc": ""
        }
        
        # 안경 체크
        glasses_keywords = ["안경", "glasses", "선글라스", "sunglasses"]
        for keyword in glasses_keywords:
            if keyword in desc_lower:
                accessories["has_glasses"] = True
                # 안경 종류 추출
                if "검정" in description or "black" in desc_lower:
                    accessories["glasses_desc"] = "black glasses"
                elif "금" in description or "gold" in desc_lower:
                    accessories["glasses_desc"] = "gold glasses"
                else:
                    accessories["glasses_desc"] = "glasses"
                break
        
        # 모자 체크
        hat_keywords = ["모자", "hat", "캡", "cap", "비니", "beanie"]
        for keyword in hat_keywords:
            if keyword in desc_lower:
                accessories["has_hat"] = True
                # 모자 종류 추출
                if "야구" in description or "baseball" in desc_lower:
                    accessories["hat_desc"] = "baseball cap"
                elif "비니" in description or "beanie" in desc_lower:
                    accessories["hat_desc"] = "beanie"
                else:
                    accessories["hat_desc"] = "hat"
                break
        
        return accessories
    
    def translate_description_to_english(self, korean_desc: str) -> str:
        """NER 서버의 Qwen으로 번역"""
        if not korean_desc or not korean_desc.strip():
            return ""
        
        try:
            print(f"[번역 요청] {korean_desc}")  # 전체 출력
            
            response = requests.post(
                'http://localhost:8000/api/translate',
                json={"text": korean_desc},
                timeout=30
            )
            
            if response.status_code == 200:
                data = response.json()
                translation = data.get("translation", korean_desc)
                print(f"[번역 완료] {translation}")
                return translation
            else:
                print(f"번역 API 실패: {response.status_code}")
                return korean_desc
                
        except requests.exceptions.ConnectionError:
            print("⚠️ NER 서버 연결 실패 - 원본 사용")
            return korean_desc
        except Exception as e:
            print(f"번역 오류: {e}")
            return korean_desc
    
    def generate_missing_person_image(
        self,
        original_photo_base64: str,
        description: str,
        age: int,
        gender: str
    ) -> str:
        try:
            if not self.inpaint_pipeline:
                self.initialize_models()
            
            original_image = self.base64_to_image(original_photo_base64)
            original_image = original_image.resize((1024, 1024))
            
            face_bbox = self.detect_face_core_region(original_image)
            
            if not face_bbox:
                print("⚠️ 얼굴 감지 실패 - 원본 반환")
                return original_photo_base64.split(',')[1] if ',' in original_photo_base64 else original_photo_base64
            
            body_mask = self.create_body_mask(original_image, face_bbox)
            accessories = self.parse_accessories(description)
            
            # gender 정보를 description에 추가
            full_description = f"{gender}, {age}세, {description}"
            print(f"[전체 설명] {full_description}")
            
            # 한글 설명 (성별 포함)을 영어 키워드로 번역
            english_desc = self.translate_description_to_english(full_description)
            
            # gender 정보는 이미 번역에 포함되어 있으므로 별도로 추가 안 함
            
            # 간결한 프롬프트 구성
            prompt = f"photo, Korean person, {english_desc}"
            
            # 안경 추가
            if accessories["has_glasses"]:
                prompt += f", {accessories['glasses_desc']}"
            else:
                prompt += ", no glasses"
            
            # 모자 추가
            if accessories["has_hat"]:
                prompt += f", {accessories['hat_desc']}"
            else:
                prompt += ", no hat"
            
            prompt += ", realistic, detailed"
            
            # Negative prompt
            negative = "cartoon, anime, different face, low quality, blurry"
            
            if not accessories["has_glasses"]:
                negative += ", glasses, eyewear"
            
            if not accessories["has_hat"]:
                negative += ", hat, cap"
            
            print("이미지 생성 중...")
            print(f"[프롬프트 길이] {len(prompt.split())} 단어")
            print(f"[프롬프트] {prompt}")
            print(f"[안경] {accessories['has_glasses']}, [모자] {accessories['has_hat']}")
            
            generated_image = self.inpaint_pipeline(
                prompt=prompt,
                negative_prompt=negative,
                image=original_image,
                mask_image=body_mask,
                num_inference_steps=40,
                guidance_scale=8.0,
                strength=0.95
            ).images[0]
            
            print("✅ 이미지 생성 완료")
            
            result_base64 = self.image_to_base64(generated_image)
            
            return result_base64
            
        except Exception as e:
            print(f"이미지 생성 오류: {e}")
            import traceback
            traceback.print_exc()
            return None

generator = None

def get_generator():
    global generator
    if generator is None:
        generator = MissingPersonImageGenerator()
    return generator