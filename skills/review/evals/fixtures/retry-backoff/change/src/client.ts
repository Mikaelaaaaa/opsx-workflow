import { expDelays } from "./backoff.ts";

export interface RequestOptions {
  timeoutMs?: number;
  retries?: number;
  fetchImpl?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
}

const MAX_DELAY_MS = 30_000;

function wait(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function getJson<T>(url: string, opts: RequestOptions = {}): Promise<T> {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const sleep = opts.sleep ?? wait;
  const delays = expDelays(opts.retries ?? 5).map((d) => Math.min(d, MAX_DELAY_MS));
  let waited = 0;
  let lastStatus = 0;
  for (let attempt = 0; ; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), opts.timeoutMs ?? 10_000);
    let res: Response | undefined;
    let body: string | undefined;
    try {
      res = await fetchImpl(url, { signal: controller.signal });
      if (res.ok) {
        body = await res.text();
      }
    } catch {
      res = undefined;
      lastStatus = 0;
    } finally {
      clearTimeout(timer);
    }
    if (body !== undefined) {
      return JSON.parse(body) as T;
    }
    if (res) {
      lastStatus = res.status;
    }
    if (attempt >= delays.length) {
      throw new Error(`GET ${url} failed after ${attempt + 1} attempts: last status ${lastStatus}, waited ${waited} ms`);
    }
    await sleep(delays[attempt]);
    waited += delays[attempt];
  }
}
