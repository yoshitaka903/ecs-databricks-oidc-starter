#!/bin/bash
# EC2 User Data Script for Proxy Server Setup

# 変数設定
ALB_DNS_NAME="${alb_dns_name}"
APP_NAME="${app_name}"
LOG_GROUP="/aws/ec2/$APP_NAME-proxy"

# CloudWatch Logs Agent設定
yum update -y
yum install -y awslogs

# CloudWatch Logs設定
cat > /etc/awslogs/awslogs.conf << EOF
[general]
state_file = /var/lib/awslogs/agent-state

[/var/log/proxy.log]
file = /var/log/proxy.log
log_group_name = $LOG_GROUP
log_stream_name = {instance_id}/proxy
datetime_format = %Y-%m-%d %H:%M:%S
EOF

# CloudWatchエージェント開始
systemctl start awslogsd
systemctl enable awslogsd

# Node.js インストール
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

# プロキシ用ディレクトリ作成
mkdir -p /opt/proxy
cd /opt/proxy

# package.json作成
cat > package.json << 'EOF'
{
  "name": "ecs-proxy-server",
  "version": "1.0.0",
  "description": "HTTPS Proxy for ECS Application",
  "main": "proxy-server.js",
  "dependencies": {
    "express": "^4.18.2",
    "http-proxy": "^1.18.1"
  }
}
EOF

# プロキシサーバーコード作成
cat > proxy-server.js << 'EOF'
const express = require('express');
const httpProxy = require('http-proxy');

const app = express();
const proxy = httpProxy.createProxyServer({});
const PORT = 8080;

// 環境変数からALB URLを取得
const TARGET_URL = process.env.ALB_URL || 'PLACEHOLDER_ALB_URL';

console.log(`Starting proxy server on port $${PORT}`);
console.log(`Proxying to: $${TARGET_URL}`);

// ヘルスチェック
app.get('/health', (req, res) => {
  res.status(200).json({ 
    status: 'healthy', 
    target: TARGET_URL,
    timestamp: new Date().toISOString()
  });
});

// 全リクエストをALBに転送
app.use('/', (req, res) => {
  console.log(`$${new Date().toISOString()} - $${req.method} $${req.url}`);
  
  proxy.web(req, res, { 
    target: TARGET_URL,
    changeOrigin: true,
    timeout: 30000
  }, (err) => {
    console.error(`Proxy error: $${err.message}`);
    res.status(500).send('Proxy Error');
  });
});

// エラーハンドリング
proxy.on('error', (err, req, res) => {
  console.error('Proxy error:', err);
  if (!res.headersSent) {
    res.writeHead(500, { 'Content-Type': 'text/plain' });
    res.end('Proxy server error');
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Proxy server running on http://0.0.0.0:$${PORT}`);
});
EOF

# プレースホルダーを実際のALB URLに置換
sed -i "s/PLACEHOLDER_ALB_URL/http:\/\/$ALB_DNS_NAME/" proxy-server.js

# 環境変数設定
echo "export ALB_URL=http://$ALB_DNS_NAME" >> /etc/environment

# パッケージインストール
npm install

# systemdサービス作成
cat > /etc/systemd/system/proxy-server.service << EOF
[Unit]
Description=ECS HTTPS Proxy Server
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/proxy
Environment=ALB_URL=http://$ALB_DNS_NAME
ExecStart=/usr/bin/node proxy-server.js
Restart=always
RestartSec=10
StandardOutput=append:/var/log/proxy.log
StandardError=append:/var/log/proxy.log

[Install]
WantedBy=multi-user.target
EOF

# サービス開始
systemctl daemon-reload
systemctl enable proxy-server
systemctl start proxy-server

# localtunnel インストール・設定
npm install -g localtunnel

# localtunnel用systemdサービス
cat > /etc/systemd/system/localtunnel.service << EOF
[Unit]
Description=Localtunnel HTTPS Service
After=network.target proxy-server.service
Requires=proxy-server.service

[Service]
Type=simple
User=ec2-user
Environment=PATH=/usr/bin:/usr/local/bin
ExecStart=/usr/local/bin/lt --port 8080 --subdomain ecs-databricks-oauth
Restart=always
RestartSec=30
StandardOutput=append:/var/log/localtunnel.log
StandardError=append:/var/log/localtunnel.log

[Install]
WantedBy=multi-user.target
EOF

# localtunnelサービス開始
systemctl enable localtunnel
systemctl start localtunnel

# ログ出力
echo "$(date): Proxy server setup completed" >> /var/log/proxy.log
echo "ALB Target: http://$ALB_DNS_NAME" >> /var/log/proxy.log
echo "Localtunnel URL: https://ecs-databricks-oauth.loca.lt" >> /var/log/proxy.log