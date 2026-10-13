# Org Monitoring — Salesforce Implementation Specification

**Version:** 1.0  
**Date:** October 13, 2026  
**Status:** Implementation handoff for Claude  
**Platform:** Salesforce Lightning Web Components (LWC), Apex, Custom Objects, Scheduled Apex

## 1. Implementation instruction to Claude

Implement a production-quality, metadata-deployable Salesforce solution called **Org Monitoring** following this specification. Deliver source code, object/field metadata, picklist metadata, permission set, Lightning App Page (FlexiPage), Apex unit tests, LWC tests where feasible, and deployment/setup instructions. Follow established layered Apex design: thin controller → service/domain layer → selector (SOQL) and repository (DML). Avoid SOQL/DML in loops. Use Salesforce Lightning Design System (SLDS). Do not merely describe the solution; generate deployable code. If a platform constraint prevents an exact requirement, explain the constraint and implement the closest safe equivalent. Preserve the distinction between actual readings and simulated demo readings.

## 2. Scope and objectives

- Monitor **all available organization limits** returned by `System.OrgLimits.getMap()`, not solely API limits. Availability and semantics vary by org and Salesforce release; do not assume every illustrative limit exists.
- Evaluate the percentage consumed for each valid returned limit on a configurable schedule.
- Persist a historical snapshot for **every valid limit on every scheduled monitoring run**, including Normal readings.
- Send a single consolidated HTML email when one or more limits meet Warning or Critical thresholds, provided recipients are configured.
- Provide an Org Monitoring Lightning App Page with editable configuration, current/latest status, and historical readings.
- Purge historical readings according to a configurable retention policy, including **Keep Forever**.
- Expose a Lightning App Builder **Demo Mode** property to display five randomly selected simulated limit readings with at least one Warning and at least one Critical, without affecting production data, emails, or jobs.

### Explicit non-goals for v1

- External callouts, third-party monitoring systems, or paid services.
- Monitoring limits that `System.OrgLimits.getMap()` does not expose.
- Automatic remediation when limits exceed thresholds.
- Sending demo-mode emails or storing demo readings as real monitoring data.

## 3. Naming conventions

| Artifact                                         | Name / API name                                         |
| ------------------------------------------------ | ------------------------------------------------------- |
| Lightning App Page                               | Org Monitoring                                          |
| Config custom object                             | `Org_Monitoring_Configuration__c`                       |
| History custom object                            | `Org_Limit__c`                                          |
| Optional run summary custom object (recommended) | `Org_Monitoring_Run__c`                                 |
| Configuration LWC                                | `orgMonitoringConfiguration`                            |
| Dashboard LWC                                    | `orgMonitoringDashboard`                                |
| Optional host/parent LWC                         | `orgMonitoringApp`                                      |
| UI Apex controller                               | `OrgMonitoringController`                               |
| Core service                                     | `OrgMonitoringService`                                  |
| Configuration service                            | `OrgMonitoringConfigService`                            |
| Limits provider abstraction                      | `OrgLimitsProvider`                                     |
| Demo provider                                    | `OrgMonitoringDemoProvider` (or client-only equivalent) |
| Read/selector class                              | `OrgLimitSelector`                                      |
| Write/repository class                           | `OrgLimitRepository`                                    |
| Scheduler                                        | `OrgMonitoringScheduler`                                |
| Schedule management                              | `OrgMonitoringScheduleService`                          |
| Notification service                             | `OrgMonitoringEmailService`                             |
| Purge job                                        | `OrgMonitoringPurgeJob`                                 |
| Permission set                                   | `Org_Monitoring_Administrator`                          |

Do not use “API Monitoring” / “API Limits” in UI headings, labels, classes, or metadata unless referring specifically to an individual API-related org limit.

## 4. Configuration object schema

Use a **Custom Object**, not Custom Metadata. Label: **Org Monitoring Configuration**; API name: `Org_Monitoring_Configuration__c`. Create exactly one canonical configuration with `Name = Default`, created during setup/initialization if not present. The application must not accidentally create duplicates; use a robust unique identifier (for example a unique `Configuration_Key__c` text field containing `DEFAULT`) and an authorized initialization path. Only a single configuration is supported in v1.

