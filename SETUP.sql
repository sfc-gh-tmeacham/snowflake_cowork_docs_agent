/*
====================================================================================================
File Name: setup_snowflake_docs_agent.sql
====================================================================================================
Author:      Tom Meacham
Create Date: 2025-08-18
Last Updated: 2026-06-23
Version:     1.1
Description: This script performs a complete, end-to-end setup for a Snowflake expert AI agent
             named "Snowflake Docs Agent". The agent is configured to use the official Snowflake
             documentation as its exclusive knowledge base, ensuring accurate and context-aware
             answers. This script must be run by a user with the ACCOUNTADMIN role.

Prerequisites:
  - ACCOUNTADMIN role (or equivalent privileges)
  - Access to the Snowflake Marketplace (org must have accepted marketplace terms)
  - A warehouse available for the executing user
  - Cross-region inference enabled (or willingness to enable it for model availability)

Objects Created:
  Databases:
    - SNOWFLAKE_DOCS_AGENT          — Hosts the agent and its schema
    - SNOWFLAKE_DOCUMENTATION       — Imported from Marketplace listing (read-only shared data)
  Schemas:
    - SNOWFLAKE_DOCS_AGENT.AGENTS   — Contains the agent object
  Agents:
    - SNOWFLAKE_DOCS_AGENT.AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT
  Snowflake CoWork Object:
    - SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT (account-level, manages agent visibility)
  Grants:
    - USAGE on SNOWFLAKE_DOCS_AGENT (database) → PUBLIC
    - USAGE on SNOWFLAKE_DOCS_AGENT.AGENTS (schema) → PUBLIC
    - IMPORTED PRIVILEGES on SNOWFLAKE_DOCUMENTATION → PUBLIC
    - USAGE on SNOWFLAKE_DOCUMENTATION_AGENT (agent) → PUBLIC
    - DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER → PUBLIC
    - USAGE on SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT → PUBLIC

Script Sections:
  1. Configure Account & Create Agent Database:
     - Validates cross-region inference settings for model availability.
     - Creates the SNOWFLAKE_DOCS_AGENT database and `agents` schema to host the agent.
  2. Install Snowflake Documentation Cortex Extension:
     - Installs the "Snowflake Documentation Cortex Knowledge Extension" Native App from the
       Snowflake Marketplace. This creates the `SNOWFLAKE_DOCUMENTATION` database, which serves
       as the vectorized knowledge base for the agent.
  3. Create and Deploy the Snowflake Docs Agent:
     - Creates the `SNOWFLAKE_DOCUMENTATION_AGENT` agent if it doesn't already exist (preserves
       version history on re-runs).
     - Updates the live version with the full specification (persona, response format, guardrails,
       tool configuration).
     - Commits the live version as an immutable snapshot (VERSION$N) for stable deployment.
     - Connects the agent to the Cortex Search service
       (`SNOWFLAKE_DOCUMENTATION.SHARED.CKE_SNOWFLAKE_DOCS_SERVICE`) for documentation retrieval.
      - Grants USAGE on the agent to the PUBLIC role, making it accessible account-wide.
  4. Add Agent to Snowflake CoWork:
     - Creates the Snowflake CoWork object (SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT) if it
       doesn't already exist.
     - Adds the agent to the CoWork object so it appears in the CoWork interface.
     - Grants USAGE on the CoWork object to PUBLIC for account-wide visibility.
Post-Execution:
     - Upon successful completion, the "Snowflake Docs Agent" will be available for use in the
       Snowflake CoWork interface (https://ai.snowflake.com). The final query in this
       script provides the specific URL for your account.
====================================================================================================
*/

-- Use the ACCOUNTADMIN role to ensure sufficient permissions for all setup tasks.
USE ROLE ACCOUNTADMIN;

-- Define the database name for the agent.
-- To change it, find and replace SNOWFLAKE_DOCS_AGENT throughout this script.


-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 1: CONFIGURE ACCOUNT & CREATE AGENT DATABASE                        ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║  Purpose: Validate cross-region inference and create the database/schema     ║
-- ║           that will host the Snowflake Docs Agent.                            ║
-- ║                                                                              ║
-- ║  Docs: https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork
-- ╚══════════════════════════════════════════════════════════════════════════════╝

