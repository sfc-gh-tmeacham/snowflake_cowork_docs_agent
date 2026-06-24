# Snowflake Docs Agent

**Give every user in your Snowflake account an always-available Snowflake expert.**

Deploy in under 5 minutes with two SQL scripts. No infrastructure to manage, no per-user setup, no ongoing maintenance.

> **New to Cortex Agents?** This is a great first agent to deploy. It's read-only (no access to your data), low risk (grounded exclusively in official docs), and immediately useful to every user in your organization. A safe way to demonstrate the value of Cortex Agents before building custom agents over your own data.

---

## Why

Every Snowflake team has the same friction: users searching docs, opening support tickets, or waiting on senior engineers for answers that already exist in the official documentation. This agent eliminates that bottleneck.

- **Instant, accurate answers** grounded exclusively in official Snowflake documentation — no hallucination, no outdated blog posts
- **Account-wide access** — every user sees the agent in [Snowflake CoWork](https://ai.snowflake.com) with zero per-user configuration
- **Structured, actionable responses** — every answer includes runnable code examples and access control details when relevant
- **Reduces support load** — fewer internal tickets, less context-switching for senior engineers, faster onboarding for new team members
- **Always current** — powered by the free [Snowflake Documentation Cortex Knowledge Extension](https://app.snowflake.com/marketplace/listing/GZSTZ67BY9OQ4/snowflake-snowflake-documentation) from the Snowflake Marketplace, which stays in sync with official documentation updates
- **Zero cost to install** — the knowledge extension is free and maintained by Snowflake; you only pay for compute when querying the agent

## Who Is This For

- **Platform / Data Engineering teams** who want to empower their org with self-serve Snowflake knowledge
- **Snowflake Admins** looking to reduce repetitive "how do I..." questions
- **Any organization** that wants to accelerate Snowflake adoption and reduce time-to-answer

---

## What It Does

Two SQL scripts create a fully functional Cortex Agent named **Snowflake Docs Agent** (persona: "Snowflake Sherpa") that:

- Answers Snowflake questions using only official documentation (no hallucination)
- Provides structured responses with code examples and access control details when relevant
- Is accessible to all users in your account via Snowflake CoWork

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Snowflake CoWork (https://ai.snowflake.com)                    │
│  └── SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT                      │
│       └── SNOWFLAKE_DOCS_AGENT.AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT
│            └── Cortex Search Tool                               │
│                 └── SNOWFLAKE_DOCUMENTATION.SHARED              │
│                      .CKE_SNOWFLAKE_DOCS_SERVICE                │
└─────────────────────────────────────────────────────────────────┘
```

### What is a Cortex Knowledge Extension (CKE)?

A **Cortex Knowledge Extension** is a pre-built, vectorized knowledge base published on the Snowflake Marketplace. It provides a ready-to-use [Cortex Search](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview) service that agents can query for RAG (Retrieval-Augmented Generation) without you needing to build ingestion pipelines, chunk documents, or manage embeddings.

This project uses the **[Snowflake Documentation CKE](https://app.snowflake.com/marketplace/listing/GZSTZ67BY9OQ4/snowflake-snowflake-documentation)** (listing `GZSTZ67BY9OQ4`), which:

- **Is free** — no credits charged for the shared data itself
- **Auto-updates** — Snowflake maintains and refreshes the vectorized content as documentation changes
- **Is read-only** — imported as a shared database; no write access to your account's data
- **Provides a Cortex Search service** (`CKE_SNOWFLAKE_DOCS_SERVICE`) that the agent calls as its retrieval tool

When the agent receives a question, it sends a search query to this service, retrieves the most relevant documentation chunks, and uses them to generate a grounded response. You never need to manage the underlying data — Snowflake handles ingestion, chunking, embedding, and indexing.

## Prerequisites & Permissions

### Required Roles

| Role | Purpose |
|------|---------|
| `ACCOUNTADMIN` | Creates databases, schemas, agents, grants privileges, manages account parameters |
| `MARKETPLACE_ADMIN` (or ACCOUNTADMIN) | Accepts Marketplace listings and imports shared databases |

> **Note:** Both scripts assume you are running as `ACCOUNTADMIN`. If your account uses a custom role hierarchy, ensure the executing role has: `CREATE DATABASE`, `CREATE AGENT`, `CREATE SNOWFLAKE INTELLIGENCE`, `MANAGE GRANTS`, and `IMPORT SHARE` privileges.

### Warehouse Requirements

- Any active warehouse available to the executing user (needed for running the setup queries)
- Agent queries at runtime are lightweight — a Small warehouse is sufficient as a default for users
- If available in your region, [Adaptive Warehouses](https://docs.snowflake.com/en/user-guide/warehouses-adaptive) are ideal as a shared default (auto-scales per query, no sizing/tuning needed)

### Other Requirements

- **Marketplace Access:** Your organization must have accepted the [Snowflake Marketplace terms](https://other-docs.snowflake.com/en/collaboration/consumer-becoming#accept-the-snowflake-provider-and-consumer-terms)
- **Cross-Region Inference:** Enabled (or willingness to enable) for model availability — the agent uses `auto` model selection which routes to the best available model across regions
- **Default Warehouse per User:** CoWork requires each user to have a default warehouse set. See the optional section at the end of `01_SETUP_ENVIRONMENT.sql` to bulk-assign one

## Quick Start

1. Open `01_SETUP_ENVIRONMENT.sql` in a Snowflake SQL worksheet
2. Run the script top-to-bottom (each section is self-contained and idempotent)
3. Open `02_SETUP_AGENT.sql` in a Snowflake SQL worksheet
4. Run the script top-to-bottom
5. The final query outputs your personalized CoWork URL and agent deep link

## Script Sections

### 01_SETUP_ENVIRONMENT.sql

| Section | Purpose |
|---------|---------|
| **1. Configure Account & Create Database** | Validates cross-region inference, creates `SNOWFLAKE_DOCS_AGENT` database and `AGENTS` schema |
| **2. Install Cortex Knowledge Extension** | Installs the Snowflake Documentation CKE from the Marketplace (listing `GZSTZ67BY9OQ4`) |
| **Optional: Set Default Warehouse** | Diagnostic query and async script to set a default warehouse for users who don't have one |

### 02_SETUP_AGENT.sql

| Section | Purpose |
|---------|---------|
| **3. Create & Deploy Agent** | Creates the agent (if not exists), updates live version with full spec, commits as immutable version |
| **3a. Grant Access & Validate** | Grants USAGE to PUBLIC, validates grants, inspects agent configuration |
| **4. Add Agent to Snowflake CoWork** | Registers the agent with the CoWork object for UI visibility |
| **Post-Execution** | Outputs account identifier, CoWork URL, and agent deep link |

## Objects Created

| Object | Type | Description |
|--------|------|-------------|
| `SNOWFLAKE_DOCS_AGENT` | Database | Hosts the agent and its schema |
| `SNOWFLAKE_DOCS_AGENT.AGENTS` | Schema | Contains the agent object |
| `SNOWFLAKE_DOCS_AGENT.AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT` | Agent | The Snowflake Docs Agent |
| `SNOWFLAKE_DOCUMENTATION` | Database | Imported from Marketplace (read-only shared data) |
| `SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT` | Snowflake Intelligence | Account-level CoWork object for agent visibility |

## Grants Applied

All grants target the `PUBLIC` role for account-wide access:

- `USAGE` on `SNOWFLAKE_DOCS_AGENT` (database)
- `USAGE` on `SNOWFLAKE_DOCS_AGENT.AGENTS` (schema)
- `IMPORTED PRIVILEGES` on `SNOWFLAKE_DOCUMENTATION`
- `USAGE` on `SNOWFLAKE_DOCUMENTATION_AGENT` (agent)
- `DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER`
- `USAGE` on `SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT`

## Customization

### Change the Agent Name

Find and replace `SNOWFLAKE_DOCS_AGENT` throughout both scripts to use a different database name.

### Modify the Agent Persona

Edit the `instructions.response` and `instructions.orchestration` YAML blocks in Section 3 of `02_SETUP_AGENT.sql` to change the agent's behavior, response format, or guardrails.

Alternatively, once the agent is created (after running `02_SETUP_AGENT.sql`), you can edit it directly in the Snowsight UI:

1. Navigate to **AI & ML > Agents** in the left navigation menu
2. Select `SNOWFLAKE_DOCUMENTATION_AGENT`
3. Edit the specification in the built-in editor
4. Test the agent against the live version before committing

### Restrict Access

Replace grants to `PUBLIC` with a specific role to limit who can use the agent:

```sql
GRANT USAGE ON AGENT AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT TO ROLE <YOUR_ROLE>;
```

## Accessing the Agent

After running both scripts, access your agent at:

```
https://ai.snowflake.com/<org>/<account>/#/ai/chat/new?db=SNOWFLAKE_DOCS_AGENT&schema=AGENTS&agent=SNOWFLAKE_DOCUMENTATION_AGENT
```

Or navigate to [ai.snowflake.com](https://ai.snowflake.com) and select **Snowflake Docs Agent** from the agent list.

> **Note:** CoWork initializes sessions with the user's default role and warehouse. Ensure all users have these set before sharing the link. The optional section at the end of `01_SETUP_ENVIRONMENT.sql` can help set default warehouses for users who don't have one.

## Testing the Agent

After deployment, test the agent directly via SQL using [`DATA_AGENT_RUN`](https://docs.snowflake.com/en/sql-reference/functions/data_agent_run-snowflake-cortex):

```sql
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'SNOWFLAKE_DOCS_AGENT.AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT',
    '{"messages": [{"role": "user", "content": [{"type": "text", "text": "How do I create a Dynamic Table?"}]}]}'
);
```

Or parse the response for readability:

```sql
SELECT TRY_PARSE_JSON(
    SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
        'SNOWFLAKE_DOCS_AGENT.AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT',
        '{"messages": [{"role": "user", "content": [{"type": "text", "text": "What is Snowpipe Streaming and how do I set it up?"}]}]}'
    )
) AS response;
```

## Version History

The script uses agent versioning — each run commits an immutable snapshot. To list all committed versions:

```sql
SHOW VERSIONS IN AGENT SNOWFLAKE_DOCS_AGENT.AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT;
```

To roll back to a previous version, set it as the default:

```sql
ALTER AGENT SNOWFLAKE_DOCS_AGENT.AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT
    SET DEFAULT VERSION = 'VERSION$3';
```

## Observability

Query the agent's execution logs to see which topics are searched most frequently:

```sql
WITH searches AS (
    SELECT
        RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_search.query"::STRING AS search_query,
        RECORD_ATTRIBUTES:"snow.ai.observability.agent.tool.cortex_search.duration"::NUMBER AS duration_ms
    FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
        'SNOWFLAKE_DOCS_AGENT',
        'AGENTS',
        'SNOWFLAKE_DOCUMENTATION_AGENT',
        'CORTEX AGENT'
    ))
    WHERE RECORD:name::STRING = 'CortexSearchService_Snowflake_Documentation_Tool'
)
SELECT
    search_query,
    duration_ms
