public without sharing class OrgMonitoringRunSelector {
  public Boolean hasRecentRunningRun(Datetime staleBefore) {
    return [
        SELECT Id
        FROM Org_Monitoring_Run__c
        WHERE Status__c = 'Running' AND Started_At__c >= :staleBefore
        LIMIT 1
      ]
      .size() > 0;
  }
}
