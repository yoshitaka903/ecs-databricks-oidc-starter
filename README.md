# Sample ECS application demonstrating OIDC SSO integration with Databricks Model Serving

## 機能

- **OAuth U2M**: ユーザー権限でのDatabricks API呼び出し
- **ECS Fargate**: AWS上でのコンテナ化デプロイ
- **HTTPS対応**: CloudFront による HTTPS アクセス
- **セッション管理**: Express Session による状態管理

## 導入前提条件

### Databricks設定
1. **OAuth App作成**
   - Databricks ワークスペース → Settings → Developer → App connections
   - Redirect URI: デプロイ後に CloudFront ドメインで更新 (例: `https://xxxxx.cloudfront.net/oauth/callback`)
   - Scopes: `openid`, `all-apis`, `offline_access`

2. **Model Serving エンドポイント**
   - モデルのエンドポイント作成(または基盤モデルを利用)
   - エンドポイント名をメモ

### AWS設定
- AWS CLI設定済み
- ECR、ECS、ALB、VPC作成権限
- Terraform v1.0以上
- SSL証明書（本番環境）

## デプロイ手順

### ワンコマンドデプロイ
```bash
# 設定ファイル準備
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# terraform.tfvars を編集（Databricks設定を入力）

# 全自動デプロイ実行
./deploy.sh
```

## 詳細セットアップ手順

### 1. リポジトリクローン
```bash
git clone https://github.com/yoshitaka903/ecs-databricks-oidc-starter.git
cd ecs-databricks-oidc-starter
```

### 2. 環境設定
```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

`terraform/terraform.tfvars` を編集:
```hcl
# AWS設定
aws_region = "ap-northeast-1"
app_name = "databricks-oauth-app" # 任意

# IP制限設定(必要な場合)
allowed_ips = [
  "YOUR_COMPANY_IP_RANGE",
  "VPN_IP_RANGE"
]

# Databricks設定
databricks_host = "xxxxxxxxx"
databricks_client_id = "your-company-client-id"
databricks_client_secret = "your-company-client-secret"
databricks_endpoint = "your-company-serving-endpoint-name"
```

### 3. インフラストラクチャ構築
```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 4. Dockerイメージビルド・プッシュ

#### オプションA: AWS CodeBuild使用（推奨・Docker不要）
```bash
# CodeBuildでイメージビルド実行
aws codebuild start-build --project-name $(terraform output -raw codebuild_project_name)

# ビルド状況確認
aws codebuild batch-get-builds --ids $(aws codebuild list-builds-for-project --project-name $(terraform output -raw codebuild_project_name) --query 'ids[0]' --output text)
```

### 5. ECSサービス更新
```bash
# タスク定義更新
terraform apply

# サービス再起動
aws ecs update-service --cluster $(terraform output -raw ecs_cluster_name) --service $(terraform output -raw ecs_service_name) --force-new-deployment
```

### 6. HTTPS アクセス設定

CloudFront が自動的にデプロイされ、HTTPS アクセスが可能になります。

```bash
# CloudFront ドメインを確認
terraform output cloudfront_https_url

# 出力例: https://xxxxx.cloudfront.net
```

### 7. Databricks Redirect URI更新

Databricks OAuth設定で Redirect URI を CloudFront ドメインで更新:

1. Databricks ワークスペース → Settings → Developer → App connections
2. 作成した OAuth アプリケーションを選択
3. Redirect URLs に以下を追加:
```bash
# terraform output から取得
terraform output oauth_redirect_uri_cloudfront

# 例: https://xxxxx.cloudfront.net/oauth/callback
```

## モニタリング

### CloudWatch Logs
```bash
# ECSアプリケーションログ
aws logs tail $(terraform output -raw cloudwatch_log_group) --follow
```

### ECS Tasks
```bash
# タスク一覧
aws ecs list-tasks --cluster $(terraform output -raw ecs_cluster_name)

# タスク詳細
aws ecs describe-tasks --cluster $(terraform output -raw ecs_cluster_name) --tasks <task-arn>
```

### ターゲットグループヘルスチェック
```bash
# ターゲットの健全性確認
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw target_group_arn)
```

### アプリケーションアクセス
```bash
# HTTPS URL (CloudFront - 推奨)
terraform output cloudfront_https_url

# HTTP URL (ALB - 直接アクセス)
terraform output application_url
```

---
**重要**: 本番環境では必ずセキュリティレビューを実施し、会社のセキュリティポリシーに準拠することを確認してください。