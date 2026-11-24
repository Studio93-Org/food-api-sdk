// Lenient readers for the API's JSON: a missing or mistyped field reads as empty rather than failing the call.

type JsonObject = Record<string, unknown>;

export function isObject(v: unknown): v is JsonObject {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

export function obj(v: unknown): JsonObject {
  return isObject(v) ? v : {};
}

export function list(v: unknown): unknown[] {
  return Array.isArray(v) ? v : [];
}

export function str(v: unknown): string {
  return typeof v === 'string' ? v : '';
}

export function strOrNull(v: unknown): string | null {
  return typeof v === 'string' ? v : null;
}

export function num(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

/** An object's entries, without `__proto__`, which would change the prototype of the map it is copied into. */
export function entries(v: unknown): [string, unknown][] {
  return Object.entries(obj(v)).filter(([key]) => key !== '__proto__');
}

export function stringMap(v: unknown): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of entries(v)) {
    if (typeof value === 'string') out[key] = value;
  }
  return out;
}

export function hasOwn(o: object, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(o, key);
}
