import json
import boto3
import time
import os
from botocore.config import Config

# S3クライアントの初期化
# 署名付きURL発行のために signature_version='s3v4' を指定
config = Config(signature_version='s3v4')
s3_client = boto3.client('s3', region_name='us-east-1', config=config)

# バケット名（環境変数から取得、なければデフォルト値）
BUCKET_NAME = os.environ.get('BUCKET_NAME', "sl-engineer-skill-sheet")

def lambda_handler(event, context):
    try:
        # クエリパラメータを取得
        query = event.get('queryStringParameters') or {}
        
        # デフォルトファイル名の生成
        default_filename = f"upload_{int(time.time() * 1000)}.pdf"
        
        file_name = query.get('fileName', default_filename)
        file_type = query.get('fileType', "application/pdf")

        # 許可する拡張子チェック
        ALLOWED_TYPES = [
            "application/pdf",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", # .xlsx
            "application/vnd.ms-excel" # .xls
        ]

        if file_type not in ALLOWED_TYPES:
            return {
                'statusCode': 400,
                'headers': { 
                    "Content-Type": "application/json",
                    "Access-Control-Allow-Origin": "*"
                },
                'body': json.dumps({ 'error': f"Invalid file type: {file_type}." })
            }

        # 振分ロジック
        folder = "uploads/"
        lower_name = file_name.lower()

        if "development" in lower_name:
            folder = "01_DevelopmentEngineer/"
        elif "cloud" in lower_name:
            folder = "02_CloudEngineer/"

        key = f"{folder}{file_name}"

        # 署名付きURLを発行 (有効期限 300秒 = 5分)
        upload_url = s3_client.generate_presigned_url(
            ClientMethod='put_object',
            Params={
                'Bucket': BUCKET_NAME,
                'Key': key,
                'ContentType': file_type
            },
            ExpiresIn=300
        )

        return {
            'statusCode': 200,
            'headers': { 
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*", # フロントエンド接続用に必須
                "Access-Control-Allow-Headers": "Content-Type",
                "Access-Control-Allow-Methods": "OPTIONS,GET"
            },
            'body': json.dumps({ 'uploadUrl': upload_url, 'key': key })
        }

    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': { 
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*"
            },
            'body': json.dumps({ 'error': str(e) })
        }