export function expDelays(attempts: number, baseMs = 500): number[] {
  return Array.from({ length: attempts }, (_, i) => baseMs * 2 ** i);
}

export function fixedDelays(attempts: number, intervalMs = 2_000): number[] {
  return Array.from({ length: attempts }, () => intervalMs);
}