| Field label            | Proposed API name           | Type                                    | Default / validation                                                                                              |
| ---------------------- | --------------------------- | --------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Name                   | `Name`                      | Text (standard record name)             | `Default`                                                                                                         |
| Configuration Key      | `Configuration_Key__c`      | Text(30), Unique                        | `DEFAULT`; singleton enforcement                                                                                  |
| Warning Percent Value  | `Warning_Percent_Value__c`  | Number(5,2)                             | 70.00; 0–100                                                                                                      |
| Critical Percent Value | `Critical_Percent_Value__c` | Number(5,2)                             | 90.00; > Warning and <= 100                                                                                       |
| Active                 | `Active__c`                 | Checkbox                                | true                                                                                                              |
| Email Addresses        | `Email_Addresses__c`        | Long Text Area                          | blank; comma-separated addresses                                                                                  |
| Comments               | `Comments__c`               | Long Text Area                          | blank                                                                                                             |
| Time Offset (Minutes)  | `Time_Offset_Minutes__c`    | Number(4,0)                             | 0; number of minutes after local midnight                                                                         |
| Days to Run            | `Days_to_Run__c`            | Text(50)                                | e.g. `SUN;MON;TUE;WED;THU;FRI;SAT`; use a normalized canonical order                                              |
| Frequency (Hours)      | `Frequency_Hours__c`        | Picklist                                | `1`, `2`, `4`, `6`, `8`, `12`, `24`; `24` means once/day                                                          |
| Retention Period       | `Retention_Period__c`       | Picklist                                | `30`, `60`, `90`, `120`, `FOREVER` (label Keep Forever); default 90                                               |
| Scheduling Time Zone   | `Scheduling_Time_Zone__c`   | Text(80) or supported timezone selector | Set to an explicitly chosen Salesforce-compatible timezone; do not implicitly assume each viewing user’s timezone |

**Time-offset constraint:** To guarantee exactly `24 / Frequency_Hours__c` runs on each selected day, use an integer offset in minutes satisfying `0 <= offset < frequency * 60`. This is stricter than 0–1439 and prevents late offsets from yielding a truncated daily schedule. Example: 12-hour frequency + 90-minute offset → 01:30 and 13:30 in the configured timezone. Once/day + 90-minute offset → 01:30. For a 1-hour frequency, allowed offset 0–59 minutes.

**Time zone and DST:** Apex `System.schedule` interprets CRON in the scheduling user’s timezone. Document and enforce the chosen timezone (for example, schedule through a designated admin user whose timezone matches the configuration). If an arbitrary configuration timezone cannot be guaranteed safely, constrain configuration to the scheduler user’s timezone and display it read-only. Test DST transitions and explain the behavior.

### Validation rules

1. Warning within 0–100; Critical > Warning and <= 100; both required.
2. When Active is true, at least one day is selected; restrict day tokens to SUN–SAT, unique, ordered.
3. Frequency must be one of the seven supported values.
4. Offset must be whole minutes and less than frequency in minutes.
5. Validate each nonempty comma-separated recipient; trim whitespace, deduplicate case-insensitively, reject invalid entries; blank is allowed and suppresses email.
6. Retention must be one of 30/60/90/120/FOREVER.
7. Validate and normalize server-side even when LWC validates client-side.
8. Only authorized administrators can edit configuration and manage schedules.

## 5. Lightning App Page and LWCs

Create a dedicated **Org Monitoring** Lightning App Page (FlexiPage), with separate modular LWCs.

### 5.1 `orgMonitoringConfiguration`

At the top, show the `Default` configuration in a concise summary: Warning %, Critical %, Active, Days to Run, Frequency, Time Offset and its explanation, Retention Period, and scheduling timezone. Show Comments if useful. The form includes:

