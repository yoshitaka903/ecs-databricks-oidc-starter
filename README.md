# Databricks OAuth U2M with OIDC Support - Production Ready

# Sample ECS application demonstrating OIDC SSO integration with Databricks Model Serving

## 機能

- **OAuth U2M**: ユーザー権限でのDatabricks API呼び出し
- **ECS Fargate**: AWS上でのコンテナ化デプロイ
- **HTTPS対応**: ALB + SSL証明書 または localtunnel
- **セッション管理**: Express Session による状態管理

## 導入前提条件

### Databricks設定
1. **OAuth App作成**
   - Databricks ワークスペース → Settings → Identity and access → OAuth apps
   - Redirect URI: `https://YOUR_COMPANY_DOMAIN/oauth/callback`
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

### 6. HTTPS設定

#### オプションA: ALB + SSL証明書（推奨）
```bash
# Route53でドメイン設定
# ACMでSSL証明書取得
# ALBにSSL証明書を適用
```

#### オプションB: EC2プロキシサーバー
```bash
# EC2プロキシサーバーを自動でプロビジョニング
terraform apply

# プロキシ状況確認
terraform output proxy_public_ip
terraform output proxy_setup_commands

# localtunnel URL確認（自動設定）
# https://ecs-databricks-oauth.loca.lt
```

#### オプションC: ローカルプロキシサーバー
```bash
# 環境変数でALB URLを設定してプロキシサーバーを起動
export ALB_URL="http://$(terraform output -raw alb_dns_name)"
node proxy-server.js

# localtunnelでHTTPS化
lt --port 8080 --subdomain ecs-databricks-oauth
```

### 7. Databricks Redirect URI更新
Databricks OAuth設定で Redirect URI を以下に更新:
```
https://your-company-domain.com/oauth/callback
```

## モニタリング

### CloudWatch Logs
```bash
# ECSアプリケーションログ
aws logs tail /ecs/databricks-oauth-app --follow

# EC2プロキシログ
aws logs tail /aws/ec2/databricks-oauth-app-proxy --follow
```

### ECS Tasks
```bash
aws ecs list-tasks --cluster $(terraform output -raw ecs_cluster_name)
aws ecs describe-tasks --cluster $(terraform output -raw ecs_cluster_name) --tasks <task-arn>
```

### EC2プロキシ監視
```bash
# プロキシサーバー状態確認
ssh -i your-key.pem ec2-user@$(terraform output -raw proxy_public_ip)
sudo systemctl status proxy-server
sudo systemctl status localtunnel

# ヘルスチェック
curl http://$(terraform output -raw proxy_public_ip):8080/health
curl https://ecs-databricks-oauth.loca.lt/health
```

---
**重要**: 本番環境では必ずセキュリティレビューを実施し、会社のセキュリティポリシーに準拠することを確認してください。