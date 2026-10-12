'use strict';
/**
 * MoonCaptcha 演示服务：blockPuzzle（滑动拼图）与 clickWord（文字点选）。
 *
 * 协议逐条对照 AJ-Captcha（见 docs/aj-captcha-analysis.md）：
 * - 缓存 key：RUNNING:CAPTCHA:{token}（TTL 120s）、RUNNING:CAPTCHA:second-{verification}（TTL 180s）
 * - check：token 一次性；AES-128-ECB 解密 pointJson；滑动 |Δx|≤5 且 y 严格相等；
 *   点选逐点 |Δx|≤25 且 |Δy|≤25；通过后生成 verification = AES(token + "---" + pointJson)
 * - 抠图：逐像素对照 cutByTemplate（含"6 像素求和 / 除 8"与跳过中行的 Java 怪癖）
 * 与 MoonBit 核心的差异仅在于宿主实现（Node crypto / Buffer），语义一致。
 */
const crypto = require('crypto');
const { encodePNG } = require('./png');

// ---------- 随机工具（语义对齐 RandomUtils） ----------

function randInt(start, end) {
  // [start, end)
  return start + Math.floor(Math.random() * (end - start));
}

function randomString(length) {
  const pool = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let s = '';
  for (let i = 0; i < length; i++) s += pool[Math.floor(Math.random() * pool.length)];
  return s;
}

function uuid() {
  return crypto.randomBytes(16).toString('hex');
}

// ---------- TTL 缓存（语义对齐 CacheUtil） ----------

class TTLCache {
  constructor() {
    this.map = new Map(); // key -> { value, holdTime }
  }
  set(key, value, expiresInSeconds) {
    this.map.set(key, {
      value,
      holdTime: expiresInSeconds > 0 ? Date.now() + expiresInSeconds * 1000 : 0,
    });
  }
  get(key) {
    const e = this.map.get(key);
    if (!e) return null;
    if (e.holdTime !== 0 && e.holdTime < Date.now()) {
      this.map.delete(key);
      return null;
    }
    return e.value;
  }
  delete(key) {
    this.map.delete(key);
  }
}

// ---------- AES（AES-128-ECB-PKCS7，密钥 16 字符 UTF-8；空密钥直通） ----------

function aesDecrypt(encryptedBase64, key) {
  if (!key) return encryptedBase64;
  try {
    const d = crypto.createDecipheriv('aes-128-ecb', Buffer.from(key, 'utf8'), null);
    return Buffer.concat([d.update(Buffer.from(encryptedBase64, 'base64')), d.final()]).toString('utf8');
  } catch (e) {
    return null;
  }
}

function aesEncrypt(content, key) {
  if (!key) return content;
  try {
    const c = crypto.createCipheriv('aes-128-ecb', Buffer.from(key, 'utf8'), null);
    return Buffer.concat([c.update(Buffer.from(content, 'utf8')), c.final()]).toString('base64');
  } catch (e) {
    return null;
  }
}

// ---------- 抠图（逐像素对照 cutByTemplate） ----------

function alphaAt(px, i) {
  return px[i * 4 + 3];
}

function blendWithWhite(r, g, b, alpha) {
  const ratio = alpha / 255;
  return [
    Math.floor(r * (1 - ratio) + 255 * ratio),
    Math.floor(g * (1 - ratio) + 255 * ratio),
    Math.floor(b * (1 - ratio) + 255 * ratio),
  ];
}

// readPixel 边界怪癖：x 越界取绝对值，y 越界用当前值
function neighbor(img, x, y) {
  let tx = x,
    ty = y;
  if (tx < 0) tx = -tx;
  else if (tx >= img.width) tx = x;
  if (ty < 0) ty = -ty;
  else if (ty >= img.height) ty = y;
  const i = (ty * img.width + tx) * 4;
  return [img.px[i], img.px[i + 1], img.px[i + 2]];
}

// avgMatrix 怪癖：跳过中间整行（6 像素求和）后仍除以 8
function avgAround(img, x, y) {
  let r = 0,
    g = 0,
    b = 0;
  for (let di = -1; di <= 1; di++) {
    for (let dj = -1; dj <= 1; dj++) {
      if (dj === 0) continue;
      const [pr, pg, pb] = neighbor(img, x + di, y + dj);
      r += pr;
      g += pg;
      b += pb;
    }
  }
  return [r / 8, g / 8, b / 8].map(Math.floor);
}

