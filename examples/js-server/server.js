'use strict';
/**
 * MoonCaptcha JS 目标 HTTP 服务示例。
 *
 * 宿主只做 HTTP ↔ JSON 搬运：验证码生成、AES 校验、坐标比对、
 * 缓存、频控全部由 MoonBit 核心完成（moon build --target js 产物）。
 *
 * 启动：
 *   node examples/js-server/build.js
 *   node examples/js-server/server.js [port]
 *
 * 可选环境变量：
 *   MOONCAPTCHA_FONT  TTF 字体路径——提供后 clickWord 文字烧录到底图
 *                     （如 AJ-Captcha 自带的 WenQuanZhengHei.ttf）
 *   MOONCAPTCHA_CLIENT_ID  调试时固定 client_id（默认按远程地址）
 */
const http = require('http');
const fs = require('fs');
const path = require('path');

// 加载 MoonBit 核心（构建产物；加载即完成全局状态初始化）
const moon = require(path.join(__dirname, 'build', 'moonbit_lib.cjs'));

const PORT = Number(process.argv[2] || process.env.PORT || 3300);

// 初始化：可带字体
const fontPath = process.env.MOONCAPTCHA_FONT;
let fontB64 = '';
if (fontPath) {
  fontB64 = fs.readFileSync(fontPath).toString('base64');
  console.log(`font: ${fontPath}`);
}
const initResp = moon.js_captcha_init(fontB64);
if (!initResp.startsWith('OK')) {
  console.error('init failed:', initResp);
  process.exit(1);
}

function clientId(req) {
  if (process.env.MOONCAPTCHA_CLIENT_ID) return process.env.MOONCAPTCHA_CLIENT_ID;
  return req.socket.remoteAddress || '';
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (c) => {
      data += c;
      if (data.length > 1024 * 1024) reject(new Error('body too large'));
    });
    req.on('end', () => resolve(data));
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  const route = req.method + ' ' + req.url.split('?')[0];
  let payload = '{}';
  if (req.method === 'POST') payload = (await readBody(req)) || '{}';
  let out;
  try {
    // 把远程地址并入请求体作为 client_id（应用可改为 ip+UA 哈希）
    const merged = JSON.stringify({ ...JSON.parse(payload), clientId: clientId(req) });
    switch (route) {
      case 'POST /captcha/get':
        out = moon.js_captcha_get(merged);
        break;
      case 'POST /captcha/check':
        out = moon.js_captcha_check(merged);
        break;
      case 'POST /captcha/verify':
        out = moon.js_captcha_verify(merged);
        break;
      case 'GET /health':
        out = JSON.stringify({ ok: true, engine: 'moonbit' });
        break;
      default:
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ repCode: '404', repMsg: 'not found' }));
        return;
    }
  } catch (e) {
    out = JSON.stringify({ repCode: '9999', repMsg: 'exception: ' + e.message });
  }
  res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(out);
});

server.listen(PORT, () => {
  console.log(`MoonCaptcha js-server (MoonBit engine): http://localhost:${PORT}`);
  console.log('endpoints: POST /captcha/get | /captcha/check | /captcha/verify');
});
