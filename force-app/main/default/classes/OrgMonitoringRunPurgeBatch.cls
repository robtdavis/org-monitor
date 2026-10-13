public without sharing class OrgMonitoringRunPurgeBatch implements Database.Batchable<SObject>, Database.Stateful {
  private Datetime cutoff;
  private Integer deletedCount = 0;
  private Integer failedCount = 0;

  public OrgMonitoringRunPurgeBatch(Datetime retentionCutoff) {
    cutoff = retentionCutoff;
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      [
        SELECT Id
        FROM Org_Monitoring_Run__c
        WHERE Started_At__c < :cutoff
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    Database.DeleteResult[] results = Database.delete(scope, false);
    for (Database.DeleteResult result : results) {
      if (result.isSuccess()) {
        deletedCount++;
      } else {
        failedCount += result.getErrors().size();
      }
    }
  }

  public void finish(Database.BatchableContext context) {
    System.debug(
      LoggingLevel.INFO,
      'Org Monitoring run audit purge deleted=' +
        deletedCount +
        ', failed=' +
        failedCount
    );
  }
}
