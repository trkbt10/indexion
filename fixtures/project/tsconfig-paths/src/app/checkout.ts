import { Order, OrderStatus, OrderLine } from "@domain/orders/model";
import { OrderRepository } from "@domain/orders/repository";
import { fromMajor } from "shared/money";
import { Logger } from "shared/logger";

/** Everything the checkout needs to turn a cart into a placed order. */
export interface CheckoutRequest {
  orderId: string;
  items: Array<{ sku: string; quantity: number; price: number }>;
}

/**
 * Application service that places an order.
 *
 * It owns the transition from Draft to Placed; the aggregate owns the
 * rules about what a Draft order may contain.
 */
export class CheckoutService {
  private readonly logger = new Logger("app.checkout");

  constructor(private readonly orders: OrderRepository) {}

  /** Place the requested order and return its total in minor units. */
  async place(request: CheckoutRequest): Promise<number> {
    const order = new Order(request.orderId);
    for (const item of request.items) {
      const line: OrderLine = {
        sku: item.sku,
        quantity: item.quantity,
        unitPrice: fromMajor("USD", item.price),
      };
      order.addLine(line);
    }
    order.status = OrderStatus.Placed;
    await this.orders.save(order);
    this.logger.info("order placed", { id: order.id });
    return order.total().minorUnits;
  }
}
