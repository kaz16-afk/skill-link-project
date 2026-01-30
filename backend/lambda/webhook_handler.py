import os
import json
import boto3
import urllib.request
import urllib.error
import re
import uuid
from botocore.config import Config

# --- 1. 環境設定 ---
# Terraformから渡されるIAMユーザーのキーを取得
S3_AK = os.environ.get('S3_ACCESS_KEY')
S3_SK = os.environ.get('S3_SECRET_KEY')
LINE_TOKEN = os.environ.get('LINE_CHANNEL_ACCESS_TOKEN')
BUCKET_NAME = os.environ.get("BUCKET_NAME", "")
KB_ID = os.environ.get('BEDROCK_KB_ID', "")

# リージョン設定
# S3・Bedrockはバージニア (us-east-1) リージョン
s3_config = Config(region_name="us-east-1", signature_version='s3v4')
bedrock_config = Config(region_name="us-east-1", connect_timeout=2, read_timeout=10, retries={'max_attempts': 1})

# クライアント初期化
if S3_AK and S3_SK:
    # アクセスキーがある場合（Terraformから渡された場合）
    s3_client = boto3.client('s3', aws_access_key_id=S3_AK, aws_secret_access_key=S3_SK, config=s3_config)
else:
    # キーがない場合は明示的にエラーを出して止める（ここで止めないと後でクラッシュするため）
    print("CRITICAL ERROR: S3 Access Keys are missing.")
    raise ValueError("S3_ACCESS_KEY or S3_SECRET_KEY is missing in environment variables.")

bedrock_runtime = boto3.client('bedrock-agent-runtime', config=bedrock_config)

# --- LINE API Helper ---
def send_line_reply(reply_token, text):
    url = "https://api.line.me/v2/bot/message/reply"
    body = {"replyToken": reply_token, "messages": [{"type": "text", "text": text}]}
    _send_request(url, body)

def send_line_push(user_id, messages):
    url = "https://api.line.me/v2/bot/message/push"
    body = {"to": user_id, "messages": messages}
    _send_request(url, body)

def _send_request(url, body):
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {LINE_TOKEN}"},
        method="POST"
    )
    try:
        with urllib.request.urlopen(req) as res: pass
    except Exception as e:
        print(f"LINE API Error: {e}")

# --- Logic ---
def find_excel_ultimate(id_str):
    try:
        if not id_str: return None
        pure_id = re.sub(r'\D', '', id_str).lstrip('0')
        if not pure_id: return None
        pattern = re.compile(rf".*[^0-9]0*{pure_id}[^0-9].*|.*_0*{pure_id}\.xlsx$|^0*{pure_id}\.xlsx$", re.IGNORECASE)
        response = s3_client.list_objects_v2(Bucket=BUCKET_NAME)
        if 'Contents' in response:
            for obj in response['Contents']:
                if pattern.match(obj['Key']) or f"_{pure_id}." in obj['Key'] or f" {pure_id}." in obj['Key']:
                    return obj['Key']
    except Exception as e:
        print(f"S3 Search Error: {e}")
    return None

def generate_presigned_url(key):
    try:
        return s3_client.generate_presigned_url(
            ClientMethod='get_object', 
            Params={'Bucket': BUCKET_NAME, 'Key': key}, 
            ExpiresIn=3600
        )
    except Exception as e:
        print(f"Presigned URL Error: {e}")
        return ""

def lambda_handler(event, context):
    print("Event:", json.dumps(event))
    try:
        if 'body' not in event or not event['body']: return {'statusCode': 200, 'body': 'OK'}
        body = json.loads(event['body'])
        
        for line_event in body.get('events', []):
            if line_event['type'] != 'message' or line_event['message']['type'] != 'text': continue
            
            user_msg = line_event['message']['text']
            reply_token = line_event['replyToken']
            user_id = line_event['source'].get('userId')
            if not user_id: continue

            session_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"prod-{user_id}"))
            send_line_reply(reply_token, "🔍 只今AIがスキルシートを検索・解析中です...少々お待ちください。")

            # 1. S3 Search
            user_input_ids = list(set(re.findall(r'(\d{2,})', user_msg)))
            user_valid_files = [] 
            for tid in user_input_ids:
                key = find_excel_ultimate(tid)
                if key: user_valid_files.append({"id": tid, "key": key, "url": generate_presigned_url(key)})

            # 2. AI Search
            bedrock_input = f"エンジニアID {' '.join(user_input_ids)} について: {user_msg}" if user_input_ids else user_msg
            prompt = """あなたはSES営業支援のプロエージェントです。$search_results$ をもとに回答してください。
            特定のエンジニアについて言及する際は「氏名 (ID: XXX)」の形式を使ってください。
            見つからない場合は正直に「情報が見当たりません」と答えてください。"""
            
            kb_config = {
                'type': 'KNOWLEDGE_BASE',
                'knowledgeBaseConfiguration': {
                    'knowledgeBaseId': KB_ID,
                    'modelArn': 'arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-5-sonnet-20240620-v1:0',
                    'retrievalConfiguration': {'vectorSearchConfiguration': {'numberOfResults': 15}},
                    'generationConfiguration': {'promptTemplate': {'textPromptTemplate': prompt}}
                }
            }

            ai_text = ""
            try:
                response = bedrock_runtime.retrieve_and_generate(
                    input={'text': bedrock_input}, sessionId=session_id, retrieveAndGenerateConfiguration=kb_config
                )
                ai_text = response['output']['text']
            except Exception:
                try:
                    response = bedrock_runtime.retrieve_and_generate(
                        input={'text': bedrock_input}, retrieveAndGenerateConfiguration=kb_config
                    )
                    ai_text = response['output']['text']
                except: ai_text = "AI検索中にエラーが発生しました。"

            # Merge results
            final_files = []
            if user_valid_files and any(x in ai_text for x in ["見つかりません", "情報がありません"]):
                ai_text = f"ご指定のエンジニア資料が見つかりました。"
                final_files = user_valid_files
            else:
                ai_ids = set(re.findall(r'ID[:：\s]*(\d+)', ai_text))
                for tid in ai_ids:
                    if tid not in [u['id'] for u in user_valid_files]:
                        key = find_excel_ultimate(tid)
                        if key: user_valid_files.append({"id": tid, "key": key, "url": generate_presigned_url(key)})
                final_files = user_valid_files

            # Push Message
            push_messages = [{"type": "text", "text": ai_text}]
            if final_files:
                bubbles = []
                seen = set()
                for f in final_files:
                    if f['id'] not in seen:
                        bubbles.append({
                            "type": "bubble", "size": "micro",
                            "body": {"type": "box", "layout": "vertical", "contents": [
                                {"type": "text", "text": f"ID:{f['id']}", "weight": "bold", "size": "sm"},
                                {"type": "text", "text": "スキルシート", "size": "xs", "color": "#888888"}
                            ]},
                            "footer": {"type": "box", "layout": "vertical", "contents": [
                                {"type": "button", "action": {"type": "uri", "label": "開く", "uri": f['url']}, "style": "primary", "color": "#00b900", "height": "sm"}
                            ]}
                        })
                        seen.add(f['id'])
                if bubbles:
                    push_messages.append({"type": "flex", "altText": "資料", "contents": {"type": "carousel", "contents": bubbles[:10]}})

            send_line_push(user_id, push_messages[:5])

    except Exception as e:
        print(f"Error: {e}")
        return {'statusCode': 200, 'body': 'Error'}
    return {'statusCode': 200, 'body': 'OK'}