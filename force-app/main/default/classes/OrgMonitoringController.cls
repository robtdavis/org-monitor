public with sharing class OrgMonitoringController {
  public class ConfigurationInput {
    @AuraEnabled
    public Decimal warningPercent { get; set; }
    @AuraEnabled
    public Decimal criticalPercent { get; set; }
    @AuraEnabled
    public Boolean active { get; set; }
    @AuraEnabled
    public List<String> daysToRun { get; set; }
    @AuraEnabled
    public String frequencyHours { get; set; }
    @AuraEnabled
    public Decimal timeOffsetMinutes { get; set; }
    @AuraEnabled
    public String retentionPeriod { get; set; }
    @AuraEnabled
    public String comments { get; set; }
    @AuraEnabled
    public String emailAddresses { get; set; }
  }

  public class ConfigurationView {
    @AuraEnabled
    public Decimal warningPercent { get; set; }
    @AuraEnabled
    public Decimal criticalPercent { get; set; }
    @AuraEnabled
    public Boolean active { get; set; }
    @AuraEnabled
    public String daysToRun { get; set; }
    @AuraEnabled
    public String frequencyHours { get; set; }
    @AuraEnabled
    public Decimal timeOffsetMinutes { get; set; }
    @AuraEnabled
    public String retentionPeriod { get; set; }
    @AuraEnabled
    public String comments { get; set; }
    @AuraEnabled
    public String emailAddresses { get; set; }
    @AuraEnabled
    public String schedulingTimeZone { get; set; }
    @AuraEnabled
    public Datetime nextRunAt { get; set; }
    @AuraEnabled
    public String scheduleStatus { get; set; }
  }

  public class HistoryResponse {
    @AuraEnabled
    public List<OrgLimitReading> rows { get; set; }
    @AuraEnabled
    public Integer totalCount { get; set; }
  }

  public class DemoSnapshotView {
    @AuraEnabled
    public List<OrgLimitReading> rows { get; set; }
    @AuraEnabled
    public String notice { get; set; }
  }

  public class DashboardView {
    @AuraEnabled
    public Datetime latestSampledAt { get; set; }
    @AuraEnabled
    public Datetime nextRunAt { get; set; }
    @AuraEnabled
    public String scheduleStatus { get; set; }
    @AuraEnabled
    public Integer normalCount { get; set; }
    @AuraEnabled
    public Integer warningCount { get; set; }
    @AuraEnabled
    public Integer criticalCount { get; set; }
    @AuraEnabled
    public Integer historyCount { get; set; }
    @AuraEnabled
    public String retentionPeriod { get; set; }
    @AuraEnabled
    public List<OrgLimitReading> rows { get; set; }
  }

  @AuraEnabled(cacheable=true)
  public static ConfigurationView getConfiguration() {
    requireAdministrator();
    requireConfigurationFields(false);
    Org_Monitoring_Configuration__c config = new OrgMonitoringConfigService()
      .getDefaultConfiguration();
    return toConfigurationView(config, nextMonitoringRun());
  }

  @AuraEnabled
  public static ConfigurationView saveConfiguration(String requestJson) {
    requireAdministrator();
    requireConfigurationFields(true);
    ConfigurationInput input;
    try {
      input = (ConfigurationInput) JSON.deserialize(
        requestJson,
        ConfigurationInput.class
      );
    } catch (Exception e) {
      throw new AuraHandledException(
        'Configuration could not be read. Review the form and try again.'
      );
    }
    Org_Monitoring_Configuration__c saved = new OrgMonitoringConfigService()
      .save(input);
    try {
      OrgMonitoringScheduleService schedules = new OrgMonitoringScheduleService();
      schedules.reconcileMonitoring(saved);
      schedules.ensurePurgeSchedule();
    } catch (Exception e) {
      throw new AuraHandledException(
        'Configuration was saved, but schedule reconciliation failed. Submit again after resolving this issue. ' +
        e.getMessage()
      );
    }
    return toConfigurationView(saved, nextMonitoringRun());
  }

  @AuraEnabled
  public static ConfigurationView initializeConfiguration() {
    requireAdministrator();
    Org_Monitoring_Configuration__c config = new OrgMonitoringConfigService()
      .initializeDefault();
    try {
      OrgMonitoringScheduleService schedules = new OrgMonitoringScheduleService();
      schedules.reconcileMonitoring(config);
      schedules.ensurePurgeSchedule();
    } catch (Exception e) {
      throw new AuraHandledException(
        'The Default configuration exists, but schedule initialization failed. Submit again to retry. ' +
        e.getMessage()
      );
    }
    return toConfigurationView(config, nextMonitoringRun());
  }

  @AuraEnabled
  public static ConfigurationView abortScheduledJobs() {
    requireAdministrator();
    new OrgMonitoringScheduleService().abortAllJobs();
    Org_Monitoring_Configuration__c config = new OrgMonitoringConfigService()
      .getDefaultConfiguration();
    return toConfigurationView(config, null);
  }

  @AuraEnabled
  public static DashboardView getDashboard() {
    requireHistoryRead();
    Org_Monitoring_Configuration__c config = new OrgMonitoringConfigService()
      .getDefaultConfiguration();
    OrgLimitSelector selector = new OrgLimitSelector();
    List<Org_Limit__c> latest = selector.latestReadings();
    DashboardView result = new DashboardView();
    result.rows = toReadings(latest);
    result.historyCount = selector.countHistory();
    result.retentionPeriod = config == null ? null : config.Retention_Period__c;
    result.latestSampledAt = latest.isEmpty() ? null : latest[0].Sampled_At__c;
    result.nextRunAt = nextMonitoringRun();
    result.scheduleStatus = config == null || !config.Active__c
      ? 'Monitoring is not active.'
      : (result.nextRunAt == null
          ? 'No monitoring schedule is available.'
          : 'Scheduled');
    result.normalCount = 0;
    result.warningCount = 0;
    result.criticalCount = 0;
    for (Org_Limit__c row : latest) {
      if (row.Status__c == 'Normal') {
        result.normalCount++;
      } else if (row.Status__c == 'Warning') {
        result.warningCount++;
      } else if (row.Status__c == 'Critical') {
        result.criticalCount++;
      }
    }
    return result;
  }

  @AuraEnabled
  public static List<OrgLimitReading> getLiveSnapshot() {
    requireHistoryRead();
    Org_Monitoring_Configuration__c config = new OrgMonitoringConfigService()
      .getDefaultConfiguration();
    Decimal warning = config == null ? 70 : config.Warning_Percent_Value__c;
    Decimal critical = config == null ? 90 : config.Critical_Percent_Value__c;
    return new OrgLimitsProvider().collect(warning, critical);
  }

  @AuraEnabled
  public static DemoSnapshotView getDemoSnapshot() {
    requireHistoryRead();
    Org_Monitoring_Configuration__c config = new OrgMonitoringConfigService()
      .getDefaultConfiguration();
    Decimal warning = config == null ? 70 : config.Warning_Percent_Value__c;
    Decimal critical = config == null ? 90 : config.Critical_Percent_Value__c;
    List<OrgLimitReading> eligible = new OrgLimitsProvider()
      .collect(warning, critical);
    List<OrgLimitReading> selected = new List<OrgLimitReading>();
    Integer availableCount = eligible.size();
    while (!eligible.isEmpty() && selected.size() < 5) {
      Integer index = (Integer) Math.floor(Math.random() * eligible.size());
      OrgLimitReading row = eligible.remove(index);
      Decimal percentage = Math.random() < 0.5
        ? (warning + critical) / 2
        : critical + 5;
      percentage = percentage > 150 ? 150 : percentage;
      row.currentlyUsed = row.maximumAllowed * percentage / 100;
      row.remaining = row.maximumAllowed - row.currentlyUsed;
      row.percentUsed = (row.currentlyUsed /
        row.maximumAllowed *
        100)
        .setScale(2, RoundingMode.HALF_UP);
      row.status = OrgMonitoringService.classify(
        row.percentUsed,
        warning,
        critical
      );
      row.sampledAt = System.now();
      selected.add(row);
    }
    if (selected.size() >= 2) {
      selected[0].currentlyUsed = selected[0].maximumAllowed * warning / 100;
      selected[0].remaining =
        selected[0].maximumAllowed - selected[0].currentlyUsed;
      selected[0].percentUsed = warning.setScale(2, RoundingMode.HALF_UP);
      selected[0].status = OrgMonitoringService.classify(
        selected[0].percentUsed,
        warning,
        critical
      );
      selected[1].currentlyUsed = selected[1].maximumAllowed * critical / 100;
      selected[1].remaining =
        selected[1].maximumAllowed - selected[1].currentlyUsed;
      selected[1].percentUsed = critical.setScale(2, RoundingMode.HALF_UP);
      selected[1].status = OrgMonitoringService.classify(
        selected[1].percentUsed,
        warning,
        critical
      );
    } else if (selected.size() == 1) {
      selected[0].currentlyUsed = selected[0].maximumAllowed * critical / 100;
      selected[0].remaining =
        selected[0].maximumAllowed - selected[0].currentlyUsed;
      selected[0].percentUsed = critical.setScale(2, RoundingMode.HALF_UP);
      selected[0].status = 'Critical';
    }
    DemoSnapshotView response = new DemoSnapshotView();
    response.rows = selected;
    if (availableCount == 0) {
      response.notice = 'No positive-maximum org limits are available to simulate.';
    } else if (availableCount < 5) {
      response.notice =
        'Only ' +
        availableCount +
        ' eligible org limit(s) are available; showing all of them.';
    }
    if (selected.size() == 1) {
      response.notice = String.isBlank(response.notice)
        ? ''
        : response.notice + ' ';
      response.notice += 'A Warning and Critical pair cannot both be shown with only one eligible limit.';
    } else if (
      selected.size() >= 2 &&
      (selected[0].status != 'Warning' ||
      selected[1].status != 'Critical')
    ) {
      response.notice = String.isBlank(response.notice)
        ? ''
        : response.notice + ' ';
      response.notice += 'The available maximums do not allow both simulated thresholds to be shown accurately.';
    }

    if (config != null && String.isNotBlank(config.Email_Addresses__c)) {
      List<String> recipients = OrgMonitoringConfigService.normalizeEmails(
        config.Email_Addresses__c
      );
      if (!recipients.isEmpty() && !selected.isEmpty()) {
        try {
          OrgMonitoringEmailService.sendAlerts(
            selected,
            recipients,
            warning,
            critical,
            System.now(),
            true
          );
          response.notice = String.isBlank(response.notice)
            ? 'Demo alert email sent to configured recipient(s).'
            : response.notice +
              ' Demo alert email sent to configured recipient(s).';
        } catch (Exception e) {
          response.notice = String.isBlank(response.notice)
            ? 'Demo email notice: ' + e.getMessage()
            : response.notice + ' (Demo email notice: ' + e.getMessage() + ')';
        }
      }
    } else {
      response.notice = String.isBlank(response.notice)
        ? 'No alert email addresses configured; demo email was not sent.'
        : response.notice +
          ' No alert email addresses configured; demo email was not sent.';
    }

    return response;
  }

  @AuraEnabled
  public static HistoryResponse getHistory(String requestJson) {
    requireHistoryRead();
    Map<String, Object> request = (Map<String, Object>) JSON.deserializeUntyped(
      requestJson
    );
    String limitName = (String) request.get('limitName');
    String status = (String) request.get('status');
    if (
      String.isNotBlank(status) &&
      !new Set<String>{ 'Normal', 'Warning', 'Critical' }.contains(status)
    ) {
      throw new AuraHandledException('Choose a valid history status filter.');
    }
    Datetime startAt = parseDate(request.get('startAt'));
    Datetime endAt = parseDate(request.get('endAt'));
    if (startAt != null && endAt != null && startAt > endAt) {
      throw new AuraHandledException(
        'History start date must not be later than the end date.'
      );
    }
    Integer pageSize = boundedInteger(request.get('pageSize'), 50, 1, 200);
    Integer pageNumber = boundedInteger(
      request.get('pageNumber'),
      1,
      1,
      1000000
    );
    Integer offsetRows = (pageNumber - 1) * pageSize;
    if (offsetRows > 2000) {
      throw new AuraHandledException(
        'Salesforce supports history offset pagination through 2,000 rows. Narrow the filters to continue.'
      );
    }
    String sortBy = (String) request.get('sortBy');
    String sortDirection = (String) request.get('sortDirection');
    if (
      !String.isBlank(sortDirection) &&
      !new Set<String>{ 'ASC', 'DESC' }.contains(sortDirection.toUpperCase())
    ) {
      throw new AuraHandledException('Choose ASC or DESC for history sorting.');
    }
    if (
      !String.isBlank(sortBy) &&
      !new Set<String>{
          'limitName',
          'maximumAllowed',
          'currentlyUsed',
          'remaining',
          'percentUsed',
          'status',
          'sampledAt'
        }
        .contains(sortBy)
    ) {
      throw new AuraHandledException('Choose a valid history sort column.');
    }
    OrgLimitSelector selector = new OrgLimitSelector();
    HistoryResponse response = new HistoryResponse();
    response.rows = toReadings(
      selector.history(
        limitName,
        status,
        startAt,
        endAt,
        sortBy,
        String.isBlank(sortDirection) ? 'DESC' : sortDirection.toUpperCase(),
        pageSize,
        offsetRows
      )
    );
    response.totalCount = selector.countHistory(
      limitName,
      status,
      startAt,
      endAt
    );
    return response;
  }

  private static ConfigurationView toConfigurationView(
    Org_Monitoring_Configuration__c config,
    Datetime nextRun
  ) {
    ConfigurationView view = new ConfigurationView();
    if (config == null) {
      view.scheduleStatus = 'Configuration is not initialized.';
      return view;
    }
    view.warningPercent = config.Warning_Percent_Value__c;
    view.criticalPercent = config.Critical_Percent_Value__c;
    view.active = config.Active__c;
    view.daysToRun = config.Days_to_Run__c;
    view.frequencyHours = config.Frequency_Hours__c;
    view.timeOffsetMinutes = config.Time_Offset_Minutes__c;
    view.retentionPeriod = config.Retention_Period__c;
    view.comments = config.Comments__c;
    view.emailAddresses = config.Email_Addresses__c;
    view.schedulingTimeZone = config.Scheduling_Time_Zone__c;
    view.nextRunAt = nextRun;
    view.scheduleStatus = !config.Active__c
      ? 'Monitoring is not active.'
      : (nextRun == null ? 'Schedule reconciliation required.' : 'Scheduled');
    return view;
  }

  private static List<OrgLimitReading> toReadings(List<Org_Limit__c> records) {
    List<OrgLimitReading> readings = new List<OrgLimitReading>();
    for (Org_Limit__c record : records) {
      OrgLimitReading reading = new OrgLimitReading();
      reading.id = record.Id;
      reading.limitName = record.Limit_Name__c;
      reading.maximumAllowed = record.Maximum_Allowed__c;
      reading.currentlyUsed = record.Currently_Used__c;
      reading.remaining = record.Remaining__c;
      reading.percentUsed = record.Percent_Used__c;
      reading.status = record.Status__c;
      reading.sampledAt = record.Sampled_At__c;
      readings.add(reading);
    }
    return readings;
  }

  private static Datetime nextMonitoringRun() {
    return new OrgMonitoringScheduleSelector().nextMonitoringRun();
  }

  private static Datetime parseDate(Object value) {
    if (value == null || String.isBlank(String.valueOf(value))) {
      return null;
    }
    try {
      return (Datetime) JSON.deserialize(
        '"' + String.escapeSingleQuotes(String.valueOf(value)) + '"',
        Datetime.class
      );
    } catch (Exception e) {
      throw new AuraHandledException('Date filter is invalid.');
    }
  }

  private static Integer boundedInteger(
    Object value,
    Integer fallback,
    Integer minimum,
    Integer maximum
  ) {
    if (value == null) {
      return fallback;
    }
    Integer parsed;
    try {
      parsed = Integer.valueOf(String.valueOf(value));
    } catch (Exception e) {
      return fallback;
    }
    return Math.max(minimum, Math.min(maximum, parsed));
  }

  private static void requireAdministrator() {
    if (
      !FeatureManagement.checkPermission('Manage_Org_Monitoring') ||
      !Schema.sObjectType.Org_Monitoring_Configuration__c.isAccessible() ||
      !Schema.sObjectType.Org_Monitoring_Configuration__c.isUpdateable()
    ) {
      throw new AuraHandledException(
        'You are not authorized to manage Org Monitoring settings.'
      );
    }
  }

  private static void requireConfigurationFields(Boolean forUpdate) {
    List<Schema.DescribeFieldResult> fields = new List<Schema.DescribeFieldResult>{
      Schema.SObjectType.Org_Monitoring_Configuration__c.fields.Warning_Percent_Value__c,
      Schema.SObjectType.Org_Monitoring_Configuration__c.fields.Critical_Percent_Value__c,
      Schema.SObjectType.Org_Monitoring_Configuration__c.fields.Active__c,
      Schema.SObjectType.Org_Monitoring_Configuration__c.fields.Email_Addresses__c,
      Schema.SObjectType.Org_Monitoring_Configuration__c.fields.Comments__c,
      Schema.SObjectType.Org_Monitoring_Configuration__c.fields.Time_Offset_Minutes__c,
      Schema.SObjectType.Org_Monitoring_Configuration__c.fields.Days_to_Run__c,
      Schema.SObjectType.Org_Monitoring_Configuration__c.fields.Frequency_Hours__c,
      Schema.SObjectType.Org_Monitoring_Configuration__c.fields.Retention_Period__c,
      Schema.SObjectType.Org_Monitoring_Configuration__c.fields.Scheduling_Time_Zone__c
    };
    for (Schema.DescribeFieldResult access : fields) {
      if (
        !access.isAccessible() ||
        (forUpdate &&
        access.getName() != 'Scheduling_Time_Zone__c' &&
        !access.isUpdateable())
      ) {
        throw new AuraHandledException(
          'You do not have the required field access for Org Monitoring configuration.'
        );
      }
    }
  }

  private static void requireHistoryRead() {
    if (
      !Schema.sObjectType.Org_Limit__c.isAccessible() ||
      !Schema.sObjectType.Org_Limit__c.fields.Limit_Name__c.isAccessible() ||
      !Schema.sObjectType.Org_Limit__c.fields.Maximum_Allowed__c.isAccessible() ||
      !Schema.sObjectType.Org_Limit__c.fields.Currently_Used__c.isAccessible() ||
      !Schema.sObjectType.Org_Limit__c.fields.Remaining__c.isAccessible() ||
      !Schema.sObjectType.Org_Limit__c.fields.Percent_Used__c.isAccessible() ||
      !Schema.sObjectType.Org_Limit__c.fields.Status__c.isAccessible() ||
      !Schema.sObjectType.Org_Limit__c.fields.Sampled_At__c.isAccessible()
    ) {
      throw new AuraHandledException(
        'You are not authorized to view Org Monitoring readings.'
      );
    }
  }
}