FROM searches
ORDER BY duration_ms DESC;
```

Or view all event types to understand the agent's reasoning steps:

```sql
SELECT
    RECORD:name::STRING AS event_name,
    COUNT(*) AS count
FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
    'SNOWFLAKE_DOCS_AGENT',
    'AGENTS',
    'SNOWFLAKE_DOCUMENTATION_AGENT',
    'CORTEX AGENT'
))
GROUP BY event_name
ORDER BY count DESC;
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Cross-region inference disabled | Run `ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';` |
| Marketplace listing not available | Run `CALL SYSTEM$REQUEST_LISTING_AND_WAIT('GZSTZ67BY9OQ4', 0);` |
| "Agent already present" error | Safe to ignore -- the script handles this with exception handling |
| "Role doesn't include access" on deep link | Ensure USAGE is granted on the database, schema, and agent to the user's role |
| "Version 'live' not found" | Run `ALTER AGENT AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT ADD LIVE VERSION FROM LAST;` |
| Users can't use CoWork | Ensure users have a default warehouse set (see optional section in `01_SETUP_ENVIRONMENT.sql`) |

## License

MIT License. See [LICENSE](LICENSE) for details.

## Disclaimer

This project is not an officially supported Snowflake product. It is provided as-is, without warranty or guarantee of any kind. Use at your own risk. Snowflake does not endorse, maintain, or provide support for this project. Always review and test scripts in a non-production environment before deploying to production accounts.
