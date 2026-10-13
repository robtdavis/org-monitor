public without sharing class OrgMonitoringConfigService {
  public static final String DEFAULT_KEY = 'DEFAULT';
  private static final List<String> DAY_ORDER = new List<String>{
    'SUN',
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT'
  };
  private static final Set<String> FREQUENCIES = new Set<String>{
    '1',
    '2',
    '4',
    '6',
    '8',
    '12',
    '24'
  };
  private static final Set<String> RETENTION_VALUES = new Set<String>{
    '30',
    '60',
    '90',
    '120',
    'FOREVER'
  };
  private final OrgMonitoringConfigRepository repository = new OrgMonitoringConfigRepository();

  public Org_Monitoring_Configuration__c getDefaultConfiguration() {
    return repository.getDefaultConfiguration();
  }

  public Org_Monitoring_Configuration__c initializeDefault() {
    Org_Monitoring_Configuration__c existing = getDefaultConfiguration();
    if (existing != null) {
      return existing;
    }
    Org_Monitoring_Configuration__c config = new Org_Monitoring_Configuration__c(
      Name = 'Default',
      Configuration_Key__c = DEFAULT_KEY,
      Warning_Percent_Value__c = 70,
      Critical_Percent_Value__c = 90,
      Active__c = true,
      Days_to_Run__c = 'SUN;MON;TUE;WED;THU;FRI;SAT',
      Frequency_Hours__c = '24',
      Retention_Period__c = '90',
      Time_Offset_Minutes__c = 0,
      Scheduling_Time_Zone__c = UserInfo.getTimeZone().getID()
    );
    try {
      repository.saveDefault(config);
    } catch (DmlException e) {
      if (e.getDmlType(0) != StatusCode.DUPLICATE_VALUE) {
        throw e;
      }
      config = getDefaultConfiguration();
      if (config == null) {
        throw e;
      }
    }
    return config;
  }

  public Org_Monitoring_Configuration__c save(
    OrgMonitoringController.ConfigurationInput input
  ) {
    validate(input);
    Org_Monitoring_Configuration__c config = getDefaultConfiguration();
    if (
      config != null &&
      config.Scheduling_Time_Zone__c != UserInfo.getTimeZone().getID()
    ) {
      throw new AuraHandledException(
        'Configuration changes must be submitted by the designated scheduler user in the configured time zone.'
      );
    }
    if (config == null) {
      config = new Org_Monitoring_Configuration__c(
        Name = 'Default',
        Configuration_Key__c = DEFAULT_KEY
      );
    }
    config.Warning_Percent_Value__c = input.warningPercent;
    config.Critical_Percent_Value__c = input.criticalPercent;
    config.Active__c = input.active;
    config.Days_to_Run__c = String.join(normalizeDays(input.daysToRun), ';');
    config.Frequency_Hours__c = input.frequencyHours;
    config.Time_Offset_Minutes__c = input.timeOffsetMinutes;
    config.Retention_Period__c = input.retentionPeriod;
    config.Comments__c = input.comments;
    config.Email_Addresses__c = String.join(
      normalizeEmails(input.emailAddresses),
      ','
    );
    config.Scheduling_Time_Zone__c = UserInfo.getTimeZone().getID();
    repository.saveDefault(config);
    return config;
  }

  public static List<String> normalizeDays(List<String> days) {
    Set<String> selected = new Set<String>();
    if (days != null) {
      for (String token : days) {
        String normalized = token == null ? '' : token.trim().toUpperCase();
        if (!DAY_ORDER.contains(normalized)) {
          throw new AuraHandledException(
            'Select valid weekdays (SUN through SAT).'
          );
        }
        selected.add(normalized);
      }
    }
    List<String> result = new List<String>();
    for (String day : DAY_ORDER) {
      if (selected.contains(day)) {
        result.add(day);
      }
    }
    return result;
  }

  public static List<String> normalizeEmails(String rawEmails) {
    List<String> result = new List<String>();
    Set<String> seen = new Set<String>();
    if (String.isBlank(rawEmails)) {
      return result;
    }
    Pattern emailPattern = Pattern.compile(
      '(?i)^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$'
    );
    for (String item : rawEmails.split(',')) {
      String email = item.trim();
      if (String.isBlank(email) || !emailPattern.matcher(email).matches()) {
        throw new AuraHandledException(
          'Enter valid comma-separated email addresses.'
        );
      }
      String key = email.toLowerCase();
      if (!seen.contains(key)) {
        seen.add(key);
        result.add(email);
      }
    }
    if (result.size() > 150) {
      throw new AuraHandledException(
        'A maximum of 150 alert recipients is supported by Salesforce email limits.'
      );
    }
    return result;
  }

  private static void validate(
    OrgMonitoringController.ConfigurationInput input
  ) {
    if (
      input == null ||
      input.warningPercent == null ||
      input.criticalPercent == null ||
      input.warningPercent < 0 ||
      input.criticalPercent > 100 ||
      input.criticalPercent <= input.warningPercent
    ) {
      throw new AuraHandledException(
        'Critical must be greater than Warning, and thresholds must be within 0–100.'
      );
    }
    if (input.active && normalizeDays(input.daysToRun).isEmpty()) {
      throw new AuraHandledException(
        'Select at least one day while monitoring is active.'
      );
    }
    if (!FREQUENCIES.contains(input.frequencyHours)) {
      throw new AuraHandledException(
        'Choose a supported monitoring frequency.'
      );
    }
    if (
      input.timeOffsetMinutes == null ||
      input.timeOffsetMinutes < 0 ||
      input.timeOffsetMinutes >= Integer.valueOf(input.frequencyHours) * 60 ||
      input.timeOffsetMinutes != input.timeOffsetMinutes.setScale(0)
    ) {
      throw new AuraHandledException(
        'Time offset must be whole minutes and less than the frequency interval.'
      );
    }
    if (!RETENTION_VALUES.contains(input.retentionPeriod)) {
      throw new AuraHandledException(
        'Choose a supported history retention period.'
      );
    }
    normalizeEmails(input.emailAddresses);
  }
}
