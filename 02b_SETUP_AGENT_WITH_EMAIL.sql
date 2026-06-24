/*
====================================================================================================
File Name: 02b_SETUP_AGENT_WITH_EMAIL.sql
====================================================================================================
Author:      Tom Meacham
Create Date: 2025-08-18
Last Updated: 2026-06-24
Version:     1.2
Description: Creates and deploys the "Snowflake Docs Agent" Cortex Agent WITH the email-answer
             tool, then registers it with Snowflake CoWork for account-wide visibility.

             This is the EMAIL variant. For the version WITHOUT the email tool, use
             02a_SETUP_AGENT.sql instead. Run ONE of 02a or 02b — not both.

             The email tool allows the agent to send its answer as a beautifully formatted HTML
             email to the current user. It includes a Python stored procedure that converts
             markdown to email-safe HTML and sends via SYSTEM$SEND_EMAIL.

Prerequisites:
  - 01_SETUP_ENVIRONMENT.sql has been executed successfully
  - ACCOUNTADMIN role (or equivalent privileges)
  - SNOWFLAKE_DOCS_AGENT database and AGENTS schema exist
  - SNOWFLAKE_DOCUMENTATION database is imported and accessible
  - Users who want to receive emails must have a verified email address in Snowflake

Objects Created:
  Notification Integration:
    - DOCS_AGENT_EMAIL_INT (account-level)
  Stored Procedures:
    - SNOWFLAKE_DOCS_AGENT.AGENTS.SEND_ANSWER_EMAIL(subject, content, recipient_email)
  Agents:
    - SNOWFLAKE_DOCS_AGENT.AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT
  Snowflake CoWork Object:
    - SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT (account-level, manages agent visibility)
  Grants:
    - USAGE on SEND_ANSWER_EMAIL → PUBLIC
    - USAGE on SNOWFLAKE_DOCUMENTATION_AGENT (agent) → PUBLIC
    - USAGE on SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT → PUBLIC

Script Sections:
  1. Create Email Notification Integration
  2. Create the SEND_ANSWER_EMAIL stored procedure
  3. Create and Deploy the Agent (with email tool in the spec)
  4. Add Agent to Snowflake CoWork
====================================================================================================
*/

USE ROLE ACCOUNTADMIN;
USE DATABASE SNOWFLAKE_DOCS_AGENT;
USE SCHEMA AGENTS;

-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 1: CREATE EMAIL NOTIFICATION INTEGRATION                            ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║  Purpose: Create the notification integration required by SYSTEM$SEND_EMAIL  ║
-- ║           to send HTML emails from the agent.                                ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

CREATE NOTIFICATION INTEGRATION IF NOT EXISTS DOCS_AGENT_EMAIL_INT
    TYPE = EMAIL
    ENABLED = TRUE
    COMMENT = 'Email integration for the Snowflake Docs Agent to send formatted answers.';

-- NOTE: We intentionally do NOT grant USAGE on this integration to PUBLIC.
-- The SEND_ANSWER_EMAIL procedure uses EXECUTE AS OWNER, so it inherits the
-- owner's (ACCOUNTADMIN) access to the integration. This keeps the email
-- integration locked down — only the procedure can use it, not users directly.

