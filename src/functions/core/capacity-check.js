/** 容量检查（编排模块 checkCapacity，Redis counter 上限 5） */
const { redis, checkCapacity } = require("./order-orchestrator/order-flow");

exports.handler = async (event, context) => {
  const body = (event.body ? (typeof event.body === "string" ? JSON.parse(event.body) : event.body) : event) || {};
  const cafe = body.cafe || "main";
  const available = await checkCapacity(cafe);
  return { statusCode: 200, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ cafe, capacityAvailable: available }) };
};
