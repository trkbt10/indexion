/**
 * Money is stored as an integer number of minor units so that arithmetic
 * over order lines never accumulates floating point error.
 */
export interface Money {
  currency: string;
  minorUnits: number;
}

/** Build a Money value from a major-unit amount such as 12.30. */
export function fromMajor(currency: string, amount: number): Money {
  return { currency, minorUnits: Math.round(amount * 100) };
}

/**
 * Add two amounts of the same currency.
 *
 * Mixing currencies is a programming error rather than a runtime
 * condition, so it throws instead of returning a result type.
 */
export function add(left: Money, right: Money): Money {
  if (left.currency !== right.currency) {
    throw new Error(`cannot add ${left.currency} to ${right.currency}`);
  }
  return { currency: left.currency, minorUnits: left.minorUnits + right.minorUnits };
}

export const ZERO_USD: Money = { currency: "USD", minorUnits: 0 };
