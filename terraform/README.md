# Infrastructure as Code (Terraform)

プロジェクト「SKiLL-LiNK」のAWSインフラ構成コードです。
Terraformを使用し、セキュアでスケーラブルなサーバーレスアーキテクチャを構築しています。

## 📏 Naming Convention
サービス名は「SKiLL-LiNK」ですが、
AWSリソースの命名規則として、一貫性とAWSの制約（S3バケット名の小文字制限など）を考慮し、全て小文字化しています。

* **Project Prefix**: `skill-link-`
* **Resource Tags**: 全リソースに対して `project = "skill-link"` タグを付与し、コスト配分タグとしての利用やリソースグループ管理を容易にしています。

## System Architecture Diagram

＜構成図をここへ挿入＞

## Architecture Overview

| Resource Type | Description | File |
| --- | --- | --- |
| **Compute** | AWS Lambda (Python), API Gateway (HTTP API) | `compute.tf` |
| **Storage** | Amazon S3, CloudFront (CDN) | `storage.tf` |
| **Auth** | Amazon Cognito (User Pool) | `auth.tf` |
| **AI / RAG** | Amazon Bedrock, Pinecone (Vector DB) | `bedrock.tf` |
| **Database** | Amazon DynamoDB, SQS | `database.tf` |
| **Security** | AWS WAF (Web ACL) *Designed | `waf.tf.example` |
| **Network** | Route53, ACM (SSL) *Designed | `domain.tf.example` |

## Security & Scalability Policy

* **IaC Management**: インフラ構成をすべてコード化し、再現性を担保。
* **Security First**: 機密情報（Account ID, Secrets）はプレースホルダー化。
* **CI/CD Separation**: Lambda等のアプリケーションコード変更はTerraformの管理外(`ignore_changes`)とし、GitHub Actionsによるデプロイと競合しないよう設計。
