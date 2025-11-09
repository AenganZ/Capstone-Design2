import os
import io
import base64
import torch
import cv2
import numpy as np
import requests
from PIL import Image
from diffusers import StableDiffusionXLPipeline, EulerDiscreteScheduler
from insightface.app import FaceAnalysis
from huggingface_hub import hf_hub_download
import insightface
from compel import Compel, ReturnedEmbeddingsType

class MissingPersonImageGenerator:
    def __init__(self):
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        print(f"이미지 생성 디바이스: {self.device}")
        
        self.sdxl_pipeline = None
        self.face_analyzer = None
        self.face_swapper = None
        self.compel = None
        
    def initialize_models(self):
        try:
            print("=== Face Swap + Compel 모델 초기화 시작 ===")
            
            # 1. InsightFace
            print("1. InsightFace 초기화 중...")
            self.face_analyzer = FaceAnalysis(
                name='buffalo_l',
                providers=['CPUExecutionProvider']
            )
            self.face_analyzer.prepare(ctx_id=0, det_size=(640, 640))
            print("✅ InsightFace 로딩 완료")
            
            # 2. Face Swapper (로컬만 사용)
            print("2. Face Swapper 모델 로딩 중 (로컬)...")
            swapper_path = "./models/inswapper_128.onnx"
            
            if not os.path.exists(swapper_path):
                print(f"❌ Face Swapper 파일 없음: {swapper_path}")
                print(f"   모델을 다음 경로에 배치하세요: {swapper_path}")
                self.face_swapper = None
            else:
                self.face_swapper = insightface.model_zoo.get_model(swapper_path)
                print(f"✅ Face Swapper 로딩 완료 (로컬: {swapper_path})")
            
            # 3. SDXL 파이프라인
            print("3. SDXL 파이프라인 로딩 중...")
            self.sdxl_pipeline = StableDiffusionXLPipeline.from_pretrained(
                "stabilityai/stable-diffusion-xl-base-1.0",
                torch_dtype=torch.float16,
                variant="fp16"
            ).to(self.device)
            
            self.sdxl_pipeline.scheduler = EulerDiscreteScheduler.from_config(
                self.sdxl_pipeline.scheduler.config
            )
            
            print("✅ SDXL 파이프라인 로딩 완료")
            
            # 4. Compel 초기화
            print("4. Compel 초기화 중 (긴 프롬프트 지원)...")
            self.compel = Compel(
                tokenizer=[self.sdxl_pipeline.tokenizer, self.sdxl_pipeline.tokenizer_2],
                text_encoder=[self.sdxl_pipeline.text_encoder, self.sdxl_pipeline.text_encoder_2],
                returned_embeddings_type=ReturnedEmbeddingsType.PENULTIMATE_HIDDEN_STATES_NON_NORMALIZED,
                requires_pooled=[False, True]
            )
            print("✅ Compel 초기화 완료!")
            
            print("=== 모든 모델 로딩 완료 ===")
            return True
            
        except Exception as e:
            print(f"모델 초기화 오류: {e}")
            import traceback
            traceback.print_exc()
            return False
    
    def extract_source_face(self, image: Image.Image):
        try:
            image_np = np.array(image)
            image_bgr = cv2.cvtColor(image_np, cv2.COLOR_RGB2BGR)
            
            faces = self.face_analyzer.get(image_bgr)
            
            if not faces or len(faces) == 0:
                print("⚠️ 얼굴 감지 실패")
                return None
            
            face = faces[0]
            
            print(f"✅ 원본 얼굴 추출 성공")
            print(f"   - 신뢰도: {face.det_score:.2f}")
            
            return face
            
        except Exception as e:
            print(f"얼굴 추출 오류: {e}")
            return None
    
    def align_face_angle(self, face_kps):
        try:
            left_eye = face_kps[0]
            right_eye = face_kps[1]
            
            delta_y = right_eye[1] - left_eye[1]
            delta_x = right_eye[0] - left_eye[0]
            angle = np.degrees(np.arctan2(delta_y, delta_x))
            
            return angle
            
        except Exception as e:
            return 0
    
    def swap_face_with_alignment(self, target_image: Image.Image, source_face):
        try:
            if not self.face_swapper:
                print("❌ Face Swapper 없음")
                return target_image
            
            target_np = np.array(target_image)
            target_bgr = cv2.cvtColor(target_np, cv2.COLOR_RGB2BGR)
            
            target_faces = self.face_analyzer.get(target_bgr)
            
            if not target_faces or len(target_faces) == 0:
                print("⚠️ 타겟 이미지에 얼굴 없음")
                return target_image
            
            best_face = None
            best_score = -1
            
            for face in target_faces:
                bbox = face.bbox
                face_size = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
                angle = abs(self.align_face_angle(face.kps))
                score = face_size * (1.0 / (1.0 + angle / 10.0))
                
                if score > best_score:
                    best_score = score
                    best_face = face
            
            if not best_face:
                best_face = target_faces[0]
            
            print(f"선택된 얼굴 각도: {self.align_face_angle(best_face.kps):.1f}도")
            
            print("얼굴 교체 중...")
            result = self.face_swapper.get(target_bgr, best_face, source_face, paste_back=True)
            
            result_rgb = cv2.cvtColor(result, cv2.COLOR_BGR2RGB)
            result_image = Image.fromarray(result_rgb)
            
            print("✅ 얼굴 교체 완료")
            
            return result_image
            
        except Exception as e:
            print(f"Face Swap 오류: {e}")
            import traceback
            traceback.print_exc()
            return target_image
    
    def base64_to_image(self, base64_string: str) -> Image.Image:
        if base64_string.startswith('data:'):
            base64_string = base64_string.split(',')[1]
        
        image_data = base64.b64decode(base64_string)
        image = Image.open(io.BytesIO(image_data)).convert('RGB')
        return image
    
    def image_to_base64(self, image: Image.Image) -> str:
        buffered = io.BytesIO()
        
        if image.mode != 'RGB':
            image = image.convert('RGB')
        
        image.save(buffered, format="JPEG", quality=95)
        img_str = base64.b64encode(buffered.getvalue()).decode('utf-8')
        
        if not img_str.startswith('/9j/'):
            return None
        
        print(f"✅ JPEG base64 생성 완료")
        return img_str
    
    def translate_description_to_english(self, korean_desc: str) -> str:
        try:
            response = requests.post(
                'http://localhost:8000/api/translate',
                json={"text": korean_desc},
                timeout=30
            )
            if response.status_code == 200:
                return response.json().get("translation", korean_desc)
        except:
            pass
        return korean_desc
    
    def generate_missing_person_image(
        self,
        original_photo_base64: str,
        description: str,
        age: int,
        gender: str
    ) -> str:
        try:
            if not self.sdxl_pipeline:
                self.initialize_models()
            
            print("\n=== Face Swap + Compel 전신 이미지 생성 시작 ===")
            
            # 1. 원본에서 얼굴 추출
            print("\n1단계: 원본 얼굴 추출")
            original_image = self.base64_to_image(original_photo_base64)
            
            source_face = self.extract_source_face(original_image)
            
            if not source_face:
                print("⚠️ 얼굴 추출 실패 - 원본 반환")
                return original_photo_base64.split(',')[1] if ',' in original_photo_base64 else original_photo_base64
            
            # 2. 프롬프트 생성
            print("\n2단계: 긴 프롬프트 생성")
            
            english_desc = self.translate_description_to_english(description)
            
            print(f"[번역된 설명] {english_desc}")
            
            gender_en = "male" if gender == "남성" else "female"
            
            prompt = f"""professional full body portrait photograph,
Korean {gender_en} person, {age} years old,
{english_desc},
standing is not allowed.
seated on a simple backless stool (seat height 45–50cm), slight anterior pelvic tilt.
camera at eye level to the torso (navel to chest height), 70–100mm lens, distance ~3–4m to avoid distortion.
front view; centered; full body visible head to toe; no cropping.
natural relaxed posture: torso leaning forward 5–10°, shoulders neutral.
knees shoulder-width (90–100° angle), lower legs slightly forward so trousers and shoes are fully visible; feet flat, toes pointing forward.
hands resting lightly on thighs, fingers naturally separated; detailed hands (nails, knuckles) without covering garments.
plain white seamless background; clean studio lighting; soft key 45° camera-left, gentle rim light; fill -1EV; even professional exposure; sharp focus; photorealistic fashion lookbook.
trousers show realistic fabric drape and subtle knee folds; hem sits lightly on shoes; socks minimal and unobtrusive.
shoes fully visible (uppers and a hint of outsole), no perspective exaggeration.
cap/logo minimal without readable text."""
            
            negative_prompt = """portrait only, headshot, close-up, upper body only, half body, cropped, cut off, cut feet, cut shoes,
standing pose, crouching, squatting, lying down, kneeling, bent over,
side view, profile view, back view, rear view, turned away,
looking away, looking down, looking up, eyes closed, head turned,
crossed legs, legs tucked under chair, hands covering clothes, clenched fists, slouching, leaning back too far,
busy background, props, chair back, armrests,
wide-angle distortion, big head, foreshortened head, fisheye, extreme perspective, dutch angle,
cartoon, anime, illustration, drawing, painting, sketch, rendered, CGI, 3D,
low quality, blurry, out of focus, motion blur, distorted, deformed, ugly, bad anatomy, bad hands, extra fingers,
multiple people, crowd, duplicated, duplicate person, extra limbs, missing limbs,
text, watermark, readable logo, frame, border,
dark, underexposed, overexposed, harsh shadows, color cast, uneven lighting,
partial body crop,
hood up, hood worn, hood forward, hood visible around the head, hood framing the face,
hood touching/overlapping/covering the cap or brim, hood covering ears,
hood casting shadow onto the cap,
wearing the hood when wearing a hoodie (hood must not be worn),
beanie when baseball cap requested, knit cap when baseball cap requested,
baseball cap when beanie requested, curved brim when beanie requested,
wrong hat type, incorrect headwear"""
            
            print(f"[프롬프트] {prompt}")
            print(f"[프롬프트 단어 수] {len(prompt.split())}")
            
            # 3. Compel로 긴 프롬프트 처리
            print("\n3단계: Compel로 프롬프트 인코딩")
            
            conditioning_result = self.compel(prompt)
            negative_conditioning_result = self.compel(negative_prompt)
            
            # 튜플 언팩킹
            if isinstance(conditioning_result, tuple) and len(conditioning_result) == 2:
                conditioning, pooled_conditioning = conditioning_result
                negative_conditioning, negative_pooled = negative_conditioning_result
                print("✅ 프롬프트 인코딩 완료 (pooled 포함)")
            else:
                conditioning = conditioning_result
                negative_conditioning = negative_conditioning_result
                pooled_conditioning = None
                negative_pooled = None
                print("✅ 프롬프트 인코딩 완료")
            
            # 4. SDXL로 템플릿 생성
            print("\n4단계: SDXL 전신 템플릿 생성")
            print("   (약 20-30초 소요)")
            
            generator = torch.Generator(device=self.device).manual_seed(42)
            
            if pooled_conditioning is not None:
                template_image = self.sdxl_pipeline(
                    prompt_embeds=conditioning,
                    pooled_prompt_embeds=pooled_conditioning,
                    negative_prompt_embeds=negative_conditioning,
                    negative_pooled_prompt_embeds=negative_pooled,
                    num_inference_steps=35,
                    guidance_scale=8.5,
                    height=1024,
                    width=768,
                    generator=generator
                ).images[0]
            else:
                template_image = self.sdxl_pipeline(
                    prompt_embeds=conditioning,
                    negative_prompt_embeds=negative_conditioning,
                    num_inference_steps=35,
                    guidance_scale=8.5,
                    height=1024,
                    width=768,
                    generator=generator
                ).images[0]
            
            print("✅ 템플릿 생성 완료")
            
            # 5. 얼굴 교체
            print("\n5단계: 얼굴 교체 (각도 보정)")
            
            final_image = self.swap_face_with_alignment(template_image, source_face)
            
            print("✅ 최종 이미지 생성 완료")
            
            # 6. Base64 변환
            result_base64 = self.image_to_base64(final_image)
            
            return result_base64
            
        except Exception as e:
            print(f"이미지 생성 오류: {e}")
            import traceback
            traceback.print_exc()
            
            return original_photo_base64.split(',')[1] if ',' in original_photo_base64 else original_photo_base64

generator = None

def get_generator():
    global generator
    if generator is None:
        generator = MissingPersonImageGenerator()
    return generator