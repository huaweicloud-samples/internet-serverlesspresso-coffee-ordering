#!/usr/bin/env node
/**
 * 打包函数代码目录为 zip —— 纯 Node 实现（不依赖系统 zip / 7z 命令）。
 *
 * 用法： node src/scripts/zip.js <源目录> <目标 zip>
 *   例： node src/scripts/zip.js build/.stage/auth-register build/auth-register.zip
 */
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const [, , srcDir, outFile] = process.argv;
if (!srcDir || !outFile) {
  console.error("用法: node zip.js <源目录> <目标 zip>");
  process.exit(1);
}

/** 递归收集目录下所有文件（返回相对路径，按字典序保证可复现） */
function walk(dir, base = dir, acc = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, base, acc);
    else if (entry.isFile()) acc.push(path.relative(base, full).split(path.sep).join("/"));
  }
  return acc;
}

/** CRC-32 */
const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();

function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

const files = walk(srcDir);
if (files.length === 0) {
  console.error(`源目录为空: ${srcDir}`);
  process.exit(1);
}

const locals = [];
const centrals = [];
let offset = 0;

for (const name of files) {
  const data = fs.readFileSync(path.join(srcDir, name));
  const deflated = zlib.deflateRawSync(data, { level: 9 });
  const crc = crc32(data);
  const nameBuf = Buffer.from(name, "utf8");

  // local file header
  const lfh = Buffer.alloc(30);
  lfh.writeUInt32LE(0x04034b50, 0);
  lfh.writeUInt16LE(20, 4); // version needed
  lfh.writeUInt16LE(0x0800, 6); // flags: UTF-8 名称
  lfh.writeUInt16LE(8, 8); // method: deflate
  lfh.writeUInt16LE(0, 10); // mod time
  lfh.writeUInt16LE(0x21, 12); // mod date (1980-01-01)
  lfh.writeUInt32LE(crc, 14);
  lfh.writeUInt32LE(deflated.length, 18);
  lfh.writeUInt32LE(data.length, 22);
  lfh.writeUInt16LE(nameBuf.length, 26);
  lfh.writeUInt16LE(0, 28);
  locals.push(lfh, nameBuf, deflated);

  // central directory entry
  const cdh = Buffer.alloc(46);
  cdh.writeUInt32LE(0x02014b50, 0);
  cdh.writeUInt16LE(20, 4); // version made by
  cdh.writeUInt16LE(20, 6); // version needed
  cdh.writeUInt16LE(0x0800, 8);
  cdh.writeUInt16LE(8, 10);
  cdh.writeUInt16LE(0, 12);
  cdh.writeUInt16LE(0x21, 14);
  cdh.writeUInt32LE(crc, 16);
  cdh.writeUInt32LE(deflated.length, 20);
  cdh.writeUInt32LE(data.length, 24);
  cdh.writeUInt16LE(nameBuf.length, 28);
  cdh.writeUInt16LE(0, 30); // extra len
  cdh.writeUInt16LE(0, 32); // comment len
  cdh.writeUInt16LE(0, 34); // disk number
  cdh.writeUInt16LE(0, 36); // internal attrs
  cdh.writeUInt32LE((0o100644 << 16) >>> 0, 38); // external attrs（Unix 权限位，需转无符号 32 位）
  cdh.writeUInt32LE(offset, 42);
  centrals.push(cdh, nameBuf);

  offset += lfh.length + nameBuf.length + deflated.length;
}

const centralBuf = Buffer.concat(centrals);
const eocd = Buffer.alloc(22);
eocd.writeUInt32LE(0x06054b50, 0);
eocd.writeUInt16LE(0, 4);
eocd.writeUInt16LE(0, 6);
eocd.writeUInt16LE(files.length, 8);
eocd.writeUInt16LE(files.length, 10);
eocd.writeUInt32LE(centralBuf.length, 12);
eocd.writeUInt32LE(offset, 16);
eocd.writeUInt16LE(0, 20);

fs.mkdirSync(path.dirname(outFile), { recursive: true });
fs.writeFileSync(outFile, Buffer.concat([...locals, centralBuf, eocd]));
console.log(`  ${path.basename(outFile)}: ${files.length} 个文件, ${(fs.statSync(outFile).size / 1024 / 1024).toFixed(2)} MB`);
