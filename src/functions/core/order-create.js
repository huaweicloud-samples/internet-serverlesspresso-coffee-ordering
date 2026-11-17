/** 点单：校验 JWT → 写入 Redis order:{orderId} → 触发事件（EG/SMN 可按需接入） */
const Redis = require("ioredis");
const jwt = require("jsonwebtoken");
const { redis } = require("./order-orchestrator/order-flow");

function auth(event) {
  const body = (event.body ? (typeof event.body === "string" ? JSON.parse(event.body) : event.body) : event) || {};
  const h = body.headers || event.headers || {};
  const token = (h.Authorization || "").replace(/^Bearer /, "");
  try { return jwt.verify(token, process.env.AUTH_JWT_SECRET).username; } catch { return null; }
}

exports.handler = async (event, context) => {
  const username = auth(event);
  if (!username) return { statusCode: 401, body: JSON.stringify({ error: "unauthorized" }) };
  const body = (event.body ? (typeof event.body === "string" ? JSON.parse(event.body) : event.body) : event) || {};
  const { items = [], cafe = "main" } = body;
  const orderId = `ORD-${Date.now()}-${Math.random().toString(36).slice(2, 6).toUpperCase()}`;
  const now = new Date().toISOString();

  const r = redis();
  try {
    await r.set(`order:${orderId}`, JSON.stringify({ orderId, username, cafe, items, status: "NEW", createdAt: now }));
    console.log(`[event] order.created ${orderId}`);
    return { statusCode: 201, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ orderId, status: "NEW", createdAt: now }) };
  } finally { r.disconnect(); }
};
