import { test } from "node:test";
import assert from "node:assert/strict";
import { cartTotal } from "./cart.mjs";

test("sums price times quantity", () => {
  assert.equal(cartTotal([{ priceCents: 500, qty: 2 }, { priceCents: 250, qty: 1 }]), "$12.50");
});
