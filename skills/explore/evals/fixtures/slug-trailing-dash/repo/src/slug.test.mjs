import { test } from "node:test";
import assert from "node:assert/strict";
import { slugify } from "./slug.mjs";

test("joins words with a dash", () => {
  assert.equal(slugify("Hello World"), "hello-world");
});

test("collapses runs of punctuation and spaces", () => {
  assert.equal(slugify("Tips & Tricks"), "tips-tricks");
});
