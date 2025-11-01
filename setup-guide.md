# デプロイ手順ガイド - 自動化版

## 🎯 概要

このプロジェクトは**95%自動化**されています。手動作業は初回設定のみです。

### 自動化レベル

| フェーズ | 自動化率 | 説明 |
|----------|----------|------|
| **初回設定** | 10% | Databricks OAuth設定、terraform.tfvars編集 |
| **インフラ構築** | 100% | Terraform完全自動化 |
| **アプリデプロイ** | 100% | CodeBuild + ECS自動デプロイ |
| **更新デプロイ** | 100% | ワンコマンド自動更新 |

---

## 🔧 初回セットアップ（手動）

### 1. Databricks OAuth App作成
```
Databricks Workspace → Settings → Identity and access → OAuth apps
```

**設定値:**
- App name: `ECS Databricks OAuth App`
- Redirect URI: `https://ecs-databricks-oauth.loca.lt/oauth/callback`
- Scopes: `openid`, `all-apis`, `offline_access`

**取得情報:**
- Client ID: `xxx-xxx-xxx`
- Client Secret: `xxx-xxx-xxx`

### 2. 設定ファイル編集
```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

**必須設定項目:**
```hcl
# Databricks設定
databricks_host            = "https://adb-xxxxxx.azuredatabricks.net"
databricks_client_id       = "上記で取得したClient ID"
databricks_client_secret   = "上記で取得したClient Secret"
databricks_endpoint        = "your-serving-endpoint-name"

# セキュリティ設定
allowed_ips = ["YOUR_COMPANY_IP/24"]
```

### 3. AWS認証設定
```bash
aws configure
# または
export AWS_PROFILE=your-profile
```

---

## 🚀 自動デプロイ実行

### ワンコマンドデプロイ
```bash
./deploy.sh
```

**実行内容（完全自動）:**
1. ✅ 前提条件チェック
2. ✅ AWS インフラ構築（Terraform）
3. ✅ Docker イメージビルド（CodeBuild）
4. ✅ ECS サービスデプロイ
5. ✅ EC2 プロキシサーバー起動
6. ✅ HTTPS アクセス準備完了

**実行時間:** 約10-15分

---

## 🔄 更新デプロイ（コード変更時）

### アプリケーション更新
```bash
# コード変更後
./deploy.sh

# または個別実行
aws codebuild start-build --project-name $(cd terraform && terraform output -raw codebuild_project_name)
aws ecs update-service --cluster $(cd terraform && terraform output -raw ecs_cluster_name) --service $(cd terraform && terraform output -raw ecs_service_name) --force-new-deployment
```

### インフラ設定変更
```bash
# terraform.tfvars 編集後
cd terraform
terraform plan
terraform apply
```

---

## 📊 デプロイ後の確認

### 自動出力情報
```bash
# デプロイ完了時に自動表示
ALB URL:    http://xxx.ap-northeast-1.elb.amazonaws.com
HTTPS URL:  https://ecs-databricks-oauth.loca.lt
EC2 IP:     x.x.x.x
```

### 手動確認コマンド
```bash
# アクセス可能性確認
curl https://ecs-databricks-oauth.loca.lt/health

# ログ監視
aws logs tail /ecs/databricks-oauth-app --follow
aws logs tail /aws/ec2/databricks-oauth-app-proxy --follow

# ECS状態確認
aws ecs describe-services --cluster $(cd terraform && terraform output -raw ecs_cluster_name) --services $(cd terraform && terraform output -raw ecs_service_name)
```

---

## 🛠️ トラブルシューティング

### よくある問題と解決策

#### 1. CodeBuild ビルド失敗
```bash
# ログ確認
aws logs filter-log-events --log-group-name "/aws/codebuild/databricks-oauth-app-build" --start-time $(date -d '1 hour ago' +%s)000

# 手動リトライ
aws codebuild start-build --project-name $(cd terraform && terraform output -raw codebuild_project_name)
```

#### 2. ECS タスク起動失敗
```bash
# タスク状態確認
aws ecs list-tasks --cluster $(cd terraform && terraform output -raw ecs_cluster_name)
aws ecs describe-tasks --cluster $(cd terraform && terraform output -raw ecs_cluster_name) --tasks <task-arn>

# 強制再起動
aws ecs update-service --cluster $(cd terraform && terraform output -raw ecs_cluster_name) --service $(cd terraform && terraform output -raw ecs_service_name) --force-new-deployment
```

#### 3. HTTPS アクセス不可
```bash
# プロキシサーバー確認
ssh -i your-key.pem ec2-user@$(cd terraform && terraform output -raw proxy_public_ip)
sudo systemctl status proxy-server
sudo systemctl status localtunnel

# 再起動
sudo systemctl restart proxy-server
sudo systemctl restart localtunnel
```

#### 4. OAuth 認証失敗
- **確認項目:**
  - Databricks Redirect URI: `https://ecs-databricks-oauth.loca.lt/oauth/callback`
  - Client ID/Secret が正しく設定されているか
  - Scopes: `openid all-apis offline_access`

---

## 📈 監視・運用

### 日常監視
```bash
# ヘルスチェック（自動化可能）
curl -f https://ecs-databricks-oauth.loca.lt/health || echo "Service Down"

# ログ監視（自動化可能）
aws logs tail /ecs/databricks-oauth-app --since 1h
```

### メトリクス確認
```bash
# ECS メトリクス
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=$(cd terraform && terraform output -raw ecs_service_name) \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

---

## 🔒 セキュリティ考慮事項

### 本番運用時の追加対応
1. **SSL証明書**: ALB + ACM での HTTPS 直接対応
2. **Secrets管理**: AWS Secrets Manager への移行
3. **ネットワーク分離**: Private Subnet + NAT Gateway
4. **監査ログ**: CloudTrail 有効化

### 緊急時対応
```bash
# 即座にサービス停止
aws ecs update-service --cluster $(cd terraform && terraform output -raw ecs_cluster_name) --service $(cd terraform && terraform output -raw ecs_service_name) --desired-count 0

# 完全削除
terraform destroy -auto-approve
```

---

## 📋 チェックリスト

### 初回デプロイ前
- [ ] Databricks OAuth App作成済み
- [ ] terraform.tfvars 設定完了
- [ ] AWS認証設定済み
- [ ] 必要権限（ECR, ECS, VPC, IAM）確認済み

### デプロイ後
- [ ] https://ecs-databricks-oauth.loca.lt でアクセス可能
- [ ] OAuth認証フロー動作確認
- [ ] Claude Sonnet 4 API呼び出し成功
- [ ] ログ出力正常

### 本番移行前
- [ ] Route53 + ACM でのHTTPS設定
- [ ] Secrets Manager統合
- [ ] 監視・アラート設定
- [ ] バックアップ戦略確定