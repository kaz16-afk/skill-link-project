import os
import json
import boto3
import urllib.request
import urllib.error
import re
import uuid
from botocore.config import Config

# --- 1. 環境設定 ---
S3_AK = os.environ.get('S3_ACCESS_KEY')
S3_SK = os.environ.get('S3_SECRET_KEY')
LINE_TOKEN = os.environ.get('LINE_CHANNEL_ACCESS_TOKEN')
BUCKET_NAME = os.environ.get("BUCKET_NAME", "")
KB_ID = os.environ.get('BEDROCK_KB_ID', "")
TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME')

# リージョン設定 (タイムアウト60秒)
config = Config(region_name="us-east-1", connect_timeout=2, read_timeout=60, retries={'max_attempts': 0})

# クライアント初期化
s3_client = boto3.client('s3', aws_access_key_id=S3_AK, aws_secret_access_key=S3_SK, config=config)
bedrock_runtime = boto3.client('bedrock-agent-runtime', config=config)
dynamodb = boto3.resource('dynamodb', region_name='us-east-1')
table = dynamodb.Table(TABLE_NAME) if TABLE_NAME else None

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
    return s3_client.generate_presigned_url(ClientMethod='get_object', Params={'Bucket': BUCKET_NAME, 'Key': key}, ExpiresIn=3600)