/**
 * 在 bg（会被就地修改）上按模板抠图，返回滑块小图 { width, height, px }。
 * - alpha > 200：小图 = 背景色 + 模板 alpha；背景 = 6 邻域"和/8"模糊
 * - 0 < alpha ≤ 200：背景 = 白描边（按 alpha 混白）；小图 = 白色 + 模板 alpha
 */
function cutByTemplate(bg, tpl, x, y) {
  const piece = { width: tpl.width, height: tpl.height, px: new Uint8Array(tpl.width * tpl.height * 4) };
  for (let i = 0; i < tpl.width; i++) {
    for (let j = 0; j < tpl.height; j++) {
      const ti = j * tpl.width + i;
      const alpha = tpl.px[ti * 4 + 3];
      if (alpha <= 0) continue;
      const tx = x + i,
        ty = y + j;
      if (tx < 0 || ty < 0 || tx >= bg.width || ty >= bg.height) continue;
      const bi = (ty * bg.width + tx) * 4;
      if (alpha > 200) {
        piece.px[ti * 4] = bg.px[bi];
        piece.px[ti * 4 + 1] = bg.px[bi + 1];
        piece.px[ti * 4 + 2] = bg.px[bi + 2];
        piece.px[ti * 4 + 3] = alpha;
        const [r, g, b] = avgAround(bg, tx, ty);
        bg.px[bi] = r;
        bg.px[bi + 1] = g;
        bg.px[bi + 2] = b;
        bg.px[bi + 3] = 255;
      } else {
        const [r, g, b] = blendWithWhite(bg.px[bi], bg.px[bi + 1], bg.px[bi + 2], alpha);
        bg.px[bi] = r;
        bg.px[bi + 1] = g;
        bg.px[bi + 2] = b;
        bg.px[bi + 3] = 255;
        piece.px[ti * 4] = 255;
        piece.px[ti * 4 + 1] = 255;
        piece.px[ti * 4 + 2] = 255;
        piece.px[ti * 4 + 3] = alpha;
      }
    }
  }
  return piece;
}

// ---------- 协议响应包装 ----------

const ok = (data) => ({ repCode: '0000', repMsg: '成功', repData: data });
const err = (repCode, repMsg) => ({ repCode, repMsg });

// ---------- 服务 ----------

const CAPTCHA_KEY = (token) => 'RUNNING:CAPTCHA:' + token;
const SECOND_KEY = (v) => 'RUNNING:CAPTCHA:second-' + v;
const EXPIRES_IN = 120; // 秒，验证码坐标
const SECOND_EXPIRES_IN = 180; // 秒，二次校验凭证
const SLIP_OFFSET = 5;
const HAN_ZI_SIZE = 25;

