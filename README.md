# Snowflake Docs Agent

**Give every user in your Snowflake account an always-available Snowflake expert.**

Deploy in under 5 minutes with a single SQL script. No infrastructure to manage, no per-user setup, no ongoing maintenance.

---

## Why

Every Snowflake team has the same friction: users searching docs, opening support tickets, or waiting on senior engineers for answers that already exist in the official documentation. This agent eliminates that bottleneck.

- **Instant, accurate answers** grounded exclusively in official Snowflake documentation — no hallucination, no outdated blog posts
- **Account-wide access** — every user sees the agent in [Snowflake CoWork](https://ai.snowflake.com) with zero per-user configuration
- **Structured, actionable responses** — every answer includes runnable code examples, access control details, and citations to source docs
- **Reduces support load** — fewer internal tickets, less context-switching for senior engineers, faster onboarding for new team members
- **Always current** — powered by Snowflake's official Cortex Knowledge Extension, which stays in sync with documentation updates

## Who Is This For

- **Platform / Data Engineering teams** who want to empower their org with self-serve Snowflake knowledge
- **Snowflake Admins** looking to reduce repetitive "how do I..." questions
- **Any organization** that wants to accelerate Snowflake adoption and reduce time-to-answer

---

## What It Does

The `SETUP.sql` script creates a fully functional Cortex Agent named **Snowflake Docs Agent** (persona: "Snowflake Sherpa") that:

- Answers Snowflake questions using only official documentation (no hallucination)
- Provides structured responses with code examples, access control details, and follow-up questions
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

## Prerequisites

- **Role:** ACCOUNTADMIN
- **Marketplace Access:** Your organization must have accepted the [Snowflake Marketplace terms](https://other-docs.snowflake.com/en/collaboration/consumer-becoming#accept-the-snowflake-provider-and-consumer-terms)
- **Warehouse:** Any warehouse available to the executing user
- **Cross-Region Inference:** Enabled (or willingness to enable) for model availability

## Quick Start

1. Open `SETUP.sql` in a Snowflake SQL worksheet
2. Run the script top-to-bottom (each section is self-contained and idempotent)
3. The final query outputs your personalized CoWork URL and agent deep link

## Script Sections

| Section | Purpose |
|---------|---------|
| **1. Configure Account & Create Database** | Validates cross-region inference, creates `SNOWFLAKE_DOCS_AGENT` database and `AGENTS` schema |
| **2. Install Cortex Knowledge Extension** | Installs the Snowflake Documentation CKE from the Marketplace (listing `GZSTZ67BY9OQ4`) |
| **3. Create & Deploy Agent** | Creates the agent with persona, instructions, guardrails, and Cortex Search tool |
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

Find and replace `SNOWFLAKE_DOCS_AGENT` throughout the script to use a different database name.

### Modify the Agent Persona

Edit the `instructions.response` and `instructions.orchestration` YAML blocks in Section 3 to change the agent's behavior, response format, or guardrails.

### Restrict Access

Replace grants to `PUBLIC` with a specific role to limit who can use the agent:

```sql
GRANT USAGE ON AGENT AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT TO ROLE <YOUR_ROLE>;
```

## Accessing the Agent

After running the script, access your agent at:

```
https://ai.snowflake.com/<org>/<account>/#/ai/chat/new?db=SNOWFLAKE_DOCS_AGENT&schema=AGENTS&agent=SNOWFLAKE_DOCUMENTATION_AGENT
```

Or navigate to [ai.snowflake.com](https://ai.snowflake.com) and select **Snowflake Docs Agent** from the agent list.

> **Note:** CoWork initializes sessions with the user's default role and warehouse. Ensure all users have these set before sharing the link.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Cross-region inference disabled | Run `ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';` |
| Marketplace listing not available | Run `CALL SYSTEM$REQUEST_LISTING_AND_WAIT('GZSTZ67BY9OQ4', 0);` |
| "Agent already present" error | Safe to ignore -- the script handles this with exception handling |
| "Role doesn't include access" on deep link | Ensure USAGE is granted on the database, schema, and agent to the user's role |

## License

MIT License. See [LICENSE](LICENSE) for details.

## Disclaimer

This project is not an officially supported Snowflake product. It is provided as-is, without warranty or guarantee of any kind. Use at your own risk. Snowflake does not endorse, maintain, or provide support for this project. Always review and test scripts in a non-production environment before deploying to production accounts.
