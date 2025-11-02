const express = require('express');
const session = require('express-session');
const axios = require('axios');
const { v4: uuidv4 } = require('uuid');
const jwt = require('jsonwebtoken');
const jwksRsa = require('jwks-rsa');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(express.static('public'));
app.set('view engine', 'ejs');

// Session configuration
app.use(session({
  secret: process.env.SESSION_SECRET || 'databricks-oauth-secret',
  resave: false,
  saveUninitialized: false,
  cookie: { 
    secure: false, // Set to true in production with HTTPS
    maxAge: 24 * 60 * 60 * 1000 // 24 hours
  }
}));

// OAuth Configuration
const OAUTH_CONFIG = {
  clientId: process.env.DATABRICKS_CLIENT_ID,
  clientSecret: process.env.DATABRICKS_CLIENT_SECRET,
  databricksHost: process.env.DATABRICKS_HOST,
  redirectUri: process.env.REDIRECT_URI || `http://localhost:${PORT}/oauth/callback`,
  endpoint: process.env.DATABRICKS_SERVING_ENDPOINT || 'databricks-claude-sonnet-4'
};

// Routes

// Home page
app.get('/', (req, res) => {
  res.render('index', {
    isAuthenticated: !!req.session.accessToken,
    userInfo: req.session.userInfo || null,
    pendingRequest: req.session.pendingRequest || null,
    lastSummary: req.session.lastSummary || null,
    error: req.query.error || null
  });
});

// Handle summary request
app.post('/summarize', async (req, res) => {
  const { text } = req.body;
  
  if (!text || !text.trim()) {
    return res.redirect('/?error=テキストを入力してください');
  }

  // Save the request for after authentication
  req.session.pendingRequest = {
    text: text.trim(),
    timestamp: new Date().toISOString()
  };

  // Check if user is authenticated
  if (!req.session.accessToken) {
    // Redirect to OAuth
    const state = uuidv4();
    req.session.oauthState = state;
    
    const nonce = uuidv4();
    req.session.oauthNonce = nonce;
    
    const authUrl = `${OAUTH_CONFIG.databricksHost}/oidc/v1/authorize?` +
      `response_type=code&` +
      `client_id=${OAUTH_CONFIG.clientId}&` +
      `redirect_uri=${encodeURIComponent(OAUTH_CONFIG.redirectUri)}&` +
      `scope=openid all-apis offline_access&` +
      `state=${state}&` +
      `nonce=${nonce}`;
    
    return res.redirect(authUrl);
  }

  // User is authenticated, execute summary
  try {
    const summary = await callDatabricksModelServing(req.session.accessToken, text);
    req.session.lastSummary = {
      text: text.substring(0, 100) + '...',
      result: summary,
      timestamp: new Date().toLocaleString('ja-JP')
    };
    req.session.pendingRequest = null;
    res.redirect('/');
  } catch (error) {
    console.error('Summary error:', error);
    res.redirect('/?error=要約実行エラー: ' + error.message);
  }
});

