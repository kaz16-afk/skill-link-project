import json
import boto3
import time
import os
from botocore.config import Config

# S3クライアントの初期化 (署名バージョンv4を指定)
config = Config(signature_version='s3v4')
s3_client = boto3.client('s3', region_name='us-east-1', config=config)

def lambda_handler(event, context):
    # CORS用ヘッダー (共通化)
    headers_cors = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type,x-skill-link-auth",
        "Access-Control-Allow-Methods": "OPTIONS,POST"
    }

    try:
        # ==================================================================
        # 1. セキュリティチェック (簡易APIキー認証)
        # ==================================================================
        # Terraformから渡された正解のキー
        expected_key = os.environ.get('API_KEY')
        
        # リクエストヘッダーからキーを取得 (API Gatewayは小文字に変換することがあるので両対応)
        req_headers = event.get('headers', {})
        incoming_key = req_headers.get('x-skill-link-auth') or req_headers.get('X-Skill-Link-Auth')

        # キーが設定されているのに、送られてこない or 間違っている場合は拒否
        if expected_key and incoming_key != expected_key:
            print(f"Auth Failed. Incoming: {incoming_key}")
            return {
                'statusCode': 403,
                'headers': headers_cors,
                'body': json.dumps({'message': 'Forbidden: Invalid API Key'})
            }
        # ==================================================================

        # POSTボディからファイル情報を取得
        body = json.loads(event.get('body', '{}'))
        
        # デフォルトファイル名の生成
        default_filename = f"upload_{int(time.time() * 1000)}.pdf"
        
        file_name = body.get('filename', default_filename)
        file_type = body.get('filetype', "application/pdf")

        # 許可する拡張子チェック
        ALLOWED_TYPES = [
            "application/pdf",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", # .xlsx
            "application/vnd.ms-excel" # .xls
        ]

        if file_type not in ALLOWED_TYPES:
            return {
                'statusCode': 400,
                'headers': headers_cors,
                'body': json.dumps({ 'error': f"Invalid file type: {file_type}." })
            }

        # 振分ロジック
        folder = "uploads/"
        lower_name = file_name.lower()

        if "development" in lower_name:
            folder = "01_01_DevelopmentEngineer/"
        elif "cloud" in lower_name:
            folder = "02_CloudEngineer/"

        key = f"{folder}{file_name}"

        # バケット名（環境変数から取得）
        bucket_name = os.environ.get('BUCKET_NAME')

        # 署名付きURLを発行 (有効期限 300秒 = 5分)
        upload_url = s3_client.generate_presigned_url(
            ClientMethod='put_object',
            Params={
                'Bucket': bucket_name,
                'Key': key,
                'ContentType': file_type
            },
            ExpiresIn=300
        )

        return {
            'statusCode': 200,
            'headers': headers_cors,
            'body': json.dumps({ 'uploadUrl': upload_url, 'key': key })
        }

    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': headers_cors,
            'body': json.dumps({ 'error': str(e) })
        }