- Sunday-to-Saturday **seven side-by-side checkboxes** (responsive wrap on narrow screens).
- Warning / Critical percentage inputs, Active toggle, frequency and retention picklists, offset minutes, comments.
- Email Addresses multiline input with comma-separated parsing and inline errors.
- **Submit** button. Show success/error messages and current schedule details.

Submit flow: validate client-side → Apex revalidate → persist configuration → reconcile owned scheduled monitoring job(s), using an explicit error/recovery strategy. Save and scheduling cannot be treated as a single atomic cross-transaction action without compensating logic; report partial failures accurately and allow safe retries. Do not create duplicate jobs. Disabling Active must cancel owned monitoring schedules without deleting history. Purge scheduling is independent from the monitoring Active flag.

### 5.2 `orgMonitoringDashboard`

Display:

- Latest sampling timestamp and next scheduled run, or an informative idle/disabled status.
- Count of Normal / Warning / Critical latest readings.
- All latest limit readings, including Name, Max Allowed, Currently Used, Remaining Calls, Percent Used, Status.
- Color: Normal neutral/green, Warning yellow, Critical red; include textual badges (not color alone).
- Historical readings table with filters for limit name, status, and date range; pagination/sorting performed server-side for scale.
- Historical record count; indicate that Keep Forever can consume increasing storage.
- A **Refresh Now** button defined as a _read-only_ live snapshot, unless a separate explicitly labeled “Collect Now” action is later introduced. Refresh Now must not persist readings, send emails, or change schedules.

Do not claim “current” when displaying previously stored values; label latest captured vs live readings.

## 6. Collecting and evaluating org limits

Use `System.OrgLimits.getMap()` and iterate its entries. For each non-null `System.OrgLimit`:

```apex
Map<String, System.OrgLimit> orgLimits = System.OrgLimits.getMap();
for (String key : orgLimits.keySet()) {
    System.OrgLimit entry = orgLimits.get(key);
    if (entry == null) continue;
    Integer maximum = entry.getLimit();
    Integer used = entry.getValue();
    // Validate maximum; calculate remaining and percent using Decimal.
}
```

Requirements:

- Capture the returned limit name/key, maximum, used, remaining (`maximum - used`), and percentage (`used / maximum * 100`) at **two decimal places**.
- Skip zero/negative maximum limits in percentage classification, or record them as `Unavailable` with a clear reason; choose a consistent policy. **Preferred:** skip them from `Org_Limit__c` and record skip count on optional run summary.
- Do not cap percentage at 100; possible overage should be visible. Remaining may be negative.
- `Normal` if percentage < Warning; `Warning` if >= Warning and < Critical; `Critical` if >= Critical. Exactly at a threshold counts.
- Use `Decimal` for arithmetic and null/overflow safeguards. Salesforce-reported metrics can vary by org and are not all strictly “API calls.” `DailyApiRequests`, for example, uses a rolling 24-hour usage window, not midnight-to-midnight.
- Sort alert records Critical before Warning and by descending percentage.
- Reuse a common DTO between production and demo providers, and a common severity evaluator where practical.

## 7. Historical `Org_Limit__c` data model

Create one history record **per valid limit per scheduled run**, including Normal readings. Records are immutable snapshots; keep the thresholds used in each snapshot so earlier classification remains explainable.

| Field label              | API name                | Type                                   |
| ------------------------ | ----------------------- | -------------------------------------- |
| Name                     | `Name`                  | Auto Number, e.g. `OL-{000000}`        |
| Limit Name               | `Limit_Name__c`         | Text(255)                              |
| Maximum Allowed          | `Maximum_Allowed__c`    | Number(18,0)                           |
| Currently Used           | `Currently_Used__c`     | Number(18,0)                           |
| Remaining Calls          | `Remaining__c`          | Number(18,0)                           |
| Percent Used             | `Percent_Used__c`       | Number(8,2), supports >100%            |
| Status                   | `Status__c`             | Picklist: Normal, Warning, Critical    |
| Sampled At               | `Sampled_At__c`         | Date/Time                              |
| Warning Threshold        | `Warning_Threshold__c`  | Number(5,2)                            |
| Critical Threshold       | `Critical_Threshold__c` | Number(5,2)                            |
| Run Identifier           | `Run_Identifier__c`     | Text(100), indexed if warranted        |
| Configuration (optional) | `Configuration__c`      | Lookup to Org Monitoring Configuration |

