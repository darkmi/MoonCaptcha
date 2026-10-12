'use strict';
/**
 * 浏览器端 AES-128 / ECB / PKCS7 加密（仅加密，演示协议所需）。
 * 从 src/crypto/aes.mbt（已通过 FIPS-197 与 Node.js crypto 对拍验证）移植。
 * WebCrypto 不支持 ECB，故自带实现；S 盒同样程序化生成。
 */
(function (global) {
  const gmul = (a, b) => {
    let p = 0;
    for (let i = 0; i < 8; i++) {
      if (b & 1) p ^= a;
      const hi = a & 0x80;
      a = (a << 1) & 0xff;
      if (hi) a ^= 0x1b;
      b >>= 1;
    }
    return p;
  };
  const rotl8 = (b, n) => ((b << n) | (b >> (8 - n))) & 0xff;

  const SBOX = (() => {
    const inv = new Uint8Array(256);
    for (let i = 1; i < 256; i++)
      for (let j = 1; j < 256; j++)
        if (gmul(i, j) === 1) {
          inv[i] = j;
          break;
        }
    const s = new Uint8Array(256);
    for (let i = 0; i < 256; i++) {
      const b = inv[i];
      s[i] = b ^ rotl8(b, 1) ^ rotl8(b, 2) ^ rotl8(b, 3) ^ rotl8(b, 4) ^ 0x63;
    }
    return s;
  })();

  const xtime = (b) => {
    const hi = b & 0x80;
    const d = (b << 1) & 0xff;
    return hi ? d ^ 0x1b : d;
  };
  const subWord = (w) =>
    ((SBOX[(w >>> 24) & 0xff] << 24) | (SBOX[(w >>> 16) & 0xff] << 16) | (SBOX[(w >>> 8) & 0xff] << 8) | SBOX[w & 0xff]) >>> 0;
  const rotWord = (w) => (((w << 8) & 0xffffffff) | ((w >>> 24) & 0xff)) >>> 0;

  // 16 字节密钥 → 44 个 32 位轮密钥字
  function expandKey(key) {
    const w = new Uint32Array(44);
    for (let i = 0; i < 4; i++)
      w[i] = ((key[4 * i] << 24) | (key[4 * i + 1] << 16) | (key[4 * i + 2] << 8) | key[4 * i + 3]) >>> 0;
    let rc = 1;
    for (let round = 1; round < 11; round++) {
      const rcon = rc << 24;
      rc = xtime(rc);
      const i = round * 4;
      const temp = (subWord(rotWord(w[i - 1])) ^ rcon) >>> 0;
      w[i] = (w[i - 4] ^ temp) >>> 0;
      for (let k = 1; k < 4; k++) w[i + k] = (w[i + k - 4] ^ w[i + k - 1]) >>> 0;
    }
    return w;
  }

  function addRoundKey(state, w, round) {
    for (let c = 0; c < 4; c++) {
      const word = w[round * 4 + c];
      state[4 * c] ^= (word >>> 24) & 0xff;
      state[4 * c + 1] ^= (word >>> 16) & 0xff;
      state[4 * c + 2] ^= (word >>> 8) & 0xff;
      state[4 * c + 3] ^= word & 0xff;
    }
  }

  function subBytes(state) {
    for (let i = 0; i < 16; i++) state[i] = SBOX[state[i]];
  }

  function shiftRows(state) {
    for (let r = 1; r < 4; r++) {
      const row = [state[4 * 0 + r], state[4 * 1 + r], state[4 * 2 + r], state[4 * 3 + r]];
      for (let c = 0; c < 4; c++) state[4 * c + r] = row[(c + r) % 4];
    }
  }

  function mixColumns(state) {
    for (let c = 0; c < 4; c++) {
      const i = 4 * c;
      const s0 = state[i],
        s1 = state[i + 1],
        s2 = state[i + 2],
        s3 = state[i + 3];
      state[i] = gmul(s0, 2) ^ gmul(s1, 3) ^ s2 ^ s3;
      state[i + 1] = s0 ^ gmul(s1, 2) ^ gmul(s2, 3) ^ s3;
      state[i + 2] = s0 ^ s1 ^ gmul(s2, 2) ^ gmul(s3, 3);
      state[i + 3] = gmul(s0, 3) ^ s1 ^ s2 ^ gmul(s3, 2);
    }
  }

  function encryptBlock(block, w) {
    addRoundKey(block, w, 0);
    for (let round = 1; round < 10; round++) {
      subBytes(block);
      shiftRows(block);
      mixColumns(block);
      addRoundKey(block, w, round);
    }
    subBytes(block);
    shiftRows(block);
    addRoundKey(block, w, 10);
  }

  function pkcs7Pad(bytes) {
    const pad = 16 - (bytes.length % 16);
    const out = new Uint8Array(bytes.length + pad).fill(pad);
    out.set(bytes);
    return out;
  }

  /**
   * AES-128-ECB-PKCS7 加密，返回标准 Base64。空密钥时明文直通（对齐 AESUtil）。
   */
  function aesEncrypt(text, key) {
    if (!key) return text;
    const keyBytes = Array.from(new TextEncoder().encode(key));
    if (keyBytes.length !== 16) throw new Error('key must be 16 bytes');
    const w = expandKey(new Uint8Array(keyBytes));
    const data = pkcs7Pad(new TextEncoder().encode(text));
    const out = new Uint8Array(data.length);
    for (let off = 0; off < data.length; off += 16) {
      const block = new Uint8Array(16);
      for (let i = 0; i < 16; i++) block[i] = data[off + i];
      encryptBlock(block, w);
      out.set(block, off);
    }
    let bin = '';
    for (let i = 0; i < out.length; i++) bin += String.fromCharCode(out[i]);
    return btoa(bin);
  }

  global.moonAES = { aesEncrypt };
})(window);