/*
====================================================================================================
Step 1.1: Check cross-region inference status
====================================================================================================
Snowflake CoWork routes to models like Claude Sonnet 4.5, Claude Sonnet 4.6, and GPT-4.1,
depending on regional availability. The agent spec uses "auto" which automatically selects
the best available model.

References:
Cross-Region Inference: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cross-region-inference
====================================================================================================
*/
SHOW PARAMETERS LIKE 'CORTEX_ENABLED_CROSS_REGION' IN ACCOUNT ->>
SELECT
    STRTOK_TO_ARRAY("value") as key_value,
    IFF(
        ARRAY_CONTAINS( 'DISABLED'::variant , key_value),
        '⚠️ Cross Region Inference is disabled, depending on your CSP region, you are likely to experience issues.',
        '✅ Cross Region Inference is enabled with these settings: ' || "value"
        ) as validation,
    cecr.* exclude "value",
FROM $1 as cecr;

/*
====================================================================================================
-- Below are the options for this parameter, they must be set by an accountadmin.
-- Values can be comma-combined (e.g., 'AWS_US,AZURE_US'). Choose the broadest
-- setting that meets your data residency requirements.
====================================================================================================
*/

-- Cloud-wide (recommended — covers all regions within a cloud provider)
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_GLOBAL';
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AZURE_GLOBAL';
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'GCP_GLOBAL';

-- Regional (restrict to specific cloud regions)
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_US';
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_EU';
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_APJ';
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AZURE_US';
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AZURE_EU';

-- Multi-cloud combination example
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_US,AZURE_US';

-- Maximum flexibility (all regions, all clouds)
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';


/*
====================================================================================================
Create a database. This holds the configuration object and the other objects used to support
Snowflake CoWork.
====================================================================================================
*/
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_DOCS_AGENT
    COMMENT = 'Houses the Snowflake Docs Agent and its supporting objects.';
GRANT USAGE ON DATABASE SNOWFLAKE_DOCS_AGENT TO ROLE PUBLIC;

/*
====================================================================================================
After you set up the agent database, use the following SQL commands to create a
schema to store the agents and make them discoverable to everyone.
====================================================================================================
*/
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_DOCS_AGENT.AGENTS
    COMMENT = 'Schema for Snowflake CoWork agents deployed from this database.';
GRANT USAGE ON SCHEMA SNOWFLAKE_DOCS_AGENT.AGENTS TO ROLE PUBLIC;


/*
====================================================================================================
Grant the CREATE AGENT privilege on the agents schema to any role that should be able to create
agents for Snowflake CoWork.
====================================================================================================
*/
-- GRANT CREATE AGENT ON SCHEMA SNOWFLAKE_DOCS_AGENT.AGENTS TO ROLE <role>;

/*
====================================================================================================
Note: To use Snowflake CoWork, a user needs the SNOWFLAKE.CORTEX_AGENT_USER database role
(grants access to Cortex Agents only) or the broader SNOWFLAKE.CORTEX_USER role (grants access
to all Cortex AI features). By default, CORTEX_USER is granted to the PUBLIC role, so all users
have access out of the box. If you have a custom configuration, take that into account.
====================================================================================================
*/
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE PUBLIC;


-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 2: INSTALL SNOWFLAKE DOCUMENTATION CORTEX EXTENSION                 ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║  Purpose: Install the "Snowflake Documentation Cortex Knowledge Extension"   ║
-- ║           Native App from the Marketplace. This creates the                  ║
-- ║           SNOWFLAKE_DOCUMENTATION database — the vectorized knowledge base   ║
-- ║           that powers the agent's Cortex Search tool.                        ║
-- ║                                                                              ║
-- ║  Listing: GZSTZ67BY9OQ4                                                      ║
-- ║  Docs: https://docs.snowflake.com/en/user-guide/snowflake-native-apps-about  ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

-- Step 1: Make sure your account has access to the Snowflake Documentation Cortex Knowledge Extension 
DESCRIBE AVAILABLE LISTING GZSTZ67BY9OQ4 ->>
SELECT
    "global_name" as global_name,
    IFF("is_imported"::boolean, 
    '⚠️ Shared databases has already been imported. Consider dropping the imported database and recreating it after investigating dependencies.', 
    '✅ Shared databases has not yet been imported.'
    ) as share_status,
    "title" as title,
    "is_imported"::boolean as is_imported,
    "is_ready_for_import"::boolean as is_ready_for_import,
