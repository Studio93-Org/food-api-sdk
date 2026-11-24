type JsonObject = Record<string, unknown>;
export declare function isObject(v: unknown): v is JsonObject;
export declare function obj(v: unknown): JsonObject;
export declare function list(v: unknown): unknown[];
export declare function str(v: unknown): string;
export declare function strOrNull(v: unknown): string | null;
export declare function num(v: unknown): number | null;
/** An object's entries, without `__proto__`, which would change the prototype of the map it is copied into. */
export declare function entries(v: unknown): [string, unknown][];
export declare function stringMap(v: unknown): Record<string, string>;
export declare function hasOwn(o: object, key: string): boolean;
export {};