**Recommended:** `Org_Monitoring_Run__c` for a per-execution summary: started/completed, status, read count, stored count, skip count, warning count, critical count, email disposition, and concise error details. A run identifier should link sampled rows to the execution. Implement if reasonable; at minimum, retain error visibility somewhere administrators can inspect.

Use bulk insert via repository. Account for DML/governor limits and partial failures. If collections can exceed comfortable DML limits in the target org, queue persistence responsibly rather than assuming fixed small limits.

## 8. Monitoring schedule

Supported frequencies: **1, 2, 4, 6, 8, 12, and 24 hours**. Runs occur **only** on selected days, at `offset + n * interval` minutes after midnight while within the same local calendar day.

Examples:

| Selected days | Frequency |  Offset | Expected local times                     |
| ------------- | --------: | ------: | ---------------------------------------- |
| Mon–Fri       |    1 hour |  15 min | 00:15, 01:15, …, 23:15 on Mon–Fri        |
| Mon–Fri       |  12 hours |  90 min | 01:30 and 13:30 on Mon–Fri               |
| Sat           |  24 hours | 480 min | 08:00 Saturday                           |
| Sun/Tue/Thu   |   6 hours |   0 min | 00:00, 06:00, 12:00, 18:00 on those days |

Preferred implementation: build one CRON schedule per monitoring configuration that represents minute, hourly step and selected weekdays when possible. Handle offset decomposition into hour/minute (`offsetMinutes / 60`, `offsetMinutes % 60`) and the hour step. For non-zero offset hours, use a valid Salesforce CRON expression that enumerates appropriate hours rather than incorrectly assuming the step always begins at zero. Validate Salesforce-specific CRON semantics and use schedule-name ownership prefixes and returned CronTrigger IDs to prevent duplicates.

- On initial activation: create schedule.
- On schedule-affecting update: identify and abort owned old schedule(s), then create the new one; on failure provide a compensating repair path and clear UI error.
- On deactivation: abort owned monitoring schedule(s), retaining historical records.
- Show next execution time from `CronTrigger` or an explicitly calculated equivalent, clearly labeled.
- Repeated Submit must be idempotent.
- `System.schedule` runs in the **scheduler user's timezone**; test DST and weekday boundary behavior.
- Consider Salesforce’s concurrent/scheduled Apex governor limits; do not leave orphaned CRON jobs.
- Prevent duplicate overlapping logical runs (for example, by a deterministic execution key and short-lived concurrency guard) while allowing safe recovery after failures.

## 9. Email notifications

When **at least one** captured limit is Warning or Critical and there is at least one valid configured address, send **one consolidated HTML email per monitoring run**.

Email subject example: `[Org Monitoring][CRITICAL] My Salesforce Org — 2026-10-13 13:30 CDT` (use highest severity for subject).

HTML table columns: **Limit Name, Max Allowed, Currently Used, Remaining Calls, Percent Currently Used, Status**. Warning rows yellow; Critical rows red; ensure good contrast, accessible status text, and basic HTML escaping. Sort Critical first. Include Warning and Critical threshold percentages at the bottom, together with org name, sample time, and timezone. Plain-text fallback preferred. No alert email if zero thresholds are exceeded; no email when recipient list blank. Split on commas, trim, validate, dedupe. Failures should be surfaced in run logging; they must not silently discard historical records. Respect Salesforce email sending limits. Email suppression/deduplication or reminder cooldown can be a v2 enhancement unless explicitly requested.

## 10. Data retention and purge

`Retention_Period__c` values: `30`, `60`, `90`, `120`, and `FOREVER` (label **Keep Forever**). Implement a distinct daily purge job, independent of the monitoring job and independent of the Active checkbox.

