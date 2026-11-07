export function formatPrice(cents) {
  const dollars = Math.floor(cents / 100);
  const rest = cents % 100;
  return `$${dollars}.${rest === 0 ? "00" : rest}`;
}
