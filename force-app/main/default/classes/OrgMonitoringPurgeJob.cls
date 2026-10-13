public without sharing class OrgMonitoringPurgeJob implements Schedulable, Database.Batchable<SObject>, Database.Stateful {
  private Datetime cutoff;
  private Integer deletedCount = 0;
  private Integer failedCount = 0;
  private Integer processedCount = 0;
  private Id runId;
  private String errorDetails = '';

  public void execute(SchedulableContext context) {
    Org_Monitoring_Configuration__c config = new OrgMonitoringConfigService()
      .getDefaultConfiguration();
    if (config == null || config.Retention_Period__c == 'FOREVER') {
      return;
    }
    Integer daysToKeep = Integer.valueOf(config.Retention_Period__c);
    Datetime startedAt = System.now();
    Org_Monitoring_Run__c run = new Org_Monitoring_Run__c(
      Execution_Key__c = 'P' + startedAt.formatGMT('yyyyMMddHHmmssSSS'),
      Started_At__c = startedAt,
      Status__c = 'Running',
      Email_Disposition__c = 'Retention purge'
    );
    insert run;
    Database.executeBatch(
      new OrgMonitoringPurgeJob(startedAt.addDays(-daysToKeep), run.Id),
      200
    );
  }

  public OrgMonitoringPurgeJob() {
  }

  public OrgMonitoringPurgeJob(Datetime retentionCutoff) {
    cutoff = retentionCutoff;
  }

  public OrgMonitoringPurgeJob(Datetime retentionCutoff, Id auditRunId) {
    cutoff = retentionCutoff;
    runId = auditRunId;
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    if (cutoff == null) {
      return Database.getQueryLocator(
        [SELECT Id FROM Org_Limit__c WHERE Id = NULL]
      );
    }
    return Database.getQueryLocator(
      [
        SELECT Id
        FROM Org_Limit__c
        WHERE Sampled_At__c < :cutoff
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    Database.DeleteResult[] results = Database.delete(scope, false);
    for (Database.DeleteResult result : results) {
      processedCount++;
      if (result.isSuccess()) {
        deletedCount++;
      } else {
        failedCount += result.getErrors().size();
        for (Database.Error error : result.getErrors()) {
          errorDetails += error.getMessage() + '\n';
        }
      }
    }
  }

  public void finish(Database.BatchableContext context) {
    System.debug(
      LoggingLevel.INFO,
      'Org Monitoring purge deleted=' + deletedCount + ', failed=' + failedCount
    );
    if (runId != null) {
      Org_Monitoring_Run__c run = new Org_Monitoring_Run__c(
        Id = runId,
        Completed_At__c = System.now(),
        Status__c = failedCount == 0 ? 'Completed' : 'Completed with errors',
        Read_Count__c = processedCount,
        Stored_Count__c = deletedCount,
        Skipped_Count__c = failedCount,
        Error_Details__c = String.isBlank(errorDetails)
          ? null
          : errorDetails.left(32000)
      );
      update run;
    }
    if (cutoff != null && !Test.isRunningTest()) {
      Database.executeBatch(new OrgMonitoringRunPurgeBatch(cutoff), 200);
    }
  }
}
