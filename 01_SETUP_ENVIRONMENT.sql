/*
====================================================================================================
File Name: 01_SETUP_ENVIRONMENT.sql
====================================================================================================
Author:      Tom Meacham
Create Date: 2025-08-18
Last Updated: 2026-06-23
Version:     1.1
Description: This script sets up the foundational environment for the Snowflake Docs Agent.
             It configures account-level settings, creates the agent database and schema,
             and installs the Snowflake Documentation Cortex Knowledge Extension from the
             Marketplace. Run this script before 02_SETUP_AGENT.sql.

Prerequisites:
  - ACCOUNTADMIN role (or equivalent privileges)
  - Access to the Snowflake Marketplace — your organization must have accepted the
    Snowflake Provider and Consumer Terms of Service BEFORE running this script.
    If not yet accepted, an ORGADMIN must do so first:
    https://other-docs.snowflake.com/en/collaboration/consumer-becoming#accept-the-snowflake-provider-and-consumer-terms
  - A warehouse available for the executing user
  - Cross-region inference enabled (or willingness to enable it for model availability)

Objects Created:
  Databases:
    - SNOWFLAKE_DOCS_AGENT          — Hosts the agent and its schema
    - SNOWFLAKE_DOCUMENTATION       — Imported from Marketplace listing (read-only shared data)
  Schemas:
    - SNOWFLAKE_DOCS_AGENT.AGENTS   — Contains the agent object
  Grants:
    - USAGE on SNOWFLAKE_DOCS_AGENT (database) → PUBLIC
    - USAGE on SNOWFLAKE_DOCS_AGENT.AGENTS (schema) → PUBLIC
    - IMPORTED PRIVILEGES on SNOWFLAKE_DOCUMENTATION → PUBLIC
    - DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER → PUBLIC

Script Sections:
  1. Configure Account & Create Agent Database:
     - Validates cross-region inference settings for model availability.
     - Creates the SNOWFLAKE_DOCS_AGENT database and `agents` schema to host the agent.
  2. Install Snowflake Documentation Cortex Extension:
     - Installs the "Snowflake Documentation Cortex Knowledge Extension" Native App from the
       Snowflake Marketplace. This creates the `SNOWFLAKE_DOCUMENTATION` database, which serves
       as the vectorized knowledge base for the agent.
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
-- ║           that will host the Snowflake Docs Agent.                           ║
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
    '✅ Snowflake Documentation CKE is already imported. Run the next query to verify the database name is SNOWFLAKE_DOCUMENTATION.', 
    '✅ Listing is available and has not yet been imported. Proceed to Step 3 to create the database.'
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
    '✅ Snowflake Documentation CKE correctly named SNOWFLAKE_DOCUMENTATION.', 
    '⚠️ Consider renaming this database to SNOWFLAKE_DOCUMENTATION or dropping it and reimporting with the command in Step 3.'
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
Note: For databases created from Marketplace listings, Snowflake stores/displays
IMPORTED PRIVILEGES as USAGE in the SHOW GRANTS output. The query below checks for
either value to correctly report success.
====================================================================================================
*/
SHOW GRANTS ON DATABASE SNOWFLAKE_DOCUMENTATION ->>
SELECT 
    "privilege" AS privilege,
    "name" AS "DATABASE",
    "grantee_name" AS "ROLE",
    CASE 
        WHEN "grantee_name" = 'PUBLIC' AND "privilege" = 'USAGE'
        THEN '✅ VALID - IMPORTED PRIVILEGES has been granted to the Public Role'
        ELSE '⚠️ INVALID - Run: GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_DOCUMENTATION TO ROLE PUBLIC;'
    END AS validation_result
FROM $1
WHERE "grantee_name" = 'PUBLIC';


-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  OPTIONAL: SET DEFAULT WAREHOUSE FOR USERS                                   ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║  CoWork requires each user to have a default warehouse set. Users without    ║
-- ║  one will see errors when trying to use agents. The queries below help       ║
-- ║  identify and fix users who are missing a default warehouse.                 ║
-- ║                                                                              ║
-- ║  Note: There is no account-level parameter to set a default warehouse for    ║
-- ║        all users — it must be set per user via ALTER USER.                   ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

/*
====================================================================================================
Diagnostic: Show users without a default warehouse
====================================================================================================
*/
SHOW USERS ->>
SELECT "name", "login_name", "default_warehouse", "default_role"
FROM $1
WHERE "default_warehouse" IS NULL OR "default_warehouse" = '';

/*
====================================================================================================
Fix: Set a default warehouse for all users who don't have one
====================================================================================================
Uses ASYNC to run each ALTER USER concurrently for faster execution.
Replace '<YOUR_WAREHOUSE>' with the warehouse you want to assign.

Why ASYNC? Without it, each ALTER USER runs sequentially — fine for a few users, but slow
for accounts with hundreds. ASYNC fires all ALTER statements as concurrent child jobs,
then AWAIT ALL waits for them to finish. Since each ALTER USER is independent metadata-only
operation, this is safe and significantly faster at scale.

Tip: If available in your region, consider using an Adaptive Warehouse as the default.
     Adaptive Warehouses automatically scale resources per-query, eliminating the need to
     manage warehouse size, multi-cluster settings, suspend/resume policies, or QAS config.
     They are ideal as a shared default because they handle mixed workloads (BI, ETL, ad-hoc)
     without manual tuning, and you only pay for actual query compute used.

     Create one with: CREATE ADAPTIVE WAREHOUSE COWORK_WH;
     Docs: https://docs.snowflake.com/en/user-guide/warehouses-adaptive

     Requirements: Enterprise Edition, select AWS regions only.

     Otherwise, a Small warehouse works fine for CoWork — agent queries are lightweight.
     Users can always override their default warehouse per-session with USE WAREHOUSE
     or in their Snowsight profile settings.
====================================================================================================
*/
-- BEGIN
--     LET counter INTEGER := 0;
--     LET warehouse_name VARCHAR := '<WAREHOUSE_NAME>';
--     SHOW USERS;
--     LET rs RESULTSET := (
--         SELECT "name" AS username
--         FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
--         WHERE "default_warehouse" IS NULL OR "default_warehouse" = ''
--     );
--     FOR record IN rs DO
--         LET alter_stmt VARCHAR := 'ALTER USER "' || record.username || '" SET DEFAULT_WAREHOUSE = ''' || UPPER(:warehouse_name) || '''';
--         ASYNC (EXECUTE IMMEDIATE :alter_stmt);
--         counter := counter + 1;
--     END FOR;
--     AWAIT ALL;
--     RETURN counter || ' user(s) updated with default warehouse: ' || UPPER(:warehouse_name);
-- END;