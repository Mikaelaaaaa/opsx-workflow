export interface Article {
  id: string;
  title: string;
  body: string;
}

export function toJsonl(articles: Article[]): string {
  return articles.map((a) => JSON.stringify(a)).join("\n");
}
