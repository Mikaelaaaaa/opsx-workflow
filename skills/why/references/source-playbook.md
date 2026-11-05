# Source playbooks

The why skill spawns one investigator per available evidence category, each reading a single source-specific playbook below. The playbooks are concrete examples for common MCPs. Adapt them for a different MCP in the same category.

| Category | Playbook | Example MCP it documents |
|---|---|---|
| Source control history | [`code-archaeology.md`](./sources/code-archaeology.md) | git, `gh` |
| Issue / ticket tracker | `linear.md` (not shipped) | Linear (adapt for Jira, GitHub Issues, Plane, Shortcut) |
| Long-form documents | `notion.md` (not shipped) | Notion (adapt for Confluence, Google Docs, Coda) |
| Real-time team chat | `slack.md` (not shipped) | Slack (adapt for Discord, Microsoft Teams, Mattermost) |
| Infrastructure observability | `datadog.md` (not shipped) | Datadog (adapt for New Relic, Honeycomb, Grafana, Splunk) |
| Error / exception tracking | `sentry.md` (not shipped) | Sentry (adapt for Rollbar, Bugsnag, Airbrake) |
| Product analytics warehouse | `databricks.md` (not shipped) | Databricks SQL (adapt for Snowflake, BigQuery, ClickHouse, dbt) |

Only `code-archaeology.md` and `incident-postmortem.md` are copied into this plugin. For a category marked "not shipped", write the investigator's source section in the shape of `code-archaeology.md` (what the source contains, how to search it) for the MCP at hand. The upstream playbooks are in cursor-plugins/pstack `skills/why/references/sources/`.

Cross-cutting:

- [`incident-postmortem.md`](./sources/incident-postmortem.md). Add this if the target code looks defensive (null checks, retry, timeout, rate limit, feature flag, egress guard, OOM handler).