// OAuth callback
app.get('/oauth/callback', async (req, res) => {
  const { code, state, error } = req.query;

  if (error) {
    return res.redirect('/?error=認証エラー: ' + error);
  }

  if (!code || !state || state !== req.session.oauthState) {
    return res.redirect('/?error=無効な認証コールバック');
  }

  try {
    // Exchange code for token
    const tokenResponse = await axios.post(`${OAUTH_CONFIG.databricksHost}/oidc/v1/token`, {
      grant_type: 'authorization_code',
      code: code,
      redirect_uri: OAUTH_CONFIG.redirectUri,
      client_id: OAUTH_CONFIG.clientId,
      client_secret: OAUTH_CONFIG.clientSecret
    }, {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded'
      }
    });

    const { access_token, id_token, refresh_token } = tokenResponse.data;
    
    req.session.accessToken = access_token;
    req.session.refreshToken = refresh_token;
    req.session.oauthState = null;
    req.session.oauthNonce = null;

    // Process ID Token (OIDC user info)
    if (id_token) {
      try {
        // Decode ID token (在本番環境では署名検証が必要)
        const userInfo = jwt.decode(id_token);
        console.log('ID Token payload:', userInfo);
        
        // Verify nonce if present
        if (userInfo.nonce && userInfo.nonce !== req.session.oauthNonce) {
          console.warn('Nonce verification failed');
        }
        
        req.session.userInfo = {
          sub: userInfo.sub,
          email: userInfo.email || userInfo.preferred_username || 'N/A',
          name: userInfo.name || userInfo.given_name || userInfo.email || 'Unknown User',
          picture: userInfo.picture || null,
          iss: userInfo.iss,
          aud: userInfo.aud,
          exp: userInfo.exp,
          iat: userInfo.iat
        };
        
        console.log('User Info stored:', req.session.userInfo);
      } catch (error) {
        console.error('ID Token processing error:', error);
        req.session.userInfo = { name: '認証済みユーザー', email: 'N/A' };
      }
    } else {
      req.session.userInfo = { name: '認証済みユーザー', email: 'N/A' };
    }

    // Execute pending request if exists
    if (req.session.pendingRequest) {
      try {
        const summary = await callDatabricksModelServing(
          req.session.accessToken, 
          req.session.pendingRequest.text
        );
        
        req.session.lastSummary = {
          text: req.session.pendingRequest.text.substring(0, 100) + '...',
          result: summary,
          timestamp: new Date().toLocaleString('ja-JP')
        };
        req.session.pendingRequest = null;
      } catch (error) {
        console.error('Auto-summary error:', error);
        return res.redirect('/?error=要約実行エラー: ' + error.message);
      }
    }

    res.redirect('/');
  } catch (error) {
    console.error('Token exchange error:', error);
    res.redirect('/?error=トークン交換エラー: ' + error.response?.data?.error_description || error.message);
  }
});

// Execute pending request
app.post('/execute-pending', async (req, res) => {
  if (!req.session.accessToken || !req.session.pendingRequest) {
    return res.redirect('/?error=認証または保留リクエストが見つかりません');
  }

  try {
    const summary = await callDatabricksModelServing(
      req.session.accessToken, 
      req.session.pendingRequest.text
    );
    
    req.session.lastSummary = {
      text: req.session.pendingRequest.text.substring(0, 100) + '...',
      result: summary,
      timestamp: new Date().toLocaleString('ja-JP')
    };
    req.session.pendingRequest = null;
    res.redirect('/');
  } catch (error) {
    console.error('Execute pending error:', error);
    res.redirect('/?error=要約実行エラー: ' + error.message);
  }
});

// Sample text endpoint
app.post('/sample', (req, res) => {
  const sampleText = `Data Engineering Design Patterns Data projects are an intrinsic part of an organization's technical ecosystem, but data engineers in many companies continue to work on problems that others have already solved. This hands-on guide shows you how to provide valuable data by focusing on various aspects of data engineering, including data ingestion, data quality, idempotency, and more. Author Bartosz Konieczny guides you through the process of building reliable end-to-end data engineering projects, from data ingestion to data observability, focusing on data engineering design patterns that solve common business problems in a secure and storage-optimized manner.`;
  
  req.session.pendingRequest = {
    text: sampleText,
    timestamp: new Date().toISOString()
  };
  
  res.redirect('/');
});

// Clear results
app.post('/clear', (req, res) => {
  req.session.lastSummary = null;
  req.session.pendingRequest = null;
  res.redirect('/');
});

// Logout
app.post('/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/');
});

// Helper function to call Databricks model serving
async function callDatabricksModelServing(accessToken, text) {
  const response = await axios.post(
    `${OAUTH_CONFIG.databricksHost}/serving-endpoints/${OAUTH_CONFIG.endpoint}/invocations`,
    {
      messages: [
        {
          role: 'user',
          content: `以下のテキストを日本語で要約してください:\n\n${text}`
        }
      ],
      max_tokens: 1000
    },
    {
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      },
      timeout: 30000
    }
  );

  return response.data.choices[0].message.content;
}

// Start server
app.listen(PORT, () => {
  console.log(`🚀 Server running on http://localhost:${PORT}`);
  console.log(`📋 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`🔗 Databricks Host: ${OAUTH_CONFIG.databricksHost}`);
  console.log(`🔑 Client ID: ${OAUTH_CONFIG.clientId}`);
  console.log(`↩️  Redirect URI: ${OAUTH_CONFIG.redirectUri}`);
});