-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 2: CREATE THE EMAIL STORED PROCEDURE                                ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║  Purpose: A stored procedure the agent calls to send the answer as a nicely  ║
-- ║           formatted HTML email. The agent passes raw markdown — this proc    ║
-- ║           handles all markdown-to-HTML conversion internally.                ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE PROCEDURE AGENTS.SEND_ANSWER_EMAIL(
    SUBJECT VARCHAR,
    CONTENT VARCHAR,
    RECIPIENT_EMAIL VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
EXECUTE AS OWNER
AS
$$
import re
from snowflake.snowpark import Session


def markdown_to_html(md: str) -> str:
    """Convert markdown to email-safe HTML with inline styles only."""

    html = md
    html = html.replace('&', '&amp;')
    html = html.replace('<', '&lt;')
    html = html.replace('>', '&gt;')

    # Fenced code blocks (```lang\n...\n```)
    def replace_code_block(match):
        code = match.group(2).strip('\n')
        return (
            '<table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:16px 0;">'
            '<tr><td style="background-color:#f1f5f9;border:1px solid #e2e8f0;border-radius:8px;'
            'padding:16px;font-family:Courier New,Courier,monospace;font-size:13px;line-height:1.5;'
            f'color:#1e293b;white-space:pre-wrap;word-wrap:break-word;">{code}</td></tr></table>'
        )
    html = re.sub(r'```(\w*)\n?(.*?)```', replace_code_block, html, flags=re.DOTALL)

    # Inline code
    html = re.sub(
        r'`([^`]+)`',
        r'<code style="background-color:#f1f5f9;border:1px solid #e2e8f0;border-radius:4px;'
        r'padding:2px 6px;font-family:Courier New,Courier,monospace;font-size:13px;'
        r'color:#1e293b;">\1</code>',
        html
    )

    # Headings (process h4 before h3 before h2 before h1 to avoid partial matches)
    html = re.sub(
        r'^#### (.+)$',
        r'<h4 style="font-family:Arial,Helvetica,sans-serif;font-size:15px;font-weight:600;'
        r'color:#1e293b;margin:20px 0 6px 0;padding:0;">\1</h4>',
        html, flags=re.MULTILINE
    )
    html = re.sub(
        r'^### (.+)$',
        r'<h3 style="font-family:Arial,Helvetica,sans-serif;font-size:16px;font-weight:600;'
        r'color:#1e293b;margin:24px 0 8px 0;padding:0;">\1</h3>',
        html, flags=re.MULTILINE
    )
    html = re.sub(
        r'^## (.+)$',
        r'<h2 style="font-family:Arial,Helvetica,sans-serif;font-size:18px;font-weight:600;'
        r'color:#1e293b;margin:28px 0 10px 0;padding:0;">\1</h2>',
        html, flags=re.MULTILINE
    )
    html = re.sub(
        r'^# (.+)$',
        r'<h1 style="font-family:Arial,Helvetica,sans-serif;font-size:22px;font-weight:600;'
        r'color:#1e293b;margin:32px 0 12px 0;padding:0;">\1</h1>',
        html, flags=re.MULTILINE
    )

    # Bold and italic
    html = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', html)
    html = re.sub(r'__(.+?)__', r'<strong>\1</strong>', html)
    html = re.sub(r'\*(.+?)\*', r'<em>\1</em>', html)
    html = re.sub(r'(?<![_])_([^_]+)_(?![_])', r'<em>\1</em>', html)

    # Links
    html = re.sub(
        r'\[([^\]]+)\]\(([^)]+)\)',
        r'<a href="\2" style="color:#29B5E8;text-decoration:underline;">\1</a>',
        html
    )

    # Horizontal rules
    html = re.sub(
        r'^[-*_]{3,}\s*$',
        '<table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:24px 0;">'
        '<tr><td style="border-top:1px solid #e2e8f0;font-size:0;line-height:0;">&nbsp;</td></tr></table>',
        html, flags=re.MULTILINE
    )

    # Unordered lists
    def replace_ul(match):
        items = re.findall(r'^[*\-+] (.+)$', match.group(0), re.MULTILINE)
        li = ''.join(
            f'<li style="font-family:Arial,Helvetica,sans-serif;font-size:15px;'
            f'line-height:1.7;color:#374151;margin:4px 0;">{item}</li>'
            for item in items
        )
        return f'<ul style="margin:12px 0;padding-left:24px;list-style-type:disc;">{li}</ul>'
    html = re.sub(r'(^[*\-+] .+$\n?)+', replace_ul, html, flags=re.MULTILINE)

    # Ordered lists
    def replace_ol(match):
        items = re.findall(r'^\d+\. (.+)$', match.group(0), re.MULTILINE)
        li = ''.join(
            f'<li style="font-family:Arial,Helvetica,sans-serif;font-size:15px;'
            f'line-height:1.7;color:#374151;margin:4px 0;">{item}</li>'
            for item in items
        )
        return f'<ol style="margin:12px 0;padding-left:24px;list-style-type:decimal;">{li}</ol>'
    html = re.sub(r'(^\d+\. .+$\n?)+', replace_ol, html, flags=re.MULTILINE)

    # Blockquotes
    def replace_blockquote(match):
        content = re.sub(r'^&gt;\s?', '', match.group(0), flags=re.MULTILINE).strip()
        return (
            '<table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:12px 0;">'
            '<tr><td style="border-left:4px solid #29B5E8;padding:8px 16px;'
            'font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:1.7;'
            f'color:#555555;font-style:italic;">{content}</td></tr></table>'
        )
    html = re.sub(r'(^&gt;.*$\n?)+', replace_blockquote, html, flags=re.MULTILINE)

    # Markdown tables (| col | col |)
    def replace_table(match):
        lines = [l.strip() for l in match.group(0).strip().split('\n') if l.strip()]
        if len(lines) < 2:
            return match.group(0)
        # Parse header
        headers = [c.strip() for c in lines[0].strip('|').split('|')]
        # Skip separator line (line with dashes)
        data_lines = [l for l in lines[2:] if not re.match(r'^[\s|:-]+$', l)]
        
        th_style = ('font-family:Arial,Helvetica,sans-serif;font-size:13px;font-weight:600;'
                    'color:#1e293b;padding:10px 12px;border-bottom:2px solid #e2e8f0;'
                    'text-align:left;background-color:#f8fafc;')
        td_style = ('font-family:Arial,Helvetica,sans-serif;font-size:13px;'
                    'color:#374151;padding:8px 12px;border-bottom:1px solid #e2e8f0;')
        
        header_html = ''.join(f'<th style="{th_style}">{h}</th>' for h in headers)
        rows_html = ''
        for row_line in data_lines:
            cells = [c.strip() for c in row_line.strip('|').split('|')]
            rows_html += '<tr>' + ''.join(f'<td style="{td_style}">{c}</td>' for c in cells) + '</tr>'
        
        return (
            '<table width="100%" cellpadding="0" cellspacing="0" border="0" '
            'style="margin:16px 0;border:1px solid #e2e8f0;border-radius:8px;border-collapse:collapse;">'
            f'<tr>{header_html}</tr>{rows_html}</table>'
        )
    html = re.sub(r'(^\|.+\|$\n?)+', replace_table, html, flags=re.MULTILINE)

    # Paragraphs — split on double newlines
    parts = re.split(r'\n{2,}', html)
    processed = []
    for part in parts:
        part = part.strip()
        if not part:
            continue
        if re.match(r'^<(table|h[1-6]|ul|ol|pre|blockquote|code)', part):
            processed.append(part)
        else:
            part = part.replace('\n', '<br>')
            processed.append(
                f'<p style="font-family:Arial,Helvetica,sans-serif;font-size:15px;'
                f'line-height:1.7;color:#374151;margin:12px 0;padding:0;">{part}</p>'
            )
    return ''.join(processed)


def build_email_html(body_html: str, subject: str) -> str:
    """Wrap body in a full email template — inline CSS, table layout, email-client safe."""
    return f'''<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>{subject}</title>
<!--[if mso]>
<noscript><xml><o:OfficeDocumentSettings><o:PixelsPerInch>96</o:PixelsPerInch></o:OfficeDocumentSettings></xml></noscript>
<![endif]-->
</head>
<body style="margin:0;padding:0;background-color:#f4f6f9;width:100%;-webkit-text-size-adjust:100%;-ms-text-size-adjust:100%;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#f4f6f9;">
<tr>
<td align="center" style="padding:32px 16px;">
<!--[if mso]><table role="presentation" width="780" cellpadding="0" cellspacing="0" border="0"><tr><td><![endif]-->
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:780px;background-color:#ffffff;border-radius:12px;overflow:hidden;border:1px solid #e2e8f0;">
<!-- Header -->
<tr>
<td style="background-color:#29B5E8;padding:28px 32px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
<tr>
<td style="font-family:Arial,Helvetica,sans-serif;font-size:20px;font-weight:700;color:#ffffff;letter-spacing:-0.3px;">
&#10052; Snowflake Docs Agent
</td>
</tr>
<tr>
<td style="font-family:Arial,Helvetica,sans-serif;font-size:13px;color:rgba(255,255,255,0.85);padding-top:6px;">
Your answer is ready
</td>
</tr>
</table>
</td>
</tr>
<!-- Subject -->
<tr>
<td style="padding:28px 32px 0 32px;">
<h1 style="margin:0;font-family:Arial,Helvetica,sans-serif;font-size:22px;font-weight:600;color:#1e293b;line-height:1.3;">{subject}</h1>
</td>
</tr>
<!-- Body -->
<tr>
<td style="padding:20px 32px 32px 32px;">
{body_html}
</td>
</tr>
<!-- Footer -->
<tr>
<td style="padding:20px 32px;border-top:1px solid #e5e7eb;background-color:#f9fafb;">
<p style="margin:0;font-family:Arial,Helvetica,sans-serif;font-size:12px;color:#6b7280;line-height:1.5;">
This email was sent by the <strong>Snowflake Docs Agent</strong> at your request.<br>
Powered by Snowflake Cortex AI &bull; <a href="https://ai.snowflake.com" style="color:#29B5E8;text-decoration:none;">Open Snowflake CoWork</a>
</p>
</td>
</tr>
</table>
<!--[if mso]></td></tr></table><![endif]-->
</td>
</tr>
</table>
</body>
</html>'''


def main(session: Session, SUBJECT: str, CONTENT: str, RECIPIENT_EMAIL: str) -> str:
    """Convert markdown answer to HTML and send as email to the current user only."""

    if not CONTENT or not CONTENT.strip():
        return 'ERROR: No content provided. Please pass the full answer text in the CONTENT parameter so I can format and send it.'

    # Resolve current user's email — this is the ONLY allowed recipient
    try:
        user_result = session.sql("SELECT CURRENT_USER() AS u").collect()
        current_user = user_result[0]['U'] if user_result else None
        
        email_result = session.sql(
            f"SELECT EMAIL FROM SNOWFLAKE.ACCOUNT_USAGE.USERS WHERE NAME = '{current_user}' LIMIT 1"
        ).collect()
        
        if email_result and email_result[0]['EMAIL']:
            recipient = email_result[0]['EMAIL']
        else:
            return (
                'ERROR: No email address found for your Snowflake user account. '
                'Please add an email address in Snowsight under your profile settings, '
                'then verify it before trying again.'
            )
    except Exception as e:
        # Fallback: use RECIPIENT_EMAIL if account_usage lookup fails (permissions)
        if RECIPIENT_EMAIL and RECIPIENT_EMAIL.strip():
            recipient = RECIPIENT_EMAIL.strip()
        else:
            return (
                'ERROR: Could not look up your email address and none was provided. '
                f'Technical detail: {str(e)}'
            )

    # Security: reject sending to a different user
    if RECIPIENT_EMAIL and RECIPIENT_EMAIL.strip():
        provided = RECIPIENT_EMAIL.strip().lower()
        if provided != recipient.lower():
            return (
                f'REJECTED: For security, emails can only be sent to your own address ({recipient}). '
                f'Sending to other recipients ({RECIPIENT_EMAIL.strip()}) is not allowed.'
            )

    subject = SUBJECT.strip() if SUBJECT and SUBJECT.strip() else 'Snowflake Docs Agent - Your Answer'

    # Convert markdown to email-safe HTML
    body_html = markdown_to_html(CONTENT.strip())
    full_html = build_email_html(body_html, subject)

    # Escape for SQL
    escaped_html = full_html.replace("'", "''")
    escaped_subject = subject.replace("'", "''")
    escaped_recipient = recipient.replace("'", "''")

    send_sql = f"""
        CALL SYSTEM$SEND_EMAIL(
            'DOCS_AGENT_EMAIL_INT',
            '{escaped_recipient}',
            '{escaped_subject}',
            '{escaped_html}',
            'text/html'
        )
    """

    try:
        session.sql(send_sql).collect()
        return (
            f'SUCCESS: Email sent to {recipient} with subject "{subject}". '
            f'The answer has been formatted as a styled HTML email. '
            f'Let the user know to check their inbox (and spam folder if not found within a minute).'
        )
    except Exception as e:
        msg = str(e)
        if 'not verified' in msg.lower() or 'verified' in msg.lower():
            return (
                f'ERROR: Email delivery failed because {recipient} is not a verified email address in Snowflake. '
                f'The user needs to verify their email: go to Snowsight > click username (top-left) > '
                f'Profile > verify the email address. Then try again.'
            )
        if 'integration' in msg.lower() or 'DOCS_AGENT_EMAIL_INT' in msg:
            return (
                'ERROR: The email notification integration (DOCS_AGENT_EMAIL_INT) is not accessible. '
                'An administrator needs to ensure the integration exists and USAGE is granted. '
                f'Technical detail: {msg}'
            )
        return (
            f'ERROR: Email delivery failed. This may be a temporary issue. '
            f'Technical detail: {msg}'
        )
$$;

GRANT USAGE ON PROCEDURE AGENTS.SEND_ANSWER_EMAIL(VARCHAR, VARCHAR, VARCHAR) TO ROLE PUBLIC;

-- Validate: Test the procedure (optional — replace with your verified email)
-- CALL AGENTS.SEND_ANSWER_EMAIL(
--     'Test: Dynamic Tables Overview',
--     'Dynamic Tables are declarative data pipelines in Snowflake...',
--     'your.email@example.com'
-- );

-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 3: CREATE AND DEPLOY THE AGENT (WITH EMAIL TOOL)                    ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║  Purpose: Define, create, and configure the "Snowflake Docs Agent" with      ║
-- ║           both the Cortex Search tool and the Email Answer tool.              ║
-- ║                                                                              ║
-- ║  Versioning Strategy:                                                        ║
-- ║    - CREATE IF NOT EXISTS ensures the agent is only created on first run.    ║
-- ║    - ALTER AGENT MODIFY LIVE VERSION updates the spec on every re-run.       ║
-- ║    - ALTER AGENT COMMIT creates an immutable VERSION$N snapshot.             ║
-- ║    - Previous versions are preserved for rollback.                           ║
-- ║                                                                              ║
-- ║  Agent: SNOWFLAKE_DOCS_AGENT.AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT            ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

-- Step 3.1: Create the agent (first run only)
CREATE AGENT IF NOT EXISTS AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT
    COMMENT=$$This agent is an expert at answering questions related to Snowflake.$$
FROM SPECIFICATION $$
models:
  orchestration: auto
instructions:
  response: |
    You are Snowflake Sherpa, a Snowflake expert AI.
$$;

-- Step 3.2: Update the agent metadata (profile and comment)
ALTER AGENT AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT
    SET COMMENT = $$This agent is an expert at answering questions related to Snowflake.$$,
        PROFILE = '{"display_name": "Snowflake Docs Agent", "avatar": "LightbulbIcon", "color": "var(--chartDim_1-x11ij0mo)"}';

-- Step 3.3: Ensure a live version exists for modification
BEGIN
    ALTER AGENT AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT ADD LIVE VERSION FROM LAST;
    RETURN 'Live version created from last committed version.';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'Live version already exists; ready for modification. (' || SQLERRM || ')';
END;

-- Step 3.4: Update the live version with the full specification (includes email tool)
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

    ## 3. Response Format
    **Every response MUST include these core sections:**

    ### Answer
    A clear, direct response to the question. Lead with the key fact or recommendation. Minimum 1-2 sentences.

    ### Explanation
    Essential context that expands on the answer. Provide background, how the feature works, and relevant details.

    **Include these optional sections ONLY when they add substantive value (never include just to say N/A or not applicable):**

    ### Code Example
    Provide working code demonstrating the concept.
    - Use correct language identifier (e.g., sql, python)
    - Comments explain the why (logic and intent), not the what (syntax)
    - Ensure code is complete and runnable

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

    ### Access Control & Privileges
    Include when the question involves operations that require specific privileges or roles.

    **Format your response as:**
    1. **Snowflake Database Roles:** List any required Snowflake database roles (e.g., CORTEX_USER, GOVERNANCE_VIEWER, DATA_METRIC_USER)
    2. **Account-level Roles:** Specify if ACCOUNTADMIN, SECURITYADMIN, SYSADMIN, or USERADMIN is required
    3. **Object Privileges:** List specific privileges needed (e.g., USAGE, SELECT, CREATE TABLE, EXECUTE TASK, OPERATE)
    4. **Object Access:** Specify required access to databases, schemas, warehouses, or other objects

    ### Considerations
    Include when there are meaningful limitations, costs, performance implications, or best practices the user should know about.

    ## 4. Completeness Requirements
    Before finalizing your response, ensure:
    - The full question is answered. If a user asks multiple things, address each part explicitly.
    - Code examples are complete, not partial snippets.
    - Common edge cases or variations are mentioned when relevant.

    ## 5. Email Tool
    After providing your answer, always offer to email the answer to the user with a brief closing line like "Would you like me to email this answer to you?"

    When the user says yes, use the Send_Answer_Email tool with:
    - subject: A descriptive subject line
    - content: Your full answer exactly as you wrote it (in markdown). The procedure handles all HTML formatting automatically.
    - recipient_email: Use the user's email from the context metadata provided in the system reminders.

    Relay the procedure's return message to the user.

    Security rule: Only send emails to the current user. If the user asks to send to a different email address, politely decline. Say: "For security, I can only email answers to your own verified address. I'm not able to send to other recipients."

  orchestration: |
    ## 1. Core Directive
    Mission: Provide accurate, complete answers grounded in documentation with working code examples when applicable.

    Critical Rules:
    - Always search documentation before answering technical questions.
    - Never invent features, syntax, or capabilities.

    ## 2. Tool Selection & Usage
    - Use Cortex Search for how-to questions, feature explanations, syntax, and best practices.
    - Use Send_Answer_Email when the user requests their answer be emailed to them.
    - If search returns low-relevance results, rephrase the query and retry before stating uncertainty.
    - For ambiguous terms (e.g., "streams", "tasks"), state your interpretation, then search accordingly.
    - Perform additional searches when the initial results don't fully cover the question.
    - Search for related concepts. If a user asks about Dynamic Tables, also search for refresh modes, lag settings, and monitoring.
    - Cross-reference results. If multiple docs are returned, synthesize information from all relevant sources, not just the first result.

    ## 3. Task Sequencing
    - Ambiguous queries: If the query is ambiguous, provide your best interpretation and answer it, then note the alternative interpretation at the end.
    - Low confidence: If retrieved docs do not address the question, say so and suggest rephrasing or a related topic.
    - Complex procedures: Break down into numbered steps.

    ## 4. Guardrails
    - Scope: Snowflake topics only. For third-party integrations, use only what is documented.
    - No speculation: Do not speculate on unreleased features or offer opinions.
    - Security: Only recommend documented security practices. Do not advise disabling security features.
    - Prefer latest patterns: Always use the most recent documented API patterns and syntax. Avoid deprecated methods.
    - Grounding requirement: Only state facts directly supported by retrieved documentation. If your search results do not contain the answer, respond with: "I couldn't find this in the Snowflake documentation. Try rephrasing your question or asking about a related topic."

    ## 5. Email Tool Usage
    - When the user asks to email the answer, use the Send_Answer_Email tool.
    - For recipient_email, use the user's email from the context metadata (provided in the system reminders at the start of the conversation). Do NOT ask the user for their email. You already have it.
    - Security: NEVER send to a different address. If asked to forward to someone else, decline politely.
    - Pass your answer as-is in the content parameter (raw markdown). The stored procedure converts it to a beautifully formatted HTML email automatically.
    - Relay the return message from the procedure to the user (it contains clear success/error guidance).

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
  - tool_spec:
      type: generic
      name: Send_Answer_Email
      description: >
        Use this tool to email the agent's answer to the user. Pass your raw markdown answer
        in the content parameter. The procedure converts it to a styled HTML email and sends
        it to the current user's verified email address.
      input_schema:
        type: object
        properties:
          SUBJECT:
            type: string
            description: A concise email subject line summarizing the topic
          CONTENT:
            type: string
            description: The full answer in markdown format exactly as you wrote it. The procedure handles all formatting.
          RECIPIENT_EMAIL:
            type: string
            description: The user's email address from the context metadata in system reminders.
        required:
          - SUBJECT
          - CONTENT
          - RECIPIENT_EMAIL

tool_resources:
  Snowflake_Documentation_Tool:
    id_column: SOURCE_URL
    max_results: 5
    search_service: SNOWFLAKE_DOCUMENTATION.SHARED.CKE_SNOWFLAKE_DOCS_SERVICE
    title_column: DOCUMENT_TITLE
  Send_Answer_Email:
    type: procedure
    identifier: SNOWFLAKE_DOCS_AGENT.AGENTS.SEND_ANSWER_EMAIL
    execution_environment:
      type: warehouse
$$;

-- Step 3.5: Commit the live version
ALTER AGENT AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT COMMIT COMMENT = 'Agent with email tool';

-- Recreate the live version so the Snowsight test UI remains functional
ALTER AGENT AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT ADD LIVE VERSION FROM LAST;

-- Grant usage of this agent to the PUBLIC role
GRANT USAGE ON AGENT AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT TO ROLE PUBLIC;

-- Validate grants
SHOW GRANTS ON AGENT AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT;


-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 4: ADD AGENT TO SNOWFLAKE COWORK                                    ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║  Purpose: Register the agent with the Snowflake CoWork object so it          ║
-- ║           appears in the CoWork interface for all users.                     ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

-- Create the Snowflake CoWork object (if it doesn't already exist)
CREATE SNOWFLAKE INTELLIGENCE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;

-- Add the agent to the CoWork object
BEGIN
    ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
        ADD AGENT SNOWFLAKE_DOCS_AGENT.AGENTS.SNOWFLAKE_DOCUMENTATION_AGENT;
    RETURN 'Agent added to CoWork object successfully.';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'Agent is already present in the CoWork object; safe to continue. (' || SQLERRM || ')';
END;

-- Grant USAGE on the CoWork object to PUBLIC
GRANT USAGE ON SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT TO ROLE PUBLIC;

-- Validate
SHOW SNOWFLAKE INTELLIGENCES;


-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  POST-EXECUTION: ACCESS YOUR AGENT                                           ║
-- ╠══════════════════════════════════════════════════════════════════════════════╣
-- ║  Your agent is now ready! The query below provides your account identifier   ║
-- ║  and the URLs to access Snowflake CoWork.                                    ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

SELECT 
CONCAT(CURRENT_ORGANIZATION_NAME(),'-',CURRENT_ACCOUNT_NAME()) as account_identifier,
'https://ai.snowflake.com' as cowork_url,
LOWER(CONCAT('https://ai.snowflake.com/'||current_organization_name()||'/'||current_account_name()||'/#/ai')) as cowork_url_direct,
CONCAT('https://ai.snowflake.com/'||LOWER(current_organization_name())||'/'||LOWER(current_account_name())||'/#/ai/chat/new?db=SNOWFLAKE_DOCS_AGENT&schema=AGENTS&agent=SNOWFLAKE_DOCUMENTATION_AGENT') as agent_direct_url;