- For a numeric period, remove `Org_Limit__c` rows with `Sampled_At__c` strictly earlier than the specified age, based on the actual current timestamp (document if calendar-day cutoff is used instead).
- For `FOREVER`, **do not delete** history automatically; purge routine exits without deletion.
- Use Batch Apex / chunking to accommodate large datasets and governor limits.
- Log count deleted and errors. Protect against inadvertent wide deletion and query/select only eligible rows.
- Do not purge the singleton configuration record.
- If run summaries are retained, apply a documented appropriate separate policy (or keep them consistent with history retention).
- Show history count and retention status on dashboard.

## 11. Demo Mode for portfolio demonstrations

Add this Lightning App Builder property to the dashboard's `.js-meta.xml`:

```xml
<targetConfigs>
  <targetConfig targets="lightning__AppPage">
    <property
      name="demoMode"
      type="Boolean"
      label="Enable Demo Mode"
      description="Show simulated org limit readings without production side effects"
      default="false"
    />
  </targetConfig>
</targetConfigs>
```

In the LWC JavaScript, `@api demoMode = false;` (apply Salesforce property design patterns).

**Behavior when enabled:**

1. Retrieve real available org-limit _names_ and positive maximums (read-only).
2. Randomly select **five distinct limits**; if fewer than five qualify, show all eligible limits and a clear notice.
3. Set synthetic usages relative to those real maximums; with at least two eligible limits, guarantee **at least one Warning and one Critical** under the currently configured thresholds. The other readings can be Normal/Warning/Critical.
4. Reuse the same thresholds, DTO, severity evaluator, rows, colors, and dashboard displays as production.
5. Display a prominent persistent `DEMO MODE — SIMULATED DATA` label, plus a **Generate New Demo Sample** action.
6. No persistence, emails, scheduled-job modification, configuration writes, or purge side effects in demo mode. Production scheduled jobs must continue independently and must not be influenced by a user's demo dashboard setting.
7. Do not misrepresent simulated readings as real consumption. Demo-related Refresh regenerates simulated results or is separately labeled.

**Edge case:** With a valid Warning < Critical <=100, 5 available positive-max limits permit a guaranteed Warning and Critical classification. For two, use one Warning and one Critical; with one, guarantee Critical and clearly say Warning could not also be demonstrated. Do not fake unsupported org limit names as live system entries.

## 12. Security and operational requirements

- Create a permission set `Org_Monitoring_Administrator` granting only required custom object/field permissions and necessary Apex class access.
- Display the Lightning App Page only to intended administrators; configure appropriate access for read-only viewers if needed.
- Controller methods must explicitly enforce intended authorization and data access (sharing, CRUD/FLS, user-mode operations where applicable) and must not allow unprivileged users to schedule jobs or edit recipients.
- Never expose configuration email addresses or sensitive debug details unnecessarily.
- Use explicit, intentional sharing declarations on Apex classes; document scheduler/system context.
- Keep service methods bulk-safe and testable; separate SOQL selector, DML repository, limit collection, notifications and scheduling.
- Handle missing configuration gracefully and provide a safe one-time initialization option.
- Avoid scheduling duplicates, cascading retries, or emailing repeatedly due to UI refreshes.

## 13. Apex architecture and flow

```text
Org Monitoring Lightning App Page
  ├── orgMonitoringConfiguration
  └── orgMonitoringDashboard  [demoMode property]
           │
           ▼
OrgMonitoringController (Apex, authorized endpoints)
           │
           ├── OrgMonitoringConfigService → configuration repository
           ├── OrgMonitoringService
           │       ├── OrgLimitsProvider → System.OrgLimits.getMap()
           │       ├── status evaluator and DTO mapper
           │       ├── OrgLimitRepository → Org_Limit__c history DML
           │       └── OrgMonitoringEmailService
           ├── OrgLimitSelector → history SOQL queries
           └── OrgMonitoringDemoProvider → simulated DTOs ONLY

OrgMonitoringScheduler → OrgMonitoringService → persist + alert
OrgMonitoringScheduleService → owned CRON job reconcile
OrgMonitoringPurgeJob → retention-aware batch deletion
```

