// Lenient readers for the API's JSON: a missing or mistyped field reads as empty rather than failing the call.
export function isObject(v) {
    return typeof v === 'object' && v !== null && !Array.isArray(v);
}
export function obj(v) {
    return isObject(v) ? v : {};
}
export function list(v) {
    return Array.isArray(v) ? v : [];
}
export function str(v) {
    return typeof v === 'string' ? v : '';
}
export function strOrNull(v) {
    return typeof v === 'string' ? v : null;
}
export function num(v) {
    return typeof v === 'number' && Number.isFinite(v) ? v : null;
}
/** An object's entries, without `__proto__`, which would change the prototype of the map it is copied into. */
export function entries(v) {
    return Object.entries(obj(v)).filter(([key]) => key !== '__proto__');
}
export function stringMap(v) {
    const out = {};
    for (const [key, value] of entries(v)) {
        if (typeof value === 'string')
            out[key] = value;
    }
    return out;
}
export function hasOwn(o, key) {
    return Object.prototype.hasOwnProperty.call(o, key);
}
