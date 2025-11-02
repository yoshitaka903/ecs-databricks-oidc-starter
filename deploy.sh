#!/bin/bash
set -e

# デプロイ自動化スクリプト
echo "=========================================="
echo "ECS Databricks OAuth App - 自動デプロイ"
echo "=========================================="

# 色付きログ
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 前提条件チェック
check_prerequisites() {
    log_info "前提条件をチェック中..."
    
    # AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI が見つかりません"
        exit 1
    fi
    
    # Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform が見つかりません"
        exit 1
    fi
    
    # terraform.tfvars
    if [ ! -f "terraform/terraform.tfvars" ]; then
        log_error "terraform/terraform.tfvars が見つかりません"
        log_warning "terraform/terraform.tfvars.example をコピーして設定してください"
        exit 1
    fi
    
    # AWS認証
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS認証に失敗しました"
        exit 1
    fi
    
    log_success "前提条件チェック完了"
}

# Terraformデプロイ
deploy_infrastructure() {
    log_info "インフラストラクチャをデプロイ中..."
    
    cd terraform
    
    # 初期化
    log_info "Terraform初期化中..."
    terraform init
    
    # プラン
    log_info "Terraformプラン生成中..."
    terraform plan -out=tfplan
    
    # 適用
    log_info "Terraformプラン適用中..."
    terraform apply tfplan
    
    cd ..
    log_success "インフラストラクチャデプロイ完了"
}

# Docker イメージビルド
build_and_push_image() {
    log_info "Docker イメージをビルド中..."

    # リージョンとCodeBuild プロジェクト名取得
    local aws_region=$(cd terraform && terraform output -raw aws_region)
    local codebuild_project=$(cd terraform && terraform output -raw codebuild_project_name)

    # ビルド開始
    log_info "CodeBuild でビルド開始: $codebuild_project (Region: $aws_region)"
    local build_id=$(aws codebuild start-build --region "$aws_region" --project-name "$codebuild_project" --query 'build.id' --output text)
    
    log_info "Build ID: $build_id"
    log_info "ビルド状況を監視中..."
    
    # ビルド完了まで待機
    while true; do
        local build_status=$(aws codebuild batch-get-builds --region "$aws_region" --ids "$build_id" --query 'builds[0].buildStatus' --output text)
        
        case $build_status in
            "IN_PROGRESS")
                echo -n "."
                sleep 10
                ;;
            "SUCCEEDED")
                echo ""
                log_success "Docker イメージビルド完了"
                break
                ;;
            "FAILED"|"FAULT"|"STOPPED"|"TIMED_OUT")
                echo ""
                log_error "Docker イメージビルド失敗: $build_status"
                
                # ログ表示
                log_info "CodeBuild ログを表示..."
                aws logs filter-log-events \
                    --region "$aws_region" \
                    --log-group-name "/aws/codebuild/$codebuild_project" \
                    --start-time $(($(date +%s) - 3600))000 \
                    --query 'events[*].message' \
                    --output text
                
                exit 1
                ;;
            *)
                echo -n "."
                sleep 10
                ;;
        esac
    done
}

# ECS サービス更新
update_ecs_service() {
    log_info "ECS サービスを更新中..."

    local aws_region=$(cd terraform && terraform output -raw aws_region)
    local cluster_name=$(cd terraform && terraform output -raw ecs_cluster_name)
    local service_name=$(cd terraform && terraform output -raw ecs_service_name)

    # サービス強制更新
    aws ecs update-service \
        --region "$aws_region" \
        --cluster "$cluster_name" \
        --service "$service_name" \
        --force-new-deployment \
        --query 'service.serviceName' \
        --output text

    log_info "ECS タスク更新完了まで待機中..."
    aws ecs wait services-stable \
        --region "$aws_region" \
        --cluster "$cluster_name" \
        --services "$service_name"
    
    log_success "ECS サービス更新完了"
}

# デプロイ状況確認
verify_deployment() {
    log_info "デプロイ状況を確認中..."

    cd terraform

    # 出力情報表示
    echo ""
    echo "=========================================="
    log_success "デプロイ完了！"
    echo "=========================================="

    echo ""
    log_info "アクセス情報:"
    echo "  HTTPS URL (CloudFront): $(terraform output -raw cloudfront_https_url)"
    echo "  HTTP URL (ALB):         $(terraform output -raw application_url)"
    echo ""

    log_info "監視コマンド:"
    echo "  ECS ログ:   aws logs tail $(terraform output -raw cloudwatch_log_group) --follow"
    echo ""

    log_warning "次のステップ:"
    echo "  1. Databricks OAuth設定でRedirect URIを更新:"
    echo "     $(terraform output -raw oauth_redirect_uri_cloudfront)"
    echo "  2. アプリケーションにアクセスしてテスト:"
    echo "     $(terraform output -raw cloudfront_https_url)"

    cd ..
}

# メイン実行
main() {
    echo "デプロイを開始します..."
    echo ""
    
    check_prerequisites
    deploy_infrastructure
    build_and_push_image
    update_ecs_service
    verify_deployment
    
    log_success "全自動デプロイ完了！"
}

# スクリプト実行
main "$@"