FROM $1;


/*
====================================================================================================
(Optional) If the listing is already imported, find its local database name
====================================================================================================
Run this only if the previous query showed the listing was already imported. You can use this query
to discover if it has a different name than SNOWFLAKE_DOCUMENTATION.
====================================================================================================
*/
SHOW DATABASES IN ACCOUNT ->>
SELECT 
"created_on",
"name",
IFF("name" = 'SNOWFLAKE_DOCUMENTATION', 
    '✅ Good to go.', 
    '⚠️ Consider renaming this database SNOWFLAKE_DOCUMENTATION or dropping it an reimporting wiht the command in step 3'
    ) as db_name_status,
"origin",
"owner"
FROM $1 
WHERE "kind" = 'IMPORTED DATABASE'
AND "origin" like '%SNOWFLAKE_DOCS_CKE_SNOWFLAKE_SHARE%'
;

/*
====================================================================================================
Step 2: Request the listing to be replicated to your current region
====================================================================================================
This is only required if the check in Step 1 showed the listing was not ready.
====================================================================================================
*/
CALL SYSTEM$REQUEST_LISTING_AND_WAIT('GZSTZ67BY9OQ4', 0);

/*
====================================================================================================
Note
====================================================================================================
If this fails, ensure your ORGANIZATION has accepted the marketplace terms:
https://other-docs.snowflake.com/en/collaboration/consumer-becoming#accept-the-snowflake-provider-and-consumer-terms
====================================================================================================
*/

/*
====================================================================================================
Step 3: Create a local database from the shared listing
====================================================================================================
This command mounts the shared data as a read-only database in your account.
====================================================================================================
*/

CREATE OR REPLACE DATABASE SNOWFLAKE_DOCUMENTATION
FROM LISTING 'GZSTZ67BY9OQ4'
COMMENT = 'Snowflake Documentation - Cortex Knowledge Extension - Updates Weekly';

-- validation
SHOW DATABASES LIKE 'SNOWFLAKE_DOCUMENTATION';
DESCRIBE DATABASE SNOWFLAKE_DOCUMENTATION;

/*
====================================================================================================
Step 4: Grant usage privileges to all roles
====================================================================================================
'IMPORTED PRIVILEGES' is a meta-privilege required for other roles to access objects within a
database created from a share.
====================================================================================================
*/
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_DOCUMENTATION TO ROLE public;

/*
====================================================================================================
Validation: Verify the PUBLIC role has the necessary IMPORTED PRIVILEGES grant
====================================================================================================
*/
SHOW GRANTS ON DATABASE SNOWFLAKE_DOCUMENTATION ->>
SELECT 'VALID - IMPORTED PRIVILEGES has been granted to the Public Role' as "success_message"
FROM $1 
WHERE "grantee_name" = 'PUBLIC' AND "privilege" = 'IMPORTED PRIVILEGES'
UNION ALL BY NAME
SELECT 'INVALID - The PUBLIC role has not been granted IMPORTED PRIVILEGES' as "error_message" 
FROM $1
WHERE NOT EXISTS ( SELECT 1 FROM $1 WHERE "grantee_name" = 'PUBLIC' AND "privilege" = 'IMPORTED PRIVILEGES');

-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 3: CREATE AND DEPLOY THE SNOWFLAKE ASSISTANT AGENT                  ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║  Purpose: Define, create, and grant access to the "Snowflake Docs Agent"     ║
-- ║           agent. This agent uses the Cortex Search service from              ║
-- ║           SNOWFLAKE_DOCUMENTATION to answer Snowflake questions.             ║
-- ║                                                                              ║
-- ║  Versioning Strategy:                                                        ║
-- ║    - CREATE IF NOT EXISTS ensures the agent is only created on first run.    ║
-- ║    - ALTER AGENT MODIFY LIVE VERSION updates the spec on every re-run.       ║
-- ║    - ALTER AGENT COMMIT creates an immutable VERSION$N snapshot.             ║
-- ║    - Previous versions are preserved for rollback.                           ║
-- ║                                                                              ║
-- ║  Agent: SNOWFLAKE_DOCS_AGENT.AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT            ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

USE DATABASE SNOWFLAKE_DOCS_AGENT;

