import { CheckoutService, CheckoutRequest } from "@app/checkout";
import { InMemoryOrderRepository } from "@domain/orders/repository";
import { Logger } from "shared/logger";

const logger = new Logger("app.server");

/** Wire the object graph and expose a single request handler. */
export function createHandler(): (body: CheckoutRequest) => Promise<Response> {
  const checkout = new CheckoutService(new InMemoryOrderRepository());
  return async (body: CheckoutRequest) => {
    const totalMinorUnits = await checkout.place(body);
    logger.info("checkout handled", { order: body.orderId });
    return new Response(JSON.stringify({ totalMinorUnits }), {
      headers: { "content-type": "application/json" },
    });
  };
}
