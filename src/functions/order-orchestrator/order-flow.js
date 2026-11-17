/**
 * 订单编排模块 —— 对应状态机语义（容量→制作→完成）。
 * 订单与用户状态存放于 DCS Redis（KV/hash 承载表语义）。
 */
const Redis = require("ioredis");

function redis() {
  return new Redis(Number(process.env.REDIS_PORT || 6379), process.env.REDIS_HOST, {
    password: process.env.REDIS_PASSWORD,
    lazyConnect: false,
  });
}

const STATUS = { NEW: "NEW", CAPACITY: "CAPACITY_OK", PREPARING: "PREPARING", READY: "READY", COMPLETED: "COMPLETED" };

async function checkCapacity(cafe) {
  const r = redis();
  try {
    const key = `capacity:${cafe}`;
    const cur = Number((await r.get(key)) || 0);
    return cur < 5;
  } finally { r.disconnect(); }
}

async function markPreparing(orderId, step) {
  const r = redis();
  try {
    const key = `order:${orderId}`;
    const order = JSON.parse((await r.get(key)) || "{}");
    order.status = STATUS.PREPARING; order.step = step || "0";
    await r.set(key, JSON.stringify(order));
  } finally { r.disconnect(); }
}

async function complete(orderId) {
  const r = redis();
  try {
    const key = `order:${orderId}`;
    const order = JSON.parse((await r.get(key)) || "{}");
    order.status = STATUS.COMPLETED; order.completedAt = new Date().toISOString();
    await r.set(key, JSON.stringify(order));
  } finally { r.disconnect(); }
}

module.exports = { redis, STATUS, checkCapacity, markPreparing, complete };
