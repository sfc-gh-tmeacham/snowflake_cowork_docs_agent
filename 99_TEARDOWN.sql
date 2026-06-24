/*
====================================================================================================
File Name: 99_TEARDOWN.sql
====================================================================================================
Author:      Tom Meacham
Create Date: 2026-06-24
Version:     1.0
Description: Removes all objects created by the Snowflake Docs Agent setup scripts.
             This script is safe to run regardless of whether you used 02a (basic) or
             02b (with email tool) — it handles both cases.

             Objects are dropped in reverse dependency order to avoid errors.

WARNING:
  - This script is DESTRUCTIVE and IRREVERSIBLE.
  - It will remove the agent, procedure, integration, agent database, CoWork
    registration, and all associated grants.
  - It will NOT remove the SNOWFLAKE_DOCUMENTATION Marketplace database.

Prerequisites:
  - ACCOUNTADMIN role (or equivalent privileges)

Objects Removed:
  Snowflake CoWork:
    - Agent removed from SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
  Agents:
    - SNOWFLAKE_DOCS_AGENT.AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT
  Stored Procedures:
    - SNOWFLAKE_DOCS_AGENT.AGENTS.SEND_ANSWER_EMAIL (if exists)
  Notification Integrations:
    - DOCS_AGENT_EMAIL_INT (if exists)
  Databases:
    - SNOWFLAKE_DOCS_AGENT (and all contained schemas/objects)
  Grants:
    - DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER revoked from PUBLIC

Script Sections:
  1. Remove Agent from Snowflake CoWork
  2. Drop Agent
  3. Drop Email Tool Objects (procedure + integration)
  4. Drop Agent Database
  5. Marketplace Database (kept in place)
  6. Revoke Account-Level Grants
====================================================================================================
*/

USE ROLE ACCOUNTADMIN;


-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 1: REMOVE AGENT FROM SNOWFLAKE COWORK                               ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║  Purpose: Unregister the agent from CoWork so it no longer appears in the    ║
-- ║           CoWork interface. Wrapped in a block to handle "not found" errors. ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

BEGIN
    ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
        DROP AGENT SNOWFLAKE_DOCS_AGENT.AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT;
    RETURN 'Agent removed from CoWork.';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'Agent was not in CoWork or CoWork object does not exist. (' || SQLERRM || ')';
END;


-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 2: DROP THE AGENT                                                   ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║  Purpose: Remove the Cortex Agent object. All committed versions and the     ║
-- ║           live version are permanently deleted.                              ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

DROP AGENT IF EXISTS SNOWFLAKE_DOCS_AGENT.AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT;


-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 3: DROP EMAIL TOOL OBJECTS                                          ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║  Purpose: Remove the email stored procedure and notification integration.    ║
-- ║           These only exist if 02b was used. IF EXISTS handles both cases.    ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

DROP PROCEDURE IF EXISTS SNOWFLAKE_DOCS_AGENT.AGENTS.SEND_ANSWER_EMAIL(VARCHAR, VARCHAR, VARCHAR);
DROP INTEGRATION IF EXISTS DOCS_AGENT_EMAIL_INT;


-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 4: DROP AGENT DATABASE                                              ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║  Purpose: Remove the SNOWFLAKE_DOCS_AGENT database and everything inside     ║
-- ║           it (schema, any remaining objects). CASCADE is implicit for DROP   ║
-- ║           DATABASE.                                                          ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

DROP DATABASE IF EXISTS SNOWFLAKE_DOCS_AGENT;


-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 5: MARKETPLACE DATABASE (KEPT IN PLACE)                             ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║  The SNOWFLAKE_DOCUMENTATION database (Cortex Knowledge Extension) is        ║
-- ║  intentionally NOT dropped. It's a shared Marketplace listing that may be    ║
-- ║  used by other agents or applications in your account.                       ║
-- ║                                                                              ║
-- ║  To remove it manually:                                                      ║
-- ║    DROP DATABASE IF EXISTS SNOWFLAKE_DOCUMENTATION;                          ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝


-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 6: REVOKE ACCOUNT-LEVEL GRANTS (OPTIONAL)                           ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║  The CORTEX_AGENT_USER database role is required by ALL Cortex Agents in     ║
-- ║  your account. Only revoke this if you have NO other agents that need it.    ║
-- ║  Uncomment the line below if you want to revoke it.                          ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

-- REVOKE DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER FROM ROLE PUBLIC;


-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  TEARDOWN COMPLETE                                                           ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║  All Snowflake Docs Agent objects have been removed.                         ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

SELECT 'Teardown complete. All Snowflake Docs Agent objects have been removed.' AS status