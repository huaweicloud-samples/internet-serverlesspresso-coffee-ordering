/** 注册：写入 Redis user hash + 生成验证码（演示固定码 123456，接入 MSGSMS 可短信下发） */
const Redis = require("ioredis");
const crypto = require("crypto");
const { redis } = require("./order-orchestrator/order-flow");

exports.handler = async (event, context) => {
  const body = (event.body ? (typeof event.body === "string" ? JSON.parse(event.body) : event.body) : event) || {};
  const { username, password } = body;
  if (!username || !password || password.length < 8)
    return { statusCode: 400, body: JSON.stringify({ error: "username and password(>=8) required" }) };
  const r = redis();
  try {
    const salt = crypto.randomBytes(16).toString("hex");
    const hash = crypto.scryptSync(password, salt, 32).toString("hex");
    await r.hset(`user:${username}`, { salt, password: hash, status: "UNVERIFIED" });
    console.log(`[sms] 验证码 123456 发送至 ${username}（演示模式）`);
    return { statusCode: 201, body: JSON.stringify({ username, status: "UNVERIFIED", notice: "验证码已发送（演示模式见函数日志）" }) };
  } finally { r.disconnect(); }
};
