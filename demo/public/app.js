'use strict';
/**
 * MoonCaptcha 登录演示页逻辑。
 * 流程对齐 AJ-Captcha 前端组件：
 *   get → 用户交互 → check（AES 加密 pointJson）→ 本地构造 captchaVerification
 *   → 提交登录 → 服务端 verify 二次校验（一次性，防重放）
 */
(function () {
  const $ = (sel) => document.querySelector(sel);
  const IMG_W = 310,
    IMG_H = 155;

  const state = {
    mode: 'blockPuzzle',
    captcha: null, // get 响应的 repData
    clicks: [], // clickWord 已点坐标
    captchaVerification: null,
    verified: false,
  };

  // ---------- 协议日志 ----------

  function log(api, req, resp, note) {
    const box = $('#proto-log');
    const empty = box.querySelector('.log-empty');
    if (empty) empty.remove();
    const item = document.createElement('div');
    item.className = 'log-item';
    const time = new Date().toLocaleTimeString('zh-CN', { hour12: false });
    const summary = (o) => {
      if (o == null) return 'null';
      const s = JSON.stringify(o);
      return s.length > 120 ? s.slice(0, 120) + '…' : s;
    };
    item.innerHTML =
      `<div class="log-time">${time} · ${api}${note ? ' · ' + note : ''}</div>` +
      `<div class="log-line">→ ${summary(req)}</div>` +
      `<div class="log-line ${resp && resp.repCode === '0000' ? 'log-ok' : 'log-err'}">← ${summary(resp)}</div>`;
    box.prepend(item);
  }

  async function api(path, body) {
    const resp = await fetch(path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    return resp.json();
  }

  // ---------- 验证码获取与渲染 ----------

  async function refresh() {
    state.captcha = null;
    state.clicks = [];
    state.captchaVerification = null;
    state.verified = false;
    updateLoginState();
    const resp = await api('/captcha/get', { captchaType: state.mode });
    log(`/captcha/get`, { captchaType: state.mode }, resp);
    if (resp.repCode !== '0000') {
      $('#captcha-panel').innerHTML = `<div class="cap-fail">获取验证码失败：${resp.repMsg}</div>`;
      return;
    }
    state.captcha = resp.repData;
    if (state.mode === 'blockPuzzle') renderBlockPuzzle();
    else renderClickWord();
  }

  // ---------- 滑动拼图 ----------

  function renderBlockPuzzle() {
    const c = state.captcha;
    $('#captcha-panel').innerHTML = `
      <div class="cap-status" id="cap-status">请拖动滑块完成拼图</div>
      <div class="cap-canvas" id="cap-canvas" style="width:${IMG_W}px;height:${IMG_H}px">
        <img class="cap-bg" src="data:image/png;base64,${c.originalImageBase64}" draggable="false"/>
        <img class="cap-piece" id="cap-piece" src="data:image/png;base64,${c.jigsawImageBase64}" draggable="false"/>
        <div class="cap-mask" id="cap-mask"></div>
      </div>
      <div class="cap-track" id="cap-track">
        <div class="cap-handle" id="cap-handle"><span>&#10148;</span></div>
        <div class="cap-track-hint" id="cap-hint">按住滑块，拖动完成上方拼图</div>
      </div>`;
    bindDrag();
  }

  function bindDrag() {
    const canvas = $('#cap-canvas');
    const piece = $('#cap-piece');
    const track = $('#cap-track');
    const handle = $('#cap-handle');
    const hint = $('#cap-hint');
    const status = $('#cap-status');
    const maxDx = IMG_W - piece.width || IMG_W - 94;
    let dragging = false,
      startX = 0,
      dx = 0;

    handle.addEventListener('pointerdown', (e) => {
      if (state.verified) return;
      dragging = true;
      startX = e.clientX - dx;
      handle.setPointerCapture(e.pointerId);
      hint.textContent = '';
    });
    handle.addEventListener('pointermove', (e) => {
      if (!dragging) return;
      dx = Math.max(0, Math.min(maxDx, e.clientX - startX));
      piece.style.left = dx + 'px';
      handle.style.left = dx + 'px';
    });
    handle.addEventListener('pointerup', async () => {
      if (!dragging) return;
      dragging = false;
      const raw = JSON.stringify({ x: dx, y: 5.0 });
      const pointJson = moonAES.aesEncrypt(raw, state.captcha.secretKey);
      const resp = await api('/captcha/check', {
        captchaType: 'blockPuzzle',
        token: state.captcha.token,
        pointJson,
      });
      log('/captcha/check', { captchaType: 'blockPuzzle', token: short(state.captcha.token), pointJson: '…' }, resp, `x=${dx}`);
      handleCheckResult(resp, raw, status, canvas);
    });
  }

  // ---------- 文字点选 ----------

  function renderClickWord() {
    const c = state.captcha;
    const words = c.wordList.map((w) => `【${w}】`).join('');
    $('#captcha-panel').innerHTML = `
      <div class="cap-status" id="cap-status">请按顺序点击：<b>${words}</b></div>
      <div class="cap-canvas" id="cap-canvas" style="width:${IMG_W}px;height:${IMG_H}px">
        <img class="cap-bg" src="data:image/png;base64,${c.originalImageBase64}" draggable="false"/>
        ${c.wordPositions
          .map(
            (p) => `<span class="cap-word" style="left:${p.x}px;top:${p.y}px;transform:translate(-50%,-50%) rotate(${p.rotate}deg);color:rgb(${p.color.join(',')})">${p.word}</span>`,
          )
          .join('')}
        <div class="cap-mask" id="cap-mask"></div>
        <div id="cap-markers"></div>
      </div>`;
    const canvas = $('#cap-canvas');
    canvas.addEventListener('pointerdown', onClickWordClick);
  }

  async function onClickWordClick(e) {
    if (state.verified) return;
    const canvas = $('#cap-canvas');
    const rect = canvas.getBoundingClientRect();
    const x = Math.round(e.clientX - rect.left);
    const y = Math.round(e.clientY - rect.top);
    if (x < 0 || y < 0 || x > IMG_W || y > IMG_H) return;
    state.clicks.push({ x, y });
    const marker = document.createElement('div');
    marker.className = 'cap-marker';
    marker.style.left = x + 'px';
    marker.style.top = y + 'px';
    marker.textContent = state.clicks.length;
    $('#cap-markers').appendChild(marker);
    const need = state.captcha.wordList.length;
    if (state.clicks.length < need) return;
    canvas.removeEventListener('pointerdown', onClickWordClick);
    const raw = JSON.stringify(state.clicks);
    const pointJson = moonAES.aesEncrypt(raw, state.captcha.secretKey);
    const status = $('#cap-status');
    const resp = await api('/captcha/check', {
      captchaType: 'clickWord',
      token: state.captcha.token,
      pointJson,
    });
    log('/captcha/check', { captchaType: 'clickWord', token: short(state.captcha.token), pointJson: '…' }, resp, `${state.clicks.length} 个点击`);
    handleCheckResult(resp, raw, status, canvas);
  }

  // ---------- check 结果与登录 ----------

  function handleCheckResult(resp, rawPointJson, status, canvas) {
    if (resp.repCode === '0000') {
      state.verified = true;
      // 对齐 AJ-Captcha：captchaVerification 由前端本地构造 AES(token---pointJson)
      state.captchaVerification = moonAES.aesEncrypt(
        state.captcha.token + '---' + rawPointJson,
        state.captcha.secretKey,
      );
      status.textContent = '✓ 验证成功';
      status.classList.add('ok');
      canvas.classList.add('cap-success');
      $('#cap-mask').style.display = 'block';
      updateLoginState();
    } else {
      status.textContent = `✗ ${resp.repMsg}`;
      status.classList.add('bad');
      canvas.classList.add('cap-fail');
      setTimeout(refresh, 700);
    }
  }

  function updateLoginState() {
    const btn = $('#btn-login');
    const tip = $('#captcha-tip');
    btn.disabled = !state.verified;
    tip.textContent = state.verified ? '验证码校验通过，可以登录' : '请先完成验证码';
  }

  $('#btn-refresh').addEventListener('click', refresh);
  document.querySelectorAll('.mode-tab').forEach((tab) => {
    tab.addEventListener('click', () => {
      if (tab.dataset.mode === state.mode) return;
      document.querySelectorAll('.mode-tab').forEach((t) => t.classList.toggle('active', t === tab));
      state.mode = tab.dataset.mode;
      refresh();
    });
  });

  $('#btn-login').addEventListener('click', async () => {
    const username = $('#username').value.trim();
    const password = $('#password').value;
    const msg = $('#login-msg');
    if (!username || !password) {
      msg.textContent = '请输入用户名和密码';
      msg.className = 'msg bad';
      return;
    }
    const resp = await api('/login', {
      username,
      password,
      captchaVerification: state.captchaVerification,
    });
    log('/login', { username, password: '***', captchaVerification: '…' }, { repCode: resp.ok ? '0000' : '0001', repMsg: resp.message });
    if (resp.ok) {
      $('#login-card').classList.add('hidden');
      const done = $('#done-card');
      done.classList.remove('hidden');
      $('#done-text').textContent = resp.message;
    } else {
      msg.textContent = resp.message;
      msg.className = 'msg bad';
      refresh();
    }
  });

  $('#btn-again').addEventListener('click', () => {
    $('#done-card').classList.add('hidden');
    $('#login-card').classList.remove('hidden');
    $('#login-msg').textContent = '';
    refresh();
  });

  function short(s) {
    return s ? s.slice(0, 8) + '…' : s;
  }

  refresh();
})();
