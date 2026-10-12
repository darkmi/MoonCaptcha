'use strict';
/**
 * 资源嵌入转换工具：将 PNG 目录转换为 MoonBit 源文件，供构建期嵌入默认底图。
 *
 * 用法：
 *   node tools/gen-assets.js <assets-dir> <output.mbt> <package-alias>
 *
 * 目录结构（对齐 AJ-Captcha 资源布局）：
 *   <assets-dir>/original/*.png      滑动拼图底图（推荐 310×155 RGB）
 *   <assets-dir>/slidingBlock/*.png  滑块模板（推荐 94×310 RGBA）
 *   <assets-dir>/pic-click/*.png     点选文字底图（推荐 310×155 RGB）
 *
 * 生成内容：三个函数 original_assets() / slider_assets() / click_assets()，
 * 返回 Array[(String, FixedArray[Int])]（文件名 → PNG 字节），配合
 * ImagePool::add_original_png 注册。
 *
 * 许可提示：若嵌入 AJ-Captcha（Apache-2.0）的底图，请保留其许可声明
 * （见 docs/migration-design.md §8.5）。
 */
const fs = require('fs');
const path = require('path');

function readDirPng(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((f) => f.toLowerCase().endsWith('.png'))
    .sort()
    .map((f) => ({ name: f, bytes: fs.readFileSync(path.join(dir, f)) }));
}

function mbtArray(bytes) {
  const parts = [];
  for (const b of bytes) parts.push(String(b));
  const lines = [];
  for (let i = 0; i < parts.length; i += 20) lines.push('      ' + parts.slice(i, i + 20) + ',');
  return '[\n' + lines.join('\n') + '\n    ]';
}

function emitFn(out, fnName, entries) {
  out.push(`///|\n/// ${fnName}：${entries.length} 张图（构建期生成，勿手工编辑）\n`);
  out.push(`pub fn ${fnName}() -> Array[(String, FixedArray[Int])] {\n  [`);
  for (const e of entries) {
    out.push(`    ("${e.name}", @common.fixed_from_array(${mbtArray(e.bytes)})),`);
  }
  out.push('  ]\n}\n');
}

// 目录别名：AJ-Captcha 布局（original/slidingBlock/pic-click）与本仓库 demo 布局（backgrounds/sliders/click）均可
function firstExisting(base, names) {
  for (const n of names) {
    const d = path.join(base, n);
    if (fs.existsSync(d)) return d;
  }
  return null;
}

function main() {
  const [dir, outputFile] = process.argv.slice(2);
  if (!dir || !outputFile) {
    console.error('usage: node tools/gen-assets.js <assets-dir> <output.mbt>');
    process.exit(1);
  }
  const originals = readDirPng(firstExisting(dir, ['original', 'backgrounds']) || '');
  const sliders = readDirPng(firstExisting(dir, ['slidingBlock', 'sliders']) || '');
  const clicks = readDirPng(firstExisting(dir, ['pic-click', 'click']) || '');
  const out = [
    '///|',
    '/// 默认底图资源（由 tools/gen-assets.js 生成，勿手工编辑）。',
    '/// 注册方式：',
    '///   let pool = @image.ImagePool::new()',
    '///   for (name, bytes) in original_assets() { let _ = name; let _ = pool.add_original_png(bytes) }',
    '///',
    '',
  ];
  emitFn(out, 'original_assets', originals);
  emitFn(out, 'slider_assets', sliders);
  emitFn(out, 'click_assets', clicks);
  fs.writeFileSync(outputFile, out.join('\n'));
  console.log(
    `written ${outputFile}: originals=${originals.length} sliders=${sliders.length} clicks=${clicks.length}`,
  );
}

main();
