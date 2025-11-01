#!/bin/bash
# プロキシサーバーの使用例

# ALB URL を環境変数として設定してプロキシサーバーを起動
# 
# 例1: 環境変数 ALB_URL を使用
export ALB_URL="http://your-alb-dns-name.ap-northeast-1.elb.amazonaws.com"
node proxy-server.js

# 例2: 環境変数 TARGET_URL を使用
export TARGET_URL="http://your-alb-dns-name.ap-northeast-1.elb.amazonaws.com"
node proxy-server.js

# 例3: Terraformアウトプットから動的に取得
export ALB_URL="http://$(terraform output -raw alb_dns_name)"
node proxy-server.js

# 例4: ワンライナーで実行
ALB_URL="http://your-alb-dns-name.ap-northeast-1.elb.amazonaws.com" node proxy-server.js

# 例5: ローカル開発用（デフォルト値）
# 環境変数を設定しない場合、http://localhost:3000 が使用されます
node proxy-server.js