// Checks a client IP address the way the API does (Go's netip.ParseAddr), so a bad one fails before a request.
/** Whether `s` is an IPv4 address (dotted decimal, no leading zeros) or an IPv6 address (with an optional zone). */
export function isIpAddress(s) {
    return s.includes(':') ? isIPv6(s) : isIPv4(s);
}
function isIPv4(s) {
    const parts = s.split('.');
    return parts.length === 4 && parts.every(isOctet);
}
function isOctet(p) {
    if (!/^[0-9]{1,3}$/.test(p) || (p.length > 1 && p.startsWith('0')))
        return false;
    return Number(p) <= 255;
}
function isIPv6(s) {
    const zone = s.indexOf('%');
    if (zone !== -1) {
        if (zone === s.length - 1)
            return false; // An empty zone
        s = s.slice(0, zone);
    }
    const halves = s.split('::');
    if (halves.length > 2)
        return false;
    const groups = (half) => (half === '' ? [] : half.split(':'));
    const head = groups(halves[0] ?? '');
    const tail = halves.length === 2 ? groups(halves[1] ?? '') : [];
    const all = [...head, ...tail];
    // An IPv4 address may end it ("::ffff:192.0.2.1"), counting as two groups
    let count = all.length;
    const last = all[all.length - 1];
    if (last !== undefined && last.includes('.')) {
        if (!isIPv4(last))
            return false;
        all.pop();
        count++;
    }
    if (!all.every((g) => /^[0-9a-fA-F]{1,4}$/.test(g)))
        return false;
    return halves.length === 2 ? count < 8 : count === 8;
}
