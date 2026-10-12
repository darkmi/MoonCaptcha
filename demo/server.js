'use strict';
/**
 * MoonCaptcha 行为验证码演示服务（Node.js，零外部依赖）。
 *
 * 端点（协议对齐 AJ-Captcha）：
 *   POST /captcha/get     { captchaType: "blockPuzzle" | "clickWord" }
 *   POST /captcha/check   { captchaType, token, pointJson }
 *   POST /captcha/verify  { captchaVerification }
 *   POST /login           { username, password, captchaVerification }
 *   GET  /*               静态文件（public/）
 *
 * 启动：node demo/server.js   →  http://localhost:3000
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const { decodePNG } = require('./lib/png');
const captcha = require('./lib/captcha');

const PORT = Number(process.env.PORT) || 3000;
const PUBLIC_DIR = path.join(__dirname, 'public');
const ASSET_DIR = path.join(__dirname, 'assets');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.json': 'application/json; charset=utf-8',
};

function listPNG(dir) {
  return fs
    .readdirSync(dir)
    .filter((f) => f.endsWith('.png'))
    .map((f) => decodePNG(fs.readFileSync(path.join(dir, f))));
}

const store = {
  cache: new captcha.TTLCache(),
  backgrounds: listPNG(path.join(ASSET_DIR, 'backgrounds')),
  sliders: listPNG(path.join(ASSET_DIR, 'sliders')),
  clickBackgrounds: listPNG(path.join(ASSET_DIR, 'click')),
};

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (c) => {
      data += c;
      if (data.length > 5 * 1024 * 1024) reject(new Error('body too large'));
    });
    req.on('end', () => resolve(data));
    req.on('error', reject);
  });
}

function send(res, status, type, body) {
  res.writeHead(status, { 'Content-Type': type });
  res.end(body);
}

function sendJSON(res, obj) {
  send(res, 200, 'application/json; charset=utf-8', JSON.stringify(obj));
}

async function handle(req, res) {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  if (url.pathname.startsWith('/captcha/') && req.method === 'POST') {
    const body = JSON.parse((await readBody(req)) || '{}');
    const action = url.pathname.slice('/captcha/'.length);
    if (action === 'get') {
      if (body.captchaType === 'blockPuzzle') return sendJSON(res, captcha.getBlockPuzzle(store));
      if (body.captchaType === 'clickWord') return sendJSON(res, captcha.getClickWord(store));
      return sendJSON(res, { repCode: '0011', repMsg: 'captchaType不能为空' });
    }
    if (action === 'check') {
      const r =
        body.captchaType === 'clickWord'
          ? captcha.checkClickWord(store, body)
          : captcha.checkBlockPuzzle(store, body);
      return sendJSON(res, r);
    }
    if (action === 'verify') {
      return sendJSON(res, captcha.verify(store, body.captchaVerification));
    }
    return send(res, 404, 'text/plain', 'not found');
  }
  if (url.pathname === '/login' && req.method === 'POST') {
    const body = JSON.parse((await readBody(req)) || '{}');
    if (!body.username || !body.password) {
      return sendJSON(res, { ok: false, message: '用户名和密码不能为空' });
    }
    const v = captcha.verify(store, body.captchaVerification);
    if (v.repCode !== '0000') {
      return sendJSON(res, { ok: false, message: `二次校验失败（repCode=${v.repCode}）：${v.repMsg}` });
    }
    return sendJSON(res, { ok: true, message: `欢迎，${body.username}！验证码二次校验通过。` });
  }
  // 静态文件
  let file = url.pathname === '/' ? '/index.html' : url.pathname;
  file = path.normalize(file).replace(/^([.][.][/\\])+/, '');
  const full = path.join(PUBLIC_DIR, file);
  if (!full.startsWith(PUBLIC_DIR) || !fs.existsSync(full) || !fs.statSync(full).isFile()) {
    return send(res, 404, 'text/plain; charset=utf-8', '404 not found');
  }
  send(res, 200, MIME[path.extname(full)] || 'application/octet-stream', fs.readFileSync(full));
}

http
  .createServer((req, res) => {
    handle(req, res).catch((e) => {
      sendJSON(res, { repCode: '9999', repMsg: '服务器内部异常: ' + e.message });
    });
  })
  .listen(PORT, () => {
    console.log(`MoonCaptcha demo server: http://localhost:${PORT}`);
    console.log(
      `assets: ${store.backgrounds.length} backgrounds, ${store.sliders.length} sliders, ${store.clickBackgrounds.length} click images`,
    );
  });