const HAN_ZI =
  '\u7684\u4e00\u4e86\u662f\u6211\u4e0d\u5728\u4eba\u4eec\u6709\u6765\u4ed6\u8fd9\u4e0a\u7740\u4e2a\u5730\u5230\u5927\u91cc\u8bf4\u5c31\u53bb\u5b50\u5f97\u4e5f\u548c\u90a3\u8981\u4e0b\u770b\u5929\u65f6\u8fc7\u51fa\u5c0f\u4e48\u8d77\u4f60\u90fd\u628a\u597d\u8fd8\u591a\u6ca1\u4e3a\u53c8\u53ef\u5bb6\u5b66\u53ea\u4ee5\u4e3b\u4f1a\u6837\u5e74\u60f3\u751f\u540c\u8001\u4e2d\u5341\u4ece\u81ea\u9762\u524d\u5934\u9053\u5b83\u540e\u7136\u8d70\u5f88\u50cf\u89c1\u4e24\u7528\u5979\u56fd\u52a8\u8fdb\u6210\u56de\u4ec0\u8fb9\u4f5c\u5bf9\u5f00\u800c\u5df1\u4e9b\u73b0\u5c71\u6c11\u5019\u7ecf\u53d1\u5de5\u5411\u4e8b\u547d\u7ed9\u957f\u6c34\u51e0\u4e49\u4e09\u58f0\u4e8e\u9ad8\u624b\u77e5\u7406\u773c\u5fd7\u70b9\u5fc3\u6218\u4e8c\u95ee\u4f46\u8eab\u65b9\u5b9e\u5403\u505a\u53eb\u5f53\u4f4f\u542c\u9769\u6253\u5462\u771f\u5168\u624d\u56db\u5df2\u6240\u654c\u4e4b\u6700\u5149\u4ea7\u60c5\u8def\u5206\u603b\u6761\u767d\u8bdd\u4e1c\u5e2d\u6b21\u4eb2\u5982\u88ab\u82b1\u53e3\u653e\u513f\u5e38\u6c14\u4e94\u7b2c\u4f7f\u5199\u519b\u5427\u6587\u8fd0\u518d\u679c\u600e\u5b9a\u8bb8\u5feb\u660e\u884c\u56e0\u522b\u98de\u5916\u6811\u7269\u6d3b\u90e8\u95e8\u65e0\u5f80\u8239\u671b\u65b0\u5e26\u961f\u5148\u529b\u5b8c\u5374\u7ad9\u4ee3\u5458\u673a\u66f4\u4e5d\u60a8\u6bcf\u98ce\u7ea7\u8ddf\u7b11\u554a\u5b69\u4e07\u5c11\u76f4\u610f\u591c\u6bd4\u9636\u8fde\u8f66\u91cd\u4fbf\u6597\u9a6c\u54ea\u5316\u592a\u6307\u53d8\u793e\u4f3c\u58eb\u8005\u5e72\u77f3\u6ee1\u65e5\u51b3\u767e\u539f\u62ff\u7fa4\u7a76\u5404\u516d\u672c\u601d\u89e3\u7acb\u6cb3\u6751\u516b\u96be\u65e9\u8bba\u5417\u6839\u5171\u8ba9\u76f8\u7814\u4eca\u5176\u4e66\u5750\u63a5\u5e94\u5173\u4fe1\u89c9\u6b65\u53cd\u5904\u8bb0\u5c06\u5343\u627e\u4e89\u9886\u6216\u5e08\u7ed3\u5757\u8dd1\u8c01\u8349\u8d8a\u5b57\u52a0\u811a\u7d27\u7231\u7b49\u4e60\u9635\u6015\u6708\u9752\u534a\u706b\u6cd5\u9898\u5efa\u8d76\u4f4d\u5531\u6d77\u4e03\u5973\u4efb\u4ef6\u611f\u51c6\u5f20\u56e2\u5c4b\u79bb\u8272\u8138\u7247\u79d1\u5012\u775b\u5229\u4e16\u521a\u4e14\u7531\u9001\u5207\u661f\u5bfc\u665a\u8868\u591f\u6574\u8ba4\u54cd\u96ea\u6d41\u672a\u573a\u8be5\u5e76\u5e95\u6df1\u523b\u5e73\u4f1f\u5fd9\u63d0\u786e\u8fd1\u4eae\u8f7b\u8bb2\u519c\u53e4\u9ed1\u544a\u754c\u62c9\u540d\u5440\u571f\u6e05\u9633\u7167\u529e\u53f2\u6539\u5386\u8f6c\u753b\u9020\u5634\u6b64\u6cbb\u5317\u5fc5\u670d\u96e8\u7a7f\u5185\u8bc6\u9a8c\u4f20\u4e1a\u83dc\u722c\u7761\u5174\u5f62\u91cf\u54b1\u89c2\u82e6\u4f53\u4f17\u901a\u51b2\u5408\u7834\u53cb\u5ea6\u672f\u996d\u516c\u65c1\u623f\u6781\u5357\u67aa\u8bfb\u6c99\u5c81\u7ebf\u91ce\u575a\u7a7a\u6536\u7b97\u81f3\u653f\u57ce\u52b3\u843d\u94b1\u7279\u56f4\u5f1f\u80dc\u6559\u70ed\u5c55\u5305\u6b4c\u7c7b\u6e10\u5f3a\u6570\u4e61\u547c\u6027\u97f3\u7b54\u54e5\u9645\u65e7\u795e\u5ea7\u7ae0\u5e2e\u5566\u53d7\u7cfb\u4ee4\u8df3\u975e\u4f55\u725b\u53d6\u5165\u5cb8\u6562\u6389\u5ffd\u79cd\u88c5\u9876\u6025\u6797\u505c\u606f\u53e5\u533a\u8863\u822c\u62a5\u53e6\u538b\u6162\u53d4\u80cc\u7ec6';