/*
====================================================================================================
Step 3.1: Create the agent (first run only)
====================================================================================================
If the agent doesn't exist, create it with a minimal placeholder spec. The full specification
is applied in the next step via ALTER AGENT. This preserves version history on subsequent runs.
====================================================================================================
*/
CREATE AGENT IF NOT EXISTS AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT
    COMMENT=$$This agent is an expert at answering questions related to Snowflake.$$
FROM SPECIFICATION $$
models:
  orchestration: auto
instructions:
  response: |
    You are Snowflake Sherpa, a Snowflake expert AI.
$$;

/*
====================================================================================================
Step 3.2: Update the agent metadata (profile and comment)
====================================================================================================
These are set independently of the specification and persist across version commits.
====================================================================================================
*/
ALTER AGENT AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT
    SET COMMENT = $$This agent is an expert at answering questions related to Snowflake.$$,
        PROFILE = '{"display_name": "Snowflake Docs Agent", "avatar": "LightbulbIcon", "color": "var(--chartDim_1-x11ij0mo)"}';

/*
====================================================================================================
Step 3.3: Ensure a live version exists for modification
====================================================================================================
After CREATE or COMMIT, the live version may not exist. This ensures one is available
for the MODIFY LIVE VERSION step. If it already exists, this safely catches the error.
====================================================================================================
*/
BEGIN
    ALTER AGENT AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT ADD LIVE VERSION FROM LAST;
EXCEPTION
    WHEN OTHER THEN
        -- Live version already exists; safe to continue.
        NULL;
END;

/*
====================================================================================================
Step 3.4: Update the live version with the full specification
====================================================================================================
This completely replaces the live version's specification. The full spec includes persona,
response format, orchestration instructions, sample questions, and tool configuration.
On first run, this updates the placeholder from Step 3.1.
On subsequent runs, this updates the live version with any changes.
====================================================================================================
*/
ALTER AGENT AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT
MODIFY LIVE VERSION SET SPECIFICATION = $$
models:
  orchestration: auto

