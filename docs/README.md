# SKiLL-LiNK Project

**SES営業の「提案スピード」を加速させる、LINE × 生成AI エンジニア検索アシスタント**

SKiLL-LiNKは、SES企業内に眠る膨大なスキルシートをAI (AWS Bedrock) でデータベース化し、LINEでの対話を通じて最適なエンジニアを即座にマッチングさせるRAGアプリケーションです。

> **開発の背景・詳細なストーリーはこちら**
> [Zenn: SESエンジニアの私が、営業のためにAIマッチングアプリを作った話](<zennのURLをここにいれる>)

## The Challenge & Solution

現役SESエンジニアとして感じていた「営業担当者との距離」と、それに起因する**情報のブラックボックス化**（エンジニアのスキルが正しく把握されていない、検索に時間がかかり機会損失する）を解消するために開発しました。

* **課題**: 「Javaができる人」のような曖昧な検索が難しく、ファイルサーバーから手動で探すアナログな運用。
* **解決**: **RAG (検索拡張生成)** を活用し、自然言語で「AWS経験がある若手は？」と聞くだけで、AIが数百枚のスキルシートから候補者をリストアップします。

## Technology Stack

**完全サーバーレス (Serverless First)** アーキテクチャを採用し、維持コストを抑えつつスケーラビリティを確保しています。

| Category | Tech Stack | Note |
| --- | --- | --- |
| **Frontend** | React / TypeScript | Hosted on S3 + CloudFront |
| **Backend** | Python 3.11+ | AWS Lambda, API Gateway (HTTP API) |
| **Infrastructure** | **Terraform (AWS)** | フルIaC管理 (Multi-Region構成) |
| **AI / RAG** | **AWS Bedrock** | Model: Titan Embeddings G1 - Text |
| **Vector DB** | **Pinecone** | Serverless Vector Database |
| **Auth** | Amazon Cognito | ドメイン制限による社内セキュリティ確保 |
| **CI/CD** | GitHub Actions | 自動デプロイパイプライン |

## Repository Structure

主要なインフラコードとアプリケーションコードの構成です。

- **`/terraform`** 👈 **Core Infrastructure**
  - AWSインフラストラクチャの全構成コード。
  - セキュリティ（WAF, IAM）やAI基盤（Bedrock, Pinecone連携）の定義。
  - 詳細は [terraform/README.md](https://github.com/kaz16-afk/skill-link-project/blob/main/terraform/README.md) をご覧ください。

- **`/frontend`**
  - 管理画面およびLIFF (LINE Front-end Framework) アプリケーション。

- **`/backend`**
  - LINE Webhook処理およびRAG検索ロジック (Lambda)。

## Key Features

* **Conversational Search**: LINEトーク画面で「Go言語が得意な人は？」と打つだけでAIが回答。
* **Automated Skill Parsing**: Excel/PDFのスキルシートをS3にアップロードするだけで、AIが自動解析しベクトル化。
* **Secure Environment**: Cognitoによるドメイン制限により、社外からの不正アクセスを遮断。
* **Cost Optimized**: 待機コストのかからないサーバーレス構成と、マルチリージョン活用によるコスト最適化。

