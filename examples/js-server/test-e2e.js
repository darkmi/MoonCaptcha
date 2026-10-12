'use strict';
/**
 * JS 目标服务端到端测试：node examples/js-server/test-e2e.js
 * 前置：node examples/js-server/build.js && node examples/js-server/server.js 3300
 */
const crypto = require('crypto');
const BASE = process.env.E2E_BASE || 'http://localhost:3300';

function aesEncrypt(content, key) {
  const c = crypto.createCipheriv('aes-128-ecb', Buffer.from(key, 'utf8'), null);
  return Buffer.concat([c.update(Buffer.from(content, 'utf8')), c.final()]).toString('base64');
}

async function post(path, body) {
  const r = await fetch(BASE + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return r.json();
}

const results = [];
function check(name, cond) {
  results.push([name, cond]);
  console.log((cond ? 'PASS' : 'FAIL') + '  ' + name);
}

async function main() {
  // 1. blockPuzzle 全链路：目标 x ∈ [200, 216)，容差 ±5 → dx=200/206/212 三次必中
  let solved = null;
  for (const dx of [200, 206, 212]) {
    const g = await post('/captcha/get', { kind: 'blockPuzzle' });
    if (g.repCode !== '0000') {
      check('get 成功', false);
      break;
    }
    const d = g.repData;
    check('get 返回双图 base64', d.originalImageBase64.length > 100 && d.jigsawImageBase64.length > 100);
    const raw = `{"x": ${dx}, "y": 5.0}`;
    const r = await post('/captcha/check', {
      kind: 'blockPuzzle',
      token: d.token,
      pointJson: aesEncrypt(raw, d.secretKey),
    });
    if (r.repCode === '0000') {
      solved = { d, raw };
      break;
    }
    check('错误坐标 → 6111', r.repCode === '6111');
  }
  check('blockPuzzle 暴力定位并 check 成功', !!solved);
  if (solved) {
    const verification = aesEncrypt(solved.d.token + '---' + solved.raw, solved.d.secretKey);
    const v1 = await post('/captcha/verify', { captchaVerification: verification });
    check('verify → 0000', v1.repCode === '0000');
    const v2 = await post('/captcha/verify', { captchaVerification: verification });
    check('verify 重放 → 6110（防重放）', v2.repCode === '6110');
  }
  // 2. clickWord get：结构校验（4 字绘制 3 字点击；无字体时文字不烧录，仅协议测试）
  const cw = await post('/captcha/get', { kind: 'clickWord' });
  check('clickWord get → 0000', cw.repCode === '0000');
  check('clickWord wordList 3 项', cw.repData && cw.repData.wordList.length === 3);
  check('clickWord secretKey 16 位', cw.repData.secretKey.length === 16);
  // 3. token 一次性
  if (solved) {
    const r = await post('/captcha/check', {
      kind: 'blockPuzzle',
      token: solved.d.token,
      pointJson: aesEncrypt(solved.raw, solved.d.secretKey),
    });
    check('token 二次使用 → 6110', r.repCode === '6110');
  }

  console.log(`\n${results.filter(([, ok]) => ok).length}/${results.length} passed`);
  process.exit(results.some(([, ok]) => !ok) ? 1 : 0);
}

main().catch((e) => {
  console.error('E2E error:', e.message);
  process.exit(1);
});
