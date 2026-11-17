/** 登录：Redis user:{username} hash 校验 + JWT 签发（会话状态存放于 DCS Redis） */
const Redis = require("ioredis");
const jwt = require("jsonwebtoken");
const crypto = require("crypto");

const { redis } = require("./order-orchestrator/order-flow");
function scryptHash(p, s) { return crypto.scryptSync(p, s, 32).toString("hex"); }

exports.handler = async (event, context) => {
  const body = (event.body ? (typeof event.body === "string" ? JSON.parse(event.body) : event.body) : event) || {};
  const { username, password } = body;
  if (!username || !password) return { statusCode: 400, body: JSON.stringify({ error: "username and password required" }) };

  const r = redis();
  try {
    const user = await r.hgetall(`user:${username}`);
    if (!user.password) return { statusCode: 401, body: JSON.stringify({ error: "user not found" }) };
    if (scryptHash(password, user.salt) !== user.password)
      return { statusCode: 401, body: JSON.stringify({ error: "invalid credentials" }) };
    const token = jwt.sign({ username, scope: "customer" }, process.env.AUTH_JWT_SECRET, { expiresIn: "8h", algorithm: "HS256" });
    return { statusCode: 200, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ token, expiresIn: 8 * 3600 }) };
  } finally { r.disconnect(); }
};
