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
REGION_NAME = "us-east-1"
BUCKET_NAME = os.environ.get("BUCKET_NAME")
KB_ID = os.environ.get('BEDROCK_KB_ID')

config = Config(region_name=REGION_NAME, connect_timeout=2, read_timeout=10, retries={'max_attempts': 1})
s3_client = boto3.client('s3', aws_access_key_id=S3_AK, aws_secret_access_key=S3_SK, config=config)
bedrock_runtime = boto3.client('bedrock-agent-runtime', config=config)

def find_excel_ultimate(id_str):
    try:
        if not id_str: return None
        pure_id = re.sub(r'\D', '', id_str).lstrip('0')
        if not pure_id: return None
        
        # 検索パターン：ファイル名の末尾、あるいは区切り文字に挟まれたIDを探す
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
    try:
        body = json.loads(event['body'])
        for line_event in body['events']:
            if line_event['type'] != 'message' or line_event['message']['type'] != 'text':
                continue
            
            user_msg = line_event['message']['text']
            reply_token = line_event['replyToken']
            session_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"prod-{line_event['source']['userId']}"))

            # --- 1. ユーザー入力からIDを特定し、S3にあるか確認 ---
            user_input_ids = list(set(re.findall(r'(\d{2,})', user_msg)))
            user_valid_files = [] # ユーザーが指名して、かつS3にあったもの
            for tid in user_input_ids:
                key = find_excel_ultimate(tid)
                if key:
                    user_valid_files.append({"id": tid, "key": key, "url": generate_presigned_url(key)})

            # --- 2. AIへの問い合わせ ---
            bedrock_input = user_msg
            if user_input_ids:
                bedrock_input = f"エンジニアID {' '.join(user_input_ids)} について回答してください: {user_msg}"

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
                response = bedrock_runtime.retrieve_and_generate(input={'text': bedrock_input}, sessionId=session_id, retrieveAndGenerateConfiguration=kb_config)
                ai_text = response['output']['text']
            except:
                response = bedrock_runtime.retrieve_and_generate(input={'text': bedrock_input}, retrieveAndGenerateConfiguration=kb_config)
                ai_text = response['output']['text']
                final_files = []
            
            # 判定用ワード：AIが「見つからない」と言っているか？
            negatives = ["見つかりません", "見当たりません", "含まれていない", "情報がありません"]
            is_negative_response = any(x in ai_text for x in negatives)

            # 【オーバーライド発動条件】
            # 「ユーザーが指定したIDのファイルがある」のに「AIが見つからないと言っている」場合
            if user_valid_files and is_negative_response:
                # ➡ AIの回答（代替案のID含む）をすべて捨てて、強制的に成功メッセージにする
                id_list_str = "、".join([f"ID:{f['id']}" for f in user_valid_files])
                ai_text = f"ご指定の {id_list_str} のエンジニア資料が見つかりました。詳細は下記ボタンから確認してください。"
                
                # ➡ ボタンは「ユーザーが指名したもの」だけにする（AIが勝手に挙げたIDは無視）
                final_files = user_valid_files
            
            else:
                # 【通常モード】
                # AIが回答の中で言及したID（ID: XXX形式）も拾う
                ai_mentioned_ids = set(re.findall(r'ID[:：\s]*(\d+)', ai_text))
                
                # S3チェック
                ai_valid_files = []
                for tid in ai_mentioned_ids:
                    # ユーザー入力ですでにチェック済みのIDは除外してチェック
                    if tid not in [u['id'] for u in user_valid_files]:
                        key = find_excel_ultimate(tid)
                        if key:
                            ai_valid_files.append({"id": tid, "key": key, "url": generate_presigned_url(key)})
                
                # ユーザー指名分 ＋ AI提案分 を合体
                final_files = user_valid_files + ai_valid_files

            messages = [{"type": "text", "text": ai_text}]

            # --- 4. カルーセル生成 ---
            if final_files:
                bubbles = []
                # 重複排除とソート
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
                messages.append({"type": "flex", "altText": "資料送付", "contents": {"type": "carousel", "contents": bubbles[:10]}})

            # LINE返信
            req = urllib.request.Request(
                "https://api.line.me/v2/bot/message/reply", 
                data=json.dumps({"replyToken": reply_token, "messages": messages[:5]}).encode("utf-8"), 
                headers={"Content-Type": "application/json", "Authorization": f"Bearer {LINE_TOKEN}"}, 
                method="POST"
            )
            urllib.request.urlopen(req)

    except Exception as e:
        print(f"Global Error: {str(e)}")
    return {'statusCode': 200}
