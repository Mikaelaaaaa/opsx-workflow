import { getJson } from "./client.ts";

export interface Page {
  items: { sku: string; qty: number }[];
  next: string | null;
}

const REQUEST_TIMEOUT_MS = 5_000;

export async function syncInventory(firstUrl: string, save: (page: Page) => Promise<void>): Promise<number> {
  let url: string | null = firstUrl;
  let pages = 0;
  while (url) {
    const page: Page = await getJson<Page>(url, { timeoutMs: REQUEST_TIMEOUT_MS });
    await save(page);
    pages += 1;
    url = page.next;
  }
  return pages;
}
