import { Order } from "@domain/orders/model";
import { Logger } from "shared/logger";

/** Persistence boundary for the order aggregate. */
export interface OrderRepository {
  find(id: string): Promise<Order | undefined>;
  save(order: Order): Promise<void>;
}

/**
 * In-memory implementation used by tests and local development.
 *
 * It keeps insertion order so that listing endpoints stay deterministic.
 */
export class InMemoryOrderRepository implements OrderRepository {
  private readonly byId = new Map<string, Order>();
  private readonly logger = new Logger("orders.repository");

  async find(id: string): Promise<Order | undefined> {
    return this.byId.get(id);
  }

  async save(order: Order): Promise<void> {
    this.byId.set(order.id, order);
    this.logger.info("order saved", { id: order.id });
  }
}
