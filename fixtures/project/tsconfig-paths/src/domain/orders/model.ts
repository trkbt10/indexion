import { Money, ZERO_USD, add } from "shared/money";

/** A single purchasable line within an order. */
export interface OrderLine {
  sku: string;
  quantity: number;
  unitPrice: Money;
}

/** Lifecycle states an order moves through. */
export enum OrderStatus {
  Draft = "draft",
  Placed = "placed",
  Shipped = "shipped",
}

/**
 * An order aggregate.
 *
 * The total is derived rather than stored so that it can never drift
 * away from the lines it is supposed to summarise.
 */
export class Order {
  readonly lines: OrderLine[] = [];

  constructor(
    readonly id: string,
    public status: OrderStatus = OrderStatus.Draft,
  ) {}

  /** Append a line to a draft order. */
  addLine(line: OrderLine): void {
    if (this.status !== OrderStatus.Draft) {
      throw new Error(`order ${this.id} is no longer editable`);
    }
    this.lines.push(line);
  }

  /** Sum every line, quantity included. */
  total(): Money {
    return this.lines.reduce((acc, line) => {
      const lineTotal: Money = {
        currency: line.unitPrice.currency,
        minorUnits: line.unitPrice.minorUnits * line.quantity,
      };
      return add(acc, lineTotal);
    }, ZERO_USD);
  }
}
