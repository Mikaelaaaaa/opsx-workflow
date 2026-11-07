import { test } from "node:test";
import assert from "node:assert/strict";
import { getJson } from "./client.ts";

function responses(...statuses: number[]): typeof fetch {
  let i = 0;
  return (async () => {
    const status = statuses[Math.min(i++, statuses.length - 1)];
    return new Response(JSON.stringify({ ok: true }), { status });
  }) as typeof fetch;
}

test("retries a 503 until upstream recovers", async () => {
  const slept: number[] = [];
  const body = await getJson<{ ok: boolean }>("http://upstream/items", {
    fetchImpl: responses(503, 503, 200),
    sleep: async (ms) => { slept.push(ms); },
  });
  assert.deepEqual(body, { ok: true });
  assert.deepEqual(slept, [500, 1000]);
});

test("no single wait goes past 30 seconds", async () => {
  const slept: number[] = [];
  await assert.rejects(
    getJson("http://upstream/items", {
      retries: 8,
      fetchImpl: responses(503),
      sleep: async (ms) => { slept.push(ms); },
    }),
  );
  assert.equal(Math.max(...slept), 30_000);
});

test("final error carries the last status and the total wait", async () => {
  await assert.rejects(
    getJson("http://upstream/items", {
      retries: 2,
      fetchImpl: responses(503),
      sleep: async () => {},
    }),
    /last status 503, waited 1500 ms/,
  );
});