instructions:
  response: |
    ## 1. Persona
    You are **Snowflake Sherpa**, a Snowflake expert AI. Your **only** source of truth is the official Snowflake documentation retrieved via your tools.

    ## 2. Tone & Style
    - Professional, helpful, and concise
    - Lead with the direct answer before elaborating
    - Use clear, technical language appropriate for Snowflake practitioners

    ---

    ## 3. Response Format
    **Every response MUST include these core sections:**

    ---

    ### Answer
    A clear, direct response to the question. Lead with the key fact or recommendation. Minimum 1-2 sentences.

    ---

    ### Explanation
    Essential context that expands on the answer. Provide background, how the feature works, and relevant details.

    ---

    **Include these optional sections ONLY when they add substantive value (never include just to say "N/A" or "not applicable"):**

    ### Code Example
    Provide working code demonstrating the concept.
    - Use correct language identifier (e.g., sql, python)
    - Comments explain the *why* (logic and intent), not the *what* (syntax)
    - Ensure code is complete and runnable

    ---

    ### Python API Guide
    Include only when Python is relevant to the question.

    When included, specify the correct API:

    | Task Type                         | Preferred API                                    |
    |-----------------------------------|--------------------------------------------------|
    | Data transformation/querying      | Snowpark DataFrame API (avoid session.sql())     |
    | Pandas-like syntax                | Snowpark pandas API                              |
    | ML training/deployment            | Snowpark ML (snowflake.ml)                       |
    | LLM/AI functions                  | snowflake.cortex module (Complete, Summarize, etc.) |
    | Admin/metadata operations         | Snowflake Python API                             |

    ---

    ### Access Control & Privileges
    Include when the question involves operations that require specific privileges or roles.

    **Format your response as:**
    1. **Snowflake Database Roles:** List any required Snowflake database roles (e.g., CORTEX_USER, GOVERNANCE_VIEWER, DATA_METRIC_USER)
    2. **Account-level Roles:** Specify if ACCOUNTADMIN, SECURITYADMIN, SYSADMIN, or USERADMIN is required
    3. **Object Privileges:** List specific privileges needed (e.g., USAGE, SELECT, CREATE TABLE, EXECUTE TASK, OPERATE)
    4. **Object Access:** Specify required access to databases, schemas, warehouses, or other objects

    ---

    ### Considerations
    Include when there are meaningful limitations, costs, performance implications, or best practices the user should know about.

    ---

    ## 4. Completeness Requirements
    Before finalizing your response, ensure:
    - The full question is answered — if a user asks multiple things, address each part explicitly.
    - Code examples are complete, not partial snippets.
    - Common edge cases or variations are mentioned when relevant.

  orchestration: |
    ## 1. Core Directive
    **Mission:** Provide accurate, complete answers grounded in documentation—with working code examples when applicable.

    **Critical Rules:**
    - Always search documentation before answering technical questions.
    - Never invent features, syntax, or capabilities.

    ---

    ## 2. Tool Selection & Usage
    - Use **Cortex Search** for "how to" questions, feature explanations, syntax, and best practices.
    - If search returns low-relevance results, rephrase the query and retry before stating uncertainty.
    - For ambiguous terms (e.g., "streams", "tasks"), state your interpretation, then search accordingly.
    - Perform additional searches when the initial results don't fully cover the question.
    - **Search for related concepts** — If a user asks about Dynamic Tables, also search for refresh modes, lag settings, and monitoring.
    - **Cross-reference results** — If multiple docs are returned, synthesize information from all relevant sources, not just the first result.

    ---

    ## 3. Task Sequencing
    - **Ambiguous queries:** If the query is ambiguous, provide your best interpretation and answer it, then note the alternative interpretation at the end.
      Example: "I'll answer assuming you mean Table Streams (for CDC). If you meant Snowpipe Streaming, let me know and I'll adjust."
    - **Low confidence:** If retrieved docs do not address the question, say so and suggest rephrasing or a related topic.
    - **Complex procedures:** Break down into numbered steps.

    ---

    ## 4. Guardrails
    - **Scope:** Snowflake topics only. For third-party integrations, use only what is documented.
    - **No speculation:** Do not speculate on unreleased features or offer opinions.
    - **Security:** Only recommend documented security practices. Do not advise disabling security features.
    - **Prefer latest patterns:** Always use the most recent documented API patterns and syntax. Avoid deprecated methods.
    - **Grounding requirement:** Only state facts directly supported by retrieved documentation. If your search results do not contain the answer, respond with: "I couldn't find this in the Snowflake documentation. Try rephrasing your question or asking about a related topic."

  sample_questions:
    - question: "How can I query a deeply nested json with sql?"
    - question: "How to set up a task graph in snowflake to notify me if it fails or succeeds via email?"
    - question: "How do I use Cortex Fine-tuning to customize a language model on my data?"
    - question: "How do I use Openflow connectors to replicate data from PostgreSQL or MySQL into Snowflake?"
    - question: "Can you give me a YAML example for a Snowpark Container Service specification?"
    - question: "What is the Snowflake Feature Store and how do I use it?"
    - question: "How do I build a Streamlit app in Snowflake that connects to a Cortex Agent?"
    - question: "How do I set up row access policies and column masking for multi-tenant data?"
    - question: "How to deploy a custom LLM from Huggingface to Snowpark Container Services (SPCS). Step by Step."
    - question: "How do I set up continuous data ingestion with Snowpipe Streaming?"
    - question: "What is the ASOF JOIN in Snowflake and why would I use it?"
    - question: "How do I use Dynamic Tables to build an incremental data pipeline?"
    - question: "How do I create a Cortex Search service for RAG over my own documents?"
    - question: "What are my options for migrating data and workloads from another data platform to Snowflake?"
    - question: "How do I configure network policies and private connectivity for my Snowflake account?"

tools:
  - tool_spec:
      type: cortex_search
      name: Snowflake_Documentation_Tool
      description: >
        Use this tool to search the official Snowflake documentation. It covers all Snowflake
        topics, including SQL functions, data loading, data sharing, Snowpark (Python, Java, Scala),
        Snowpark Container Services, developing and distributing Snowflake Native Apps, Cortex AI,
        connectors, security, governance, cost management, and account configurations.

tool_resources:
  Snowflake_Documentation_Tool:
    id_column: SOURCE_URL
    max_results: 5
    search_service: SNOWFLAKE_DOCUMENTATION.SHARED.CKE_SNOWFLAKE_DOCS_SERVICE
    title_column: DOCUMENT_TITLE
$$;

/*
====================================================================================================
Step 3.5: Commit the live version
====================================================================================================
Creates an immutable named version (VERSION$N). This snapshot can be referenced by name or
alias for stable deployments. Previous committed versions are preserved for rollback.
====================================================================================================
*/
ALTER AGENT AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT COMMIT COMMENT = 'Updated agent specification';

