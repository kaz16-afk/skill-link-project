# SKiLL-LiNK
**AWS RAG × LINE** で実現するエンジニア検索ボット

営業担当者がLINEで「Java経験3年以上のエンジニアを探して」と送るだけで、
S3上のExcelスキルシートから条件に合う候補者を検索し、**要約 + スキルシートのダウンロードリンク**を自動返信します。

![Architecture Diagram](./docs/architecture.png)
*(ここに構成図の画像を配置してください)*

## 📖 開発背景・詳細解説 (Zenn)
本プロダクトの開発経緯、アーキテクチャ選定の裏側、開発中の技術的な課題（SQSによる流量制御、RAGの精度調整など）については、Zennの記事で詳しく解説しています。

👉 **[SES営業の『このエンジニアいないかな？』を爆速で解決。AWS RAG × LINE で叶えるエンジニア検索ボット「SKiLL-LiNK」](https://zenn.dev/study_scraps/articles/c43f2f8ceb1fef)**

---

## 主な機能
- **自然言語検索**: LINEトークで「Goが得意な若手、AWS経験あり」のように話しかけて検索可能
- **RAG (検索拡張生成)**: Bedrock (Claude 3.5 Sonnet) + Pinecone による高精度なマッチング
- **自動同期**: S3にスキルシートをアップロードするだけで、SQS経由で自動的にベクトルDBへ同期
- **サーバーレス**: Lambda, API Gateway, S3, DynamoDB によるフルマネージド構成

---

## 🛠 技術スタック
- **Frontend:** React (Vite), LINE Bot
- **Backend:** AWS Lambda (Python 3.11)
- **AI/RAG:** AWS Bedrock, Amazon Titan (Embeddings), Knowledge Base, Pinecone
- **Infrastructure:** Terraform (IaC)
- **CI/CD:** (Future Plan: GitHub Actions)

---

## デプロイ手順

本リポジトリは Terraform を使用しており、コマンド一つでインフラ構築からフロントエンドのデプロイまで完結します。

### 1. 前提条件
- AWS CLI の設定済み (`aws configure`)
- Terraform のインストール済み
- LINE Developers コンソールでのチャネル作成（Messaging API）
- Pinecone のインデックス作成（API Keyの取得）

### 2. リポジトリのクローン
```bash
git clone [https://github.com/](https://github.com/)<your-username>/skill-link.git
cd skill-link
```

### 3. 変数設定ファイル (`terraform.tfvars`) の作成
リポジトリ直下に `terraform.tfvars` ファイルを作成し、ご自身の環境に合わせて値を設定してください。
※このファイルは機密情報を含むため `.gitignore` されています。

```hcl
# terraform.tfvars
aws_account_id      = "123456789012"
line_channel_token  = "YOUR_LINE_CHANNEL_ACCESS_TOKEN"
pinecone_index_url  = "YOUR_PINECONE_INDEX_URL"
pinecone_secret_arn = "arn:aws:secretsmanager:us-east-1:..." 
# ※PineconeキーをSecrets Managerに保存していない場合は、main.tfの該当箇所を直接文字列で指定するか調整してください
```

### 4. インフラ構築 & デプロイ
```bash
# フロントエンドのビルドとAWSリソースの作成を一括実行
terraform init
terraform apply
```

完了後、ターミナルに以下が出力されます：
- `api_gateway_url`: Webhook等のエンドポイント
- `cloudfront_url`: 管理画面（Web）のURL

### 5. LINE Bot設定
出力された `api_gateway_url` + `/callback` (例: `https://xxxx.execute-api.us-east-1.amazonaws.com/callback`) を、LINE Developersコンソールの **Webhook URL** に設定してください。

---

##  動作確認

1. **管理画面**: `cloudfront_url` にアクセスし、テスト用のExcelスキルシートをアップロードします。
2. **LINE**: Botに対して以下のように話しかけます。
   - 「Java経験3年以上のエンジニアを探して」
   - 「基本設計から一人称で動けるPM」

---

## 免責事項
本リポジトリのコードは学習・検証用（MVP）として公開しています。
本番運用時のセキュリティ（WAF、厳密なIAM権限管理など）および利用責任は利用者に帰属します。
```