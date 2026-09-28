export const ACTIVE_BOOKINGS = ["PENDING", "CONFIRMED"] as const;
export function mayCancel(startsAt: Date, now = new Date()) {
  return startsAt.getTime() - now.getTime() > 24 * 60 * 60 * 1000;
}
export function overlaps(a: Date, b: Date, c: Date, d: Date) {
  return a < d && b > c;
}
export function discounted(price: number, percent: number) {
  return Math.max(0, price - Math.floor((price * percent) / 100));
}
export function validWindow(start: Date, end: Date, now = new Date()) {
  return (
    Number.isFinite(+start) &&
    Number.isFinite(+end) &&
    start > now &&
    end > start &&
    +end - +start <= 12 * 3600000
  );
}
export function imageMime(bytes: Buffer): string | null {
  if (
    bytes.length >= 8 &&
    bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
  )
    return "image/png";
  if (
    bytes.length >= 3 &&
    bytes[0] === 255 &&
    bytes[1] === 216 &&
    bytes[2] === 255
  )
    return "image/jpeg";
  if (
    bytes.length >= 12 &&
    bytes.toString("ascii", 0, 4) === "RIFF" &&
    bytes.toString("ascii", 8, 12) === "WEBP"
  )
    return "image/webp";
  return null;
}