-- Recreate the live version from the latest commit so the Snowsight test UI remains functional.
ALTER AGENT AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT ADD LIVE VERSION FROM LAST;

-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 3a: GRANT ACCESS & VALIDATE                                         ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║  Purpose: Grant usage to PUBLIC, validate grants, and inspect the agent.     ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

-- Grant usage of this agent to the PUBLIC role
GRANT USAGE ON AGENT AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT TO ROLE PUBLIC;

-- Optionally, grant ownership of this AGENT to another role
-- GRANT OWNERSHIP ON AGENT AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT TO ROLE <SOME_OTHER_ROLE>;

-- Validate grants
SHOW GRANTS ON AGENT AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT;

-- List agents in the database
SHOW AGENTS like 'SNOWFLAKE_DOCUMENTATION_AGENT' in database SNOWFLAKE_DOCS_AGENT ->>
select * from $1;

-- Inspect the agent
DESCRIBE AGENT AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT;

-- Describe agent with parsed JSON fields
DESCRIBE AGENT AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT ->>
SELECT 
    * exclude ("profile", "agent_spec"),
    parse_json("profile") as profile,
    parse_json("agent_spec") as agent_spec
FROM $1 as t;

-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 4: ADD AGENT TO SNOWFLAKE COWORK                                    ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║  Purpose: Register the agent with the Snowflake CoWork object so it          ║
-- ║           appears in the CoWork interface for all users.                      ║
-- ║                                                                              ║
-- ║  Note: If a Snowflake CoWork object exists in the account, agents must be    ║
-- ║        explicitly added to it to be visible. If no CoWork object exists,     ║
-- ║        all agents with proper USAGE grants are visible automatically.        ║
-- ║                                                                              ║
-- ║  Docs: https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/deploy-agents
-- ╚══════════════════════════════════════════════════════════════════════════════╝

/*
====================================================================================================
Step 4.1: Create the Snowflake CoWork object (if it doesn't already exist)
====================================================================================================
The Snowflake CoWork object is an account-level object that manages which agents are visible
in the CoWork interface. Only one can exist per account. If one already exists, this will
no-op safely with IF NOT EXISTS.
====================================================================================================
*/
CREATE SNOWFLAKE INTELLIGENCE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;

/*
====================================================================================================
Step 4.2: Add the agent to the Snowflake CoWork object
====================================================================================================
This makes the agent visible to all users who have USAGE on the CoWork object.
Without this step, the agent would only be accessible via a direct link or Snowsight UI.
====================================================================================================
*/
BEGIN
    ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
        ADD AGENT SNOWFLAKE_DOCS_AGENT.AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT;
EXCEPTION
    WHEN OTHER THEN
        -- Agent is already present in the CoWork object; safe to ignore.
        NULL;
END;

/*
====================================================================================================
Step 4.3: Grant USAGE on the Snowflake CoWork object to PUBLIC
====================================================================================================
This allows all users to see the curated list of agents in CoWork.
====================================================================================================
*/
GRANT USAGE ON SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT TO ROLE PUBLIC;

-- Validate: Show the CoWork object and its agents
SHOW SNOWFLAKE INTELLIGENCES;


-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  POST-EXECUTION: ACCESS YOUR AGENT                                           ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║  Your agent is now ready! The query below provides your account identifier   ║
-- ║  and the URLs to access Snowflake CoWork.                                    ║
-- ║                                                                              ║
-- ║  Note: CoWork uses the user's default role and warehouse. Ensure all users   ║
-- ║        have these set before sharing the link.                               ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝
SELECT 
CONCAT(CURRENT_ORGANIZATION_NAME(),'-',CURRENT_ACCOUNT_NAME()) as account_identifier,
'https://ai.snowflake.com' as cowork_url,
LOWER(CONCAT('https://ai.snowflake.com/'||current_organization_name()||'/'||current_account_name()||'/#/ai')) as cowork_url_direct,
CONCAT('https://ai.snowflake.com/'||LOWER(current_organization_name())||'/'||LOWER(current_account_name())||'/#/ai/chat/new?db=SNOWFLAKE_DOCS_AGENT&schema=AGENTS&agent=SNOWFLAKE_DOCUMENTATION_AGENT') as agent_direct_url;