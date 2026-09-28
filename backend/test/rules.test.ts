import { test } from "node:test";
import assert from "node:assert/strict";
import {
  mayCancel,
  discounted,
  overlaps,
  validWindow,
  imageMime,
} from "../src/studio/rules";
test("cancellation boundary is strictly more than 24 hours", () => {
  const now = new Date("2026-10-01T00:00:00Z");
  assert.equal(mayCancel(new Date(+now + 86400001), now), true);
  assert.equal(mayCancel(new Date(+now + 86400000), now), false);
  assert.equal(mayCancel(new Date(+now - 1), now), false);
});
test("overlap includes containment but allows adjacent slots", () => {
  const t = (n: number) => new Date(n);
  assert.equal(overlaps(t(1), t(4), t(2), t(3)), true);
  assert.equal(overlaps(t(1), t(2), t(2), t(3)), false);
});
test("money is integer arithmetic and never negative", () => {
  assert.equal(discounted(35000, 15), 29750);
  assert.equal(discounted(99, 10), 90);
  assert.equal(discounted(35000, 100), 0);
});
test("reject invalid, past, reversed and overly long windows", () => {
  const now = new Date(1000);
  assert.equal(validWindow(new Date(2000), new Date(3000), now), true);
  assert.equal(validWindow(new Date("bad"), new Date(3000), now), false);
  assert.equal(validWindow(new Date(0), new Date(3000), now), false);
  assert.equal(validWindow(new Date(3000), new Date(2000), now), false);
  assert.equal(
    validWindow(new Date(2000), new Date(2000 + 13 * 3600000), now),
    false,
  );
});
test("proof type checked by bytes, not filename", () => {
  assert.equal(imageMime(Buffer.from('<svg onload="alert(1)">')), null);
  assert.equal(
    imageMime(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])),
    "image/png",
  );
  assert.equal(imageMime(Buffer.from([255, 216, 255])), "image/jpeg");
});
