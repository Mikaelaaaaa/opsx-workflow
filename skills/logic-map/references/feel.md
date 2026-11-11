# FEEL for logic maps

FEEL is the expression language of DMN (Decision Model and Notation). The map uses a small part of it. This page lists that part and how common code idioms translate.

## The part we use

| Need | FEEL |
|---|---|
| Compare | `x = 3`, `x != null`, `x < 0.7`, `x >= 500` |
| Combine | `a and b`, `a or b`, `not(a)` |
| Membership | `x in ["健康","宗教","政治"]`, `x in [1..5]` |
| Text | `contains(s, "合併")`, `starts with(s, "/")`, `ends with(s, ".md")`, `matches(s, "^git\s+commit")`, `lower case(s)` |
| Any or all of a list | `some w in WORDS satisfies contains(s, w)`, `every f in files satisfies …` |
| Filter and count | `files[ends with(item, ".sh")]`, `count(list)`, `sum(list)` |
| Choice | `if c then "a" else if d then "b" else "c"` |
| Empty | `x = null`, `x = ""`, `count(list) = 0` |
| Time | `now()`, `today()`, `duration("PT5M")`, `time(now()) in [time("09:00")..time("18:00")]` |
| File exists (not FEEL; write it this way) | `exists(file "<path>")` |

## Idioms to FEEL

| Code | FEEL |
|---|---|
| `[ -z "$x" ]` | `x = null or x = ""` |
| `[ -n "$x" ]` | `x != null and x != ""` |
| `[ -f "$p" ]`, `[ -d "$p" ]` | `exists(file p)`, `exists(dir p)` |
| `case "$s" in *word*)` | `contains(s, "word")` |
| `case "$s" in a|b)` | `s in ["a","b"]` |
| `grep -q 'pat'` on text | `matches(text, "pat")` |
| `grep -qE '(^|\s)git\s+commit'` | `matches(cmd, "(^|\s)git\s+commit")` |
| `[[ "$s" =~ re ]]` | `matches(s, "re")` |
| `[ "$n" -eq 0 ]` | `n = 0` |
| Python `if not x:` | `x = null or x = "" or count(x) = 0` (pick the one the type allows) |
| Python `any(k in s for k in WORDS)` | `some k in WORDS satisfies contains(s, k)` |
| Python `x.get("k")` truthy | `x.k != null` |
| Python `d.get(k, default)` | `if x.k = null then default else x.k` |
| First `if` that matches wins (`if/elif` chain) | One row per branch, in order; say in the first row that it shadows the rest |

Keep the regex or the word list exactly as the code has it. The user judges the literal.
