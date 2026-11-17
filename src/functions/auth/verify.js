/** 验证码校验（演示固定码 123456） */
const Redis = require("ioredis");
const { redis } = require("./order-orchestrator/order-flow");

exports.handler = async (event, context) => {
  const body = (event.body ? (typeof event.body === "string" ? JSON.parse(event.body) : event.body) : event) || {};
  const { username, code } = body;
  if (!username || String(code) !== "123456")
    return { statusCode: 400, body: JSON.stringify({ error: "invalid code" }) };
  const r = redis();
  try {
    await r.hset(`user:${username}`, { status: "VERIFIED" });
    return { statusCode: 200, body: JSON.stringify({ username, status: "VERIFIED" }) };
  } finally { r.disconnect(); }
};