def lambda_handler(event, context):
    print("Event:", json.dumps(event))
    try:
        if 'body' not in event or not event['body']: return {'statusCode': 200, 'body': 'OK'}
        body = json.loads(event['body'])
        
        for line_event in body.get('events', []):
            if line_event['type'] != 'message' or line_event['message']['type'] != 'text':
                continue
            
            user_msg = line_event['message']['text'].strip()
            reply_token = line_event['replyToken']
            user_id = line_event['source'].get('userId')
            if not user_id: continue

            # ==========================================
            # 1. メールアドレス登録
            # ==========================================
            email_pattern = r"^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$"
            if re.match(email_pattern, user_msg):
                if table:
                    try:
                        table.put_item(Item={'userId': user_id, 'email': user_msg})
                        # 登録完了メッセージ
                        req = urllib.request.Request(
                            "https://api.line.me/v2/bot/message/reply", 
                            data=json.dumps({"replyToken": reply_token, "messages": [{"type": "text", "text": f"メールアドレスを登録しました！\n({user_msg})\n\n続けて、探したいエンジニアの条件を教えてください。"}]}).encode("utf-8"), 
                            headers={"Content-Type": "application/json", "Authorization": f"Bearer {LINE_TOKEN}"}, 
                            method="POST"
                        )
                        urllib.request.urlopen(req)
                    except Exception as e:
                        print(f"DynamoDB Error: {e}")
                return {'statusCode': 200}
            
            # ==========================================
            # 2. AI検索
            # ==========================================

            # 一次回答として 先に「お待ちください」を返信
            try:
                push_req = urllib.request.Request(
                    "https://api.line.me/v2/bot/message/reply",
                    data=json.dumps({"replyToken": reply_token, "messages": [{"type": "text", "text": "🔍 只今AIがスキルシートを検索・解析中です...少々お待ちください。"}]}).encode("utf-8"), 
                    headers={"Content-Type": "application/json", "Authorization": f"Bearer {LINE_TOKEN}"}, 
                    method="POST"
                )
                urllib.request.urlopen(push_req)
            except: pass

            # A. S3 Search (User Input)
            user_input_ids = list(set(re.findall(r'(\d{2,})', user_msg)))
            user_valid_files = [] 
            for tid in user_input_ids:
                key = find_excel_ultimate(tid)
                if key:
                    user_valid_files.append({"id": tid, "key": key, "url": generate_presigned_url(key)})

            # B. Bedrock Call
            bedrock_input = user_msg
            if user_input_ids:
                bedrock_input = f"エンジニアID {' '.join(user_input_ids)} について回答してください: {user_msg}"

            # ★旧コードのプロンプト
            prompt_template = """あなたはプロのエージェントです。$search_results$ をもとに回答してください。
            特定のエンジニアについて言及する際は「氏名 (ID: XXX)」の形式を使ってください。
            最後に「詳細は下記ボタンから確認してください。」と添えてください。"""
            
            kb_config = {
                'type': 'KNOWLEDGE_BASE',
                'knowledgeBaseConfiguration': {
                    'knowledgeBaseId': KB_ID,
                    'modelArn': 'arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-5-sonnet-20240620-v1:0',
                    'retrievalConfiguration': {'vectorSearchConfiguration': {'numberOfResults': 15}},
                    'generationConfiguration': {'promptTemplate': {'textPromptTemplate': prompt_template}}
                }
            }

            ai_text = ""
            try:
                # sessionId削除 (エラー回避)
                response = bedrock_runtime.retrieve_and_generate(
                    input={'text': bedrock_input}, 
                    retrieveAndGenerateConfiguration=kb_config
                )
                ai_text = response['output']['text']
            except:
                try:
                    response = bedrock_runtime.retrieve_and_generate(
                        input={'text': bedrock_input}, 
                        retrieveAndGenerateConfiguration=kb_config
                    )
                    ai_text = response['output']['text']
                except: ai_text = "AI検索中にエラーが発生しました。"

            # C. 表示ロジック
            final_files = []
            
            negatives = ["見つかりません", "見当たりません", "含まれていない", "情報がありません"]
            is_negative_response = any(x in ai_text for x in negatives)

            # 強制上書きモード
            if user_valid_files and is_negative_response:
                id_list_str = "、".join([f"ID:{f['id']}" for f in user_valid_files])
                ai_text = f"ご指定の {id_list_str} のエンジニア資料が見つかりました。詳細は下記ボタンから確認してください。"
                final_files = user_valid_files
            else:
                # 通常モード (ID: XXX を抽出)
                ai_mentioned_ids = set(re.findall(r'ID[:：\s]*(\d+)', ai_text))
                
                ai_valid_files = []
                for tid in ai_mentioned_ids:
                    if tid not in [u['id'] for u in user_valid_files]:
                        key = find_excel_ultimate(tid)
                        if key:
                            ai_valid_files.append({"id": tid, "key": key, "url": generate_presigned_url(key)})
                
                final_files = user_valid_files + ai_valid_files

            # Push Message (replyToken消費済みのためPushを使用)
            push_messages = [{"type": "text", "text": ai_text}]

            # カルーセル生成
            if final_files:
                bubbles = []
                seen_ids = set()
                sorted_files = []
                for f in final_files:
                    if f['id'] not in seen_ids:
                        sorted_files.append(f)
                        seen_ids.add(f['id'])
                sorted_files.sort(key=lambda x: x['id'])

                for f in sorted_files:
                    bubbles.append({
                        "type": "bubble", "size": "micro",
                        "body": {"type": "box", "layout": "vertical", "contents": [
                            {"type": "text", "text": f"ID:{f['id']}", "weight": "bold", "size": "sm"},
                            {"type": "text", "text": "スキルシート資料", "size": "xs", "color": "#888888"}
                        ]},
                        "footer": {"type": "box", "layout": "vertical", "contents": [
                            {"type": "button", "action": {"type": "uri", "label": "開く", "uri": f['url']}, "style": "primary", "color": "#00b900", "height": "sm"}
                        ]}
                    })
                if bubbles:
                    push_messages.append({"type": "flex", "altText": "資料送付", "contents": {"type": "carousel", "contents": bubbles[:10]}})

            # LINE Push送信
            req = urllib.request.Request(
                "https://api.line.me/v2/bot/message/push", 
                data=json.dumps({"to": user_id, "messages": push_messages[:5]}).encode("utf-8"), 
                headers={"Content-Type": "application/json", "Authorization": f"Bearer {LINE_TOKEN}"}, 
                method="POST"
            )
            urllib.request.urlopen(req)

    except Exception as e:
        print(f"Global Error: {str(e)}")
    return {'statusCode': 200}