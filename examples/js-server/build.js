'use strict';
/**
 * 构建脚本：把 MoonCaptcha 核心（moon build --target js 产物）包装为
 * CommonJS 模块。
 *
 * 原理：moonc 生成的 JS 里函数名是确定性的 mangling
 * （`_M0` 前缀 + 包路径 + 标识符，下划线翻倍），对入参/返回值均为
 * String 的薄派发函数（js_captcha_get 等）做源码级名字提取，
 * 拼接 module.exports 后写为 moonbit_lib.cjs。
 */
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.join(__dirname, '..', '..');
const OUT_DIR = path.join(__dirname, 'build');

function findGeneratedJs(startDir) {
  let dir = startDir;
  for (let i = 0; i < 8; i++) {
    for (const kind of ['release', 'debug']) {
      const candidate = path.join(dir, '_build', 'js', kind, 'build');
      if (fs.existsSync(candidate)) return candidate;
    }
    dir = path.dirname(dir);
  }
  throw new Error('moon build output not found (run: moon build --target js)');
}

function extractFnName(source, fnName) {
  // mangling 会把 `js_captcha_get` 变为 `js_captcha__get`（下划线翻倍），
  // 且可能带包前缀；用宽松正则按子串定位唯一的顶层函数定义
  const mangled = fnName.replace(/_/g, '__');
  const re = new RegExp('function (_M0[A-Za-z0-9_]*' + mangled + ')\\(');
  const m = source.match(re);
  if (!m) throw new Error('cannot locate function ' + fnName);
  return m[1];
}

function main() {
  execSync('moon build --target js', { cwd: ROOT, stdio: 'inherit' });
  const buildRoot = findGeneratedJs(ROOT);
  const candidates = [];
  (function walk(d) {
    for (const f of fs.readdirSync(d)) {
      const full = path.join(d, f);
      if (fs.statSync(full).isDirectory()) walk(full);
      else if (f.endsWith('.js')) candidates.push(full);
    }
  })(buildRoot);
  const source = candidates
    .map((f) => fs.readFileSync(f, 'utf8'))
    .join('\n');
  const fns = ['js_captcha_init', 'js_captcha_get', 'js_captcha_check', 'js_captcha_verify'];
  const exportsJs = fns.map((f) => `  ${f}: ${extractFnName(source, f)},`).join('\n');
  const lib = source + '\n\nmodule.exports = {\n' + exportsJs + '\n};\n';
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const outFile = path.join(OUT_DIR, 'moonbit_lib.cjs');
  fs.writeFileSync(outFile, lib);
  console.log('written', outFile);
}

main();
