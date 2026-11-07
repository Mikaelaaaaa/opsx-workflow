import { formatPrice } from "./money.mjs";

export function cartTotal(items) {
  const cents = items.reduce((sum, item) => sum + item.priceCents * item.qty, 0);
  return formatPrice(cents);
}
