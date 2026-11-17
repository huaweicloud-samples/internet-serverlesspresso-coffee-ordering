/** 订单完成：PREPARING → COMPLETED（编排模块） */
const { markPreparing, complete } = require("./order-orchestrator/order-flow");

exports.handler = async (event, context) => {
  const body = (event.body ? (typeof event.body === "string" ? JSON.parse(event.body) : event.body) : event) || {};
  const orderId = body.orderId || (event.pathParameters && event.pathParameters.id);
  if (!orderId) return { statusCode: 400, body: JSON.stringify({ error: "orderId required" }) };
  await markPreparing(orderId, "complete");
  await complete(orderId);
  console.log(`[event] order.completed ${orderId}`);
  return { statusCode: 200, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ orderId, status: "COMPLETED" }) };
};
