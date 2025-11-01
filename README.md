# Databricks OAuth U2M with OIDC Support - Production Ready

**企業環境移行対応版** - Databricks OAuth User-to-Machine (U2M) 認証を使用したテキスト要約アプリケーション。OIDC (OpenID Connect) 対応によりユーザー情報の表示とSSO統合をサポート。

## OIDC版の新機能

- **OpenID Connect**: `openid` scope による拡張認証
- **ユーザー情報表示**: ID Token からユーザー属性を取得・表示
- **SSO統合準備**: 企業IDプロバイダーとの連携可能
- **Nonce検証**: CSRF攻撃防止
- **JWT処理**: ID Token のデコードと検証機能

## 主要機能

- **OAuth U2M**: ユーザー権限でのDatabricks API呼び出し
- **ECS Fargate**: AWS上でのコンテナ化デプロイ
- **HTTPS対応**: ALB + SSL証明書 または localtunnel
- **セッション管理**: Express Session による状態管理

## 企業環境での導入前提条件

### Databricks設定
1. **OAuth App作成**
   - Databricks ワークスペース → Settings → Identity and access → OAuth apps
   - Redirect URI: `https://YOUR_COMPANY_DOMAIN/oauth/callback`
   - Scopes: `openid`, `all-apis`, `offline_access`

2. **Model Serving エンドポイント**
   - Claude Sonnet 4 モデルのエンドポイント作成
   - エンドポイント名をメモ

### AWS設定
- AWS CLI設定済み
- ECR、ECS、ALB、VPC作成権限
- Terraform v1.0以上
- SSL証明書（本番環境）

## セットアップ手順

### 1. リポジトリクローン
```bash
git clone <your-company-repository>
cd databricks-oauth-oidc-production
```

### 2. 環境設定
```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

`terraform/terraform.tfvars` を編集:
```hcl
# AWS設定
aws_region = "ap-northeast-1"  # 会社のリージョンに変更
app_name = "databricks-oauth-app"

# IP制限設定（会社のIP範囲に変更）
allowed_ips = [
  "YOUR_COMPANY_IP_RANGE/24",
  "VPN_IP_RANGE/24"
]

# Databricks設定（会社の環境に変更）
databricks_host = "adb-xxxxxxxxx.xx.azuredatabricks.net"
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

#### オプションB: ローカルDocker使用
```bash
# ECR ログイン
aws ecr get-login-password --region $(terraform output -raw aws_region) | docker login --username AWS --password-stdin $(terraform output -raw ecr_repository_url)

# イメージビルド
docker build -t databricks-oauth-app .

# タグ付け
docker tag databricks-oauth-app:latest $(terraform output -raw ecr_repository_url):latest

# プッシュ
docker push $(terraform output -raw ecr_repository_url):latest
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

#### オプションB: EC2プロキシサーバー（推奨）
```bash
# EC2プロキシサーバーを自動でプロビジョニング
terraform apply

# プロキシ状況確認
terraform output proxy_public_ip
terraform output proxy_setup_commands

# localtunnel URL確認（自動設定）
# https://ecs-databricks-oauth.loca.lt
```

#### オプションC: ローカルプロキシ（開発用のみ）
```bash
# localtunnel インストール
npm install -g localtunnel

# プロキシサーバー起動
node proxy-server.js &

# localtunnel 開始
lt --port 8080 --subdomain your-company-app
```

### 7. Databricks Redirect URI更新
Databricks OAuth設定で Redirect URI を以下に更新:
```
https://your-company-domain.com/oauth/callback
```

## OIDC機能詳細

### OIDC Flow
1. **Authorization Request**: `openid` scope を含むOAuth要求
2. **Token Exchange**: authorization code → access_token + id_token
3. **ID Token Processing**: JWT デコードしてユーザー情報抽出
4. **User Info Display**: 名前、メール、ユーザーIDを画面表示

### セキュリティ強化
- **Nonce検証**: CSRF攻撃防止
- **JWT署名検証** (本番環境で有効化)
- **Token有効期限管理**

## 企業SSO統合

### Azure AD統合例
```javascript
// Azure AD OIDC設定例
const OIDC_CONFIG = {
  issuer: "https://login.microsoftonline.com/YOUR_TENANT_ID/v2.0",
  jwks_uri: "https://login.microsoftonline.com/YOUR_TENANT_ID/discovery/v2.0/keys"
};
```

### Okta統合例
```javascript
// Okta OIDC設定例
const OIDC_CONFIG = {
  issuer: "https://YOUR_COMPANY.okta.com/oauth2/default",
  jwks_uri: "https://YOUR_COMPANY.okta.com/oauth2/default/v1/keys"
};
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

## 企業環境でのセキュリティ考慮事項

### 本番環境設定
1. **JWT署名検証**: JWKS エンドポイントからの公開鍵検証
2. **HTTPS強制**: ALB + SSL証明書使用
3. **Secrets管理**: AWS Secrets Manager活用
4. **ネットワーク分離**: Private Subnet + NAT Gateway
5. **VPC Endpoints**: S3、ECR用のVPCエンドポイント設定

### コンプライアンス
- **最小権限**: IAM Role最小化
- **監査ログ**: CloudTrail + Databricks Audit Logs
- **データ保護**: 機密情報の適切な暗号化
- **アクセス制御**: VPN/PrivateLink経由のアクセス限定

## トラブルシューティング

### よくある問題
1. **Redirect URI mismatch**: 会社ドメイン設定とアプリケーション設定の確認
2. **CORS Error**: ALB Security Group設定確認
3. **ID Token missing**: `openid` scope が含まれているか確認
4. **Company firewall**: アウトバウンド通信許可設定

### デバッグコマンド
```bash
# アプリケーションログ
aws logs tail /ecs/databricks-oauth-app --follow

# ECS Service状態
aws ecs describe-services --cluster <cluster-name> --services <service-name>

# Target Group Health
aws elbv2 describe-target-health --target-group-arn <target-group-arn>
```

## 企業環境カスタマイズポイント

### 必須変更項目
- [ ] `terraform.tfvars` の全設定値
- [ ] Databricks OAuth Redirect URI
- [ ] SSL証明書の設定
- [ ] VPCネットワーク設計
- [ ] Security Group ルール

### オプション設定
- [ ] CloudWatch アラート設定
- [ ] Auto Scaling設定
- [ ] Blue/Green デプロイ設定
- [ ] バックアップ戦略

## サポート

企業環境での導入支援が必要な場合は、社内DevOpsチームまたはクラウドアーキテクトにご相談ください。

---

**重要**: 本番環境では必ずセキュリティレビューを実施し、会社のセキュリティポリシーに準拠することを確認してください。