function toBase64Png(img) {
  return encodePNG(img.width, img.height, img.px).toString('base64');
}

function pick(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

/**
 * blockPuzzle get：随机底图 + 随机模板抠图，返回双图 + token。
 */
function getBlockPuzzle(store) {
  const bgSrc = pick(store.backgrounds);
  const tpl = pick(store.sliders);
  const bg = { width: bgSrc.width, height: bgSrc.height, px: bgSrc.px.slice() };
  const jw = tpl.width,
    jh = tpl.height;
  let x = 5;
  if (bg.width - jw > 0) {
    const bound = bg.width - jw - 200;
    if (bound > 0) x = randInt(200, 200 + bound);
  }
  // 标准底图 155 高 < 模板 310 高 → y 恒为 5（前端硬编码 y:5.0 的由来）
  const y = bg.height - jh <= 0 ? 5 : randInt(5, bg.height - jh + 5);
  const secretKey = randomString(16);
  const piece = cutByTemplate(bg, tpl, x, 0);
  const token = uuid();
  store.cache.set(CAPTCHA_KEY(token), JSON.stringify({ secretKey, x, y }), EXPIRES_IN);
  return ok({
    captchaType: 'blockPuzzle',
    originalImageBase64: toBase64Png(bg),
    jigsawImageBase64: toBase64Png(piece),
    token,
    secretKey,
  });
}

/**
 * blockPuzzle check：一次性 token → AES 解密坐标 → |Δx|≤5 且 y 严格相等 → 生成二次校验凭证。
 */
function checkBlockPuzzle(store, { token, pointJson }) {
  const key = CAPTCHA_KEY(token || '');
  const raw = store.cache.get(key);
  if (!raw) return err('6110', '验证码已失效，请重新获取');
  store.cache.delete(key); // 验证码只用一次，即刻失效
  let stored, userJson;
  try {
    stored = JSON.parse(raw);
  } catch (e) {
    return err('0001', '验证码坐标解析失败');
  }
  userJson = aesDecrypt(pointJson, stored.secretKey);
  if (userJson == null) return err('0001', '验证码坐标解析失败');
  let p;
  try {
    p = JSON.parse(userJson);
  } catch (e) {
    return err('0001', '验证码坐标解析失败');
  }
  const ux = Math.trunc(p.x),
    uy = Math.trunc(p.y); // 前端浮点坐标按 int 截断
  if (stored.x - SLIP_OFFSET > ux || ux > stored.x + SLIP_OFFSET || stored.y !== uy) {
    return err('6111', '验证失败');
  }
  const verification = aesEncrypt(token + '---' + userJson, stored.secretKey);
  if (verification == null) return err('0001', 'AES加密失败');
  store.cache.set(SECOND_KEY(verification), token, SECOND_EXPIRES_IN);
  return ok({ captchaType: 'blockPuzzle', token, result: true });
}

/**
 * clickWord get：随机底图 + 汉字池去重取 4 字（1 字干扰不校验），分列布点。
 */
function getClickWord(store) {
  const bgSrc = pick(store.clickBackgrounds);
  const bg = { width: bgSrc.width, height: bgSrc.height, px: bgSrc.px.slice() };
  const wordTotalCount = 4;
  const decoyIndex = randInt(1, wordTotalCount) - 1; // 干扰字下标，最后一个字永不干扰
  const secretKey = randomString(16);
  // 去重随机选字
  const words = [];
  while (words.length < wordTotalCount) {
    const w = HAN_ZI[Math.floor(Math.random() * HAN_ZI.length)];
    if (!words.includes(w)) words.push(w);
  }
  const wordList = [];
  const pointList = [];
  const wordPositions = []; // 演示专用：真实实现把文字烧进图片，不回传坐标
  for (let i = 0; i < wordTotalCount; i++) {
    const point = randomWordPoint(bg.width, bg.height, i, wordTotalCount);
    const pos = {
      word: words[i],
      x: point.x,
      y: point.y,
      rotate: randInt(-45, 46),
      color: [randInt(1, 256), randInt(1, 256), randInt(1, 256)],
    };
    wordPositions.push(pos);
    if (i !== decoyIndex) {
      wordList.push(words[i]);
      pointList.push({ secretKey, x: point.x, y: point.y });
    }
  }
  const token = uuid();
  store.cache.set(CAPTCHA_KEY(token), JSON.stringify(pointList), EXPIRES_IN);
  return ok({
    captchaType: 'clickWord',
    originalImageBase64: toBase64Png(bg),
    wordList,
    token,
    secretKey,
    wordPositions, // 演示专用字段
  });
}

// randomWordPoint：avgWidth 分列，内边距 HAN_ZI_SIZE_HALF
function randomWordPoint(w, h, wordSortIndex, wordCount) {
  const half = HAN_ZI_SIZE / 2;
  const avgWidth = Math.floor(w / (wordCount + 1));
  let x;
  if (avgWidth < half) {
    x = randInt(1 + half, w);
  } else if (wordSortIndex === 0) {
    x = randInt(1 + half, avgWidth * (wordSortIndex + 1) - half);
  } else {
    x = randInt(avgWidth * wordSortIndex + half, avgWidth * (wordSortIndex + 1) - half);
  }
  const y = randInt(HAN_ZI_SIZE, h - HAN_ZI_SIZE);
  return { x, y };
}

/**
 * clickWord check：一次性 token → 以首点 secretKey 解密 → 逐点 |Δ|≤字号 → 生成凭证。
 */
function checkClickWord(store, { token, pointJson }) {
  const key = CAPTCHA_KEY(token || '');
  const raw = store.cache.get(key);
  if (!raw) return err('6110', '验证码已失效，请重新获取');
  store.cache.delete(key);
  let expected;
  try {
    expected = JSON.parse(raw);
  } catch (e) {
    return err('0001', '验证码坐标解析失败');
  }
  if (!Array.isArray(expected) || expected.length === 0) return err('0001', '验证码坐标解析失败');
  const userJson = aesDecrypt(pointJson, expected[0].secretKey);
  if (userJson == null) return err('0001', '验证码坐标解析失败');
  let clicked;
  try {
    clicked = JSON.parse(userJson);
  } catch (e) {
    return err('0001', '验证码坐标解析失败');
  }
  if (!Array.isArray(clicked) || clicked.length < expected.length) {
    return err('0001', '验证码坐标解析失败');
  }
  for (let i = 0; i < expected.length; i++) {
    const ex = expected[i].x,
      ey = expected[i].y;
    const qx = Math.trunc(clicked[i].x),
      qy = Math.trunc(clicked[i].y);
    if (ex - HAN_ZI_SIZE > qx || qx > ex + HAN_ZI_SIZE || ey - HAN_ZI_SIZE > qy || qy > ey + HAN_ZI_SIZE) {
      return err('6111', '验证失败');
    }
  }
  const verification = aesEncrypt(token + '---' + userJson, expected[0].secretKey);
  if (verification == null) return err('0001', 'AES加密失败');
  store.cache.set(SECOND_KEY(verification), token, SECOND_EXPIRES_IN);
  return ok({ captchaType: 'clickWord', token, result: true });
}

/**
 * verification：二次校验（业务后端），凭证取出后即刻失效（防重放）。
 */
function verify(store, captchaVerification) {
  if (!captchaVerification) return err('0011', 'captchaVerification不能为空');
  const key = SECOND_KEY(captchaVerification);
  if (!store.cache.get(key)) return err('6110', '验证码已失效，请重新获取');
  store.cache.delete(key);
  return ok(null);
}

module.exports = {
  TTLCache,
  getBlockPuzzle,
  checkBlockPuzzle,
  getClickWord,
  checkClickWord,
  verify,
};
