public without sharing class OrgMonitoringConfigRepository {
  public Org_Monitoring_Configuration__c getDefaultConfiguration() {
    String configurationKey = OrgMonitoringConfigService.DEFAULT_KEY;
    List<Org_Monitoring_Configuration__c> rows = [
      SELECT
        Id,
        Name,
        Configuration_Key__c,
        Warning_Percent_Value__c,
        Critical_Percent_Value__c,
        Active__c,
        Email_Addresses__c,
        Comments__c,
        Time_Offset_Minutes__c,
        Days_to_Run__c,
        Frequency_Hours__c,
        Retention_Period__c,
        Scheduling_Time_Zone__c
      FROM Org_Monitoring_Configuration__c
      WHERE Configuration_Key__c = :configurationKey
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  public void saveDefault(Org_Monitoring_Configuration__c config) {
    upsert config Configuration_Key__c;
  }
}
