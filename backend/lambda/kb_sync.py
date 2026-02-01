import json
import os
import boto3
import logging
from botocore.exceptions import ClientError

# --- ロガー設定 ---
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# --- クライアント初期化 (Bedrock Agent) ---
client = boto3.client('bedrock-agent', region_name='us-east-1')

def lambda_handler(event, context):
    """
    SQSからメッセージを受信した際に起動するLambda関数。
    S3の変更通知をトリガーに、Bedrock Knowledge Baseの同期ジョブを開始します。
    """
    
    logger.info(f"Event Received from SQS: {json.dumps(event)}")

    # --- 環境変数の取得とチェック ---
    kb_id = os.environ.get('KNOWLEDGE_BASE_ID')
    ds_id = os.environ.get('DATA_SOURCE_ID')

    if not kb_id or not ds_id:
        logger.error("Error: KNOWLEDGE_BASE_ID or DATA_SOURCE_ID is missing.")
        raise ValueError("Environment variables are missing.")

    try:
        # --- SQSメッセージの処理 ---
        # SQS経由の場合、event['Records']の中にメッセージリストが入っている。
        # 今回は「通知が来たら同期する」だけなので、中身の詳細解析はせず
        # 単純に同期ジョブを1回キックする。
        
        # 同期ジョブの開始リクエスト
        response = client.start_ingestion_job(
            knowledgeBaseId=kb_id,
            dataSourceId=ds_id,
            description='Auto-sync triggered via SQS -> Lambda'
        )
        
        # 成功ログ
        logger.info(f"✅ Sync Started: {response}")
        
        return {
            'statusCode': 200,
            'body': json.dumps("Sync job started successfully")
        }

    except ClientError as e:
        error_code = e.response['Error']['Code']
        
        # --- エラーハンドリング (スロットリング対策) ---
        
        # ケース1: ConflictException
        # すでに同期ジョブが実行中の場合。これは異常ではなく「重複起動」なので、
        # エラーにせず「スキップ」として正常終了させる。
        if error_code == 'ConflictException':
            logger.warning("⚠️ Sync job is already running. Skipping this request.")
            return {
                'statusCode': 200,
                'body': json.dumps("Skipped: Sync already running")
            }
            
        # ケース2: ThrottlingException
        # 短時間に大量のファイルをアップロードしてAPI制限に引っかかった場合。
        # 別のLambda実行が同期をかけてくれることに期待し、これも「スキップ」とする。
        if error_code == 'ThrottlingException':
            logger.warning("⚠️ Throttling detected. Skipping this request.")
            return {
                'statusCode': 200,
                'body': json.dumps("Skipped: Throttling")
            }
        
        logger.error(f"❌ Error starting ingestion job: {e}")
        raise e

    except Exception as e:
        logger.error(f"❌ Unexpected error: {e}")
        raise e