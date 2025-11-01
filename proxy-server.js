const http = require('http');
const httpProxy = require('http-proxy');

const proxy = httpProxy.createProxyServer({});
const ALB_URL = 'http://ecs-databricks-app-415024499.ap-northeast-1.elb.amazonaws.com';

const server = http.createServer((req, res) => {
  console.log(`Proxying: ${req.method} ${req.url}`);
  proxy.web(req, res, {
    target: ALB_URL,
    changeOrigin: true
  });
});

const PORT = 8080;
server.listen(PORT, () => {
  console.log(`Proxy server running on http://localhost:${PORT}`);
  console.log(`Forwarding to: ${ALB_URL}`);
});

proxy.on('error', (err, req, res) => {
  console.error('Proxy error:', err);
  res.writeHead(500, {
    'Content-Type': 'text/plain'
  });
  res.end('Proxy error occurred');
});