Separate limits collection from classification and from persistence, so unit tests can inject controlled limit fixtures. DAO/selector classes own SOQL, repositories own DML; service owns orchestration. Code should be readable and appropriately documented, not overengineered.

## 14. Minimum acceptance criteria

1. Deployment creates all necessary metadata and a functional **Org Monitoring** Lightning App Page.
2. `Default` configuration record can be initialized exactly once and edited with Submit.
3. Threshold, email, day, frequency, offset, and retention validations work on client and server.
4. Every supported schedule interval (1/2/4/6/8/12/24 hours) produces expected times _only_ on selected weekdays and at configured offset in documented timezone.
5. Repeated submits do not create extra scheduled jobs; disabling Active stops monitoring schedules.
6. Scheduled collection evaluates **all valid limits exposed by `System.OrgLimits.getMap()`** and stores one `Org_Limit__c` reading per eligible limit, including Normal.
7. Normal, Warning, and Critical thresholds classify properly at boundary values; over-100 readings remain visible.
8. Exactly one consolidated alert email is sent per qualifying run to validated recipients, or none if no recipients/alerts.
9. Latest snapshot and paginated historical data are shown with accurate timestamps and status labels.
10. Numeric retention deletes only appropriately aged history; Keep Forever does not delete it.
11. Demo Mode picks five real available limit names when possible and guarantees at least one Warning and Critical; simulated data cannot be saved or emailed and is prominently labeled.
12. Privilege checks prevent unauthorized config edits and scheduling.
13. Test coverage is at least Salesforce's deployment minimum, with a project target of **85%+ meaningful Apex coverage** and appropriate behavioral assertions.

## 15. Test cases and deployment checklist

### Automated tests

- Threshold boundaries: immediately below Warning; exactly Warning; between thresholds; exactly Critical; above 100%.
- Zero/negative max, missing keys, empty map, null values, and unusual naming.
- All 7 schedule intervals; offset validation; 7-day combinations; weekend-only; day/time rollovers; DST and scheduler timezone.
- Save config / reschedule / deactivate / reactivate / repeated identical Submit / recovery after failed scheduling.
- Email no-recipient, one-recipient, comma-separated recipients, duplicates, invalid address, no-alert, mixed severity, send failure.
- Every-sample history logging and correct run grouping; bulk records; pagination and filters.
- Retention boundary at cutoff; Keep Forever; purge error; processing large history.
- Demo mode five distinct available limits, warning + critical guaranteed, regeneration, insufficient eligible limits, **no DML/email/schedule side effects**.
- User permission enforcement and explicit no-access assertions.

### Deliverables to provide with source

1. Salesforce DX project tree (or copy-ready metadata files) with complete LWCs, Apex and tests.
2. Custom object XML, field XML, permissions, FlexiPage, and Apex/LWC metadata.
3. Setup instructions for configuring org page access, initial `Default` record, scheduler user/timezone, and org-wide email if used.
4. Deployment commands (`sf project deploy start`, etc.) and test commands.
5. Known platform limits, assumptions, and any implementation differences from this specification.
6. A short demo script showing realistic readings, regenerated demo results, email formatting (preview only), and historical dashboard.

## 16. Resolved decisions and remaining implementation choices

**Resolved:** Use Custom Objects instead of Custom Metadata; application is Org Monitoring; history is Org Limits; log all eligible org limit readings including Normal; 1/2/4/6/8/12/24-hour intervals; selected weekdays and offset; Keep Forever option; five-limit demo with guaranteed Warning and Critical when at least two eligible limits exist; no demo side effects.

**Implementation choices to document (choose safe defaults without blocking build):** Whether to include the recommended run-summary object; exact UI treatment of unsupported/zero-maximum limits; permission model for read-only users; timezone selection policy; bootstrap provisioning of singleton config; specific CRON syntax and error reconciliation; and whether to suppress repeat alerts in a future release. Prefer minimal safe v1 defaults and list these choices in the README.
