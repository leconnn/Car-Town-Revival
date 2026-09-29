// Small helpers matching GDScript's integer behaviour.

/** GDScript `int / int`: truncates toward zero. */
export function idiv(a: number, b: number): number {
  return Math.trunc(a / b);
}

/** GDScript `posmod`. */
export function posmod(a: number, b: number): number {
  return ((a % b) + b) % b;
}

/** GDScript `roundi`: rounds half away from zero. */
export function roundi(x: number): number {
  return x < 0 ? -Math.round(-x) : Math.round(x);
}

/** GDScript `str()` of an int, used for dictionary keys in saves. */
export function key(n: number): string {
  return String(n);
}

/** Deep copy of plain JSON data. */
export function clone<T>(v: T): T {
  return JSON.parse(JSON.stringify(v));
}

/** Server copy of scripts/rules/simple_rng.gd (31-bit LCG). */
export const SimpleRng = {
  MODULUS: 2147483648,
  next(state: number): number {
    return Number((BigInt(state) * 1103515245n + 12345n) % 2147483648n);
  },
  /** Returns [newState, value in [low, high]]. */
  rangeInt(state: number, low: number, high: number): [number, number] {
    const s = SimpleRng.next(state);
    return [s, low + ((s >> 8) % (high - low + 1))];
  },
};
