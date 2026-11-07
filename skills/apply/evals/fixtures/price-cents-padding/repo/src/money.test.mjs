import { test } from "node:test";
import assert from "node:assert/strict";
import { formatPrice } from "./money.mjs";

test("whole dollars get two zeros", () => {
  assert.equal(formatPrice(1000), "$10.00");
});

test("two-digit cents", () => {
  assert.equal(formatPrice(1250), "$12.50");
  assert.equal(formatPrice(199), "$1.99");
});
