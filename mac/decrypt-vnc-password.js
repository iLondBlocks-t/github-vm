#!/usr/bin/env node
'use strict';

const crypto = require('crypto');

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

const token = process.env.NGROK_AUTH_TOKEN;
const envelope = process.env.VNC_PASSWORD_ENVELOPE;
if (!token || !envelope || !envelope.startsWith('v1:')) {
  fail('Missing Ngrok token or unsupported encrypted payload.');
}

try {
  const packed = Buffer.from(envelope.slice(3), 'base64url');
  if (packed.length < 16 + 12 + 16 + 1) fail('Encrypted payload is incomplete.');
  const salt = packed.subarray(0, 16);
  const nonce = packed.subarray(16, 28);
  const tag = packed.subarray(28, 44);
  const ciphertext = packed.subarray(44);
  const info = Buffer.from('github-vm/MacRDP/VNC-password/v1');
  const aad = Buffer.from('github-vm:MacRDP:v1');
  const key = Buffer.from(crypto.hkdfSync('sha256', Buffer.from(token), salt, info, 32));
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, nonce);
  decipher.setAAD(aad);
  decipher.setAuthTag(tag);
  const password = Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf8');
  if (password.length !== 8) fail('Decrypted value did not match the expected VNC password length.');
  process.stdout.write(`VNC password (keep private): ${password}\n`);
} catch {
  fail('Could not decrypt the payload. Check that the Ngrok token and complete payload are correct.');
}
