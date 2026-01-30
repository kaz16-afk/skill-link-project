import json
import os
import boto3
import logging
from botocore.exceptions import ClientError

# ロガーの設定
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Bedrock Agentクライアントの初期化 (バージニア北部: us-east-1)
client = boto3.client('bedrock-agent', region_name='us-east-1')

def lambda_handler(event, context):
    # デバッグ用ログ出力
    logger.info(f"Event Received: {json.dumps(event)}")

    # 環境変数の取得
    kb_id = os.environ.get('KNOWLEDGE_BASE_ID')
    ds_id = os.environ.get('DATA_SOURCE_ID')

    # 設定漏れチェック
    if not kb_id or not ds_id:
        logger.error("Error: KNOWLEDGE_BASE_ID or DATA_SOURCE_ID is missing.")
        raise ValueError("Environment variables are missing.")

    try:
        # 同期ジョブの開始
        response = client.start_ingestion_job(
            knowledgeBaseId=kb_id,
            dataSourceId=ds_id,
            description='Auto-sync triggered via Lambda (Python)'
        )
        
        logger.info(f"✅ Ingestion Job Started successfully: {response}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': "Sync job started",
                'jobId': response['ingestionJob']['ingestionJobId'],
                'status': response['ingestionJob']['status']
            })
        }

    except ClientError as e:
        error_code = e.response['Error']['Code']
        
        # よくあるエラー:「前の同期が終わってないのに次を実行しようとした」場合
        # これは正常なスキップとして扱う
        if error_code == 'ConflictException':
            logger.warning("⚠️ Sync job is already running. Skipping this request.")
            return {
                'statusCode': 200,
                'body': json.dumps("Sync already running")
            }
        
        # それ以外の本当のエラーはログに出して異常終了させる
        logger.error(f"❌ Error starting ingestion job: {e}")
        raise e

    except Exception as e:
        logger.error(f"❌ Unexpected error: {e}")
        raise e