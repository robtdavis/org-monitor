public without sharing class OrgMonitoringService {
  @TestVisible
  private static OrgLimitsProvider limitsProvider = new OrgLimitsProvider();

  public static String classify(
    Decimal percent,
    Decimal warning,
    Decimal critical
  ) {
    if (percent >= critical) {
      return 'Critical';
    }
    if (percent >= warning) {
      return 'Warning';
    }
    return 'Normal';
  }

  public void runScheduled() {
    OrgMonitoringConfigService configService = new OrgMonitoringConfigService();
    Org_Monitoring_Configuration__c config = configService.getDefaultConfiguration();
    if (config == null || !config.Active__c) {
      return;
    }
    Datetime startedAt = System.now();
    if (
      new OrgMonitoringRunSelector().hasRecentRunningRun(startedAt.addHours(-2))
    ) {
      return;
    }
    String runKey = startedAt.formatGMT('yyyyMMddHHmm');
    Org_Monitoring_Run__c run = new Org_Monitoring_Run__c(
      Execution_Key__c = runKey,
      Started_At__c = startedAt,
      Status__c = 'Running'
    );
    try {
      insert run;
    } catch (DmlException e) {
      if (e.getDmlType(0) == StatusCode.DUPLICATE_VALUE) {
        return;
      }
      throw e;
    }

    try {
      List<OrgLimitReading> readings = limitsProvider.collect(
        config.Warning_Percent_Value__c,
        config.Critical_Percent_Value__c
      );
      String runIdentifier = run.Id;
      List<Org_Limit__c> records = new List<Org_Limit__c>();
      Integer warnings = 0;
      Integer criticals = 0;
      for (OrgLimitReading reading : readings) {
        if (reading.status == 'Warning') {
          warnings++;
        } else if (reading.status == 'Critical') {
          criticals++;
        }
        records.add(
          new Org_Limit__c(
            Limit_Name__c = reading.limitName,
            Maximum_Allowed__c = reading.maximumAllowed,
            Currently_Used__c = reading.currentlyUsed,
            Remaining__c = reading.remaining,
            Percent_Used__c = reading.percentUsed,
            Status__c = reading.status,
            Sampled_At__c = startedAt,
            Warning_Threshold__c = config.Warning_Percent_Value__c,
            Critical_Threshold__c = config.Critical_Percent_Value__c,
            Run_Identifier__c = runIdentifier
          )
        );
      }
      Database.SaveResult[] saved = new OrgLimitRepository()
        .insertReadings(records);
      Integer stored = 0;
      List<String> errors = new List<String>();
      for (Integer index = 0; index < saved.size(); index++) {
        if (saved[index].isSuccess()) {
          stored++;
        } else {
          for (Database.Error error : saved[index].getErrors()) {
            errors.add(
              'History insert failed for ' +
                readings[index].limitName +
                ': ' +
                error.getMessage()
            );
          }
        }
      }
      run.Read_Count__c = readings.size();
      run.Stored_Count__c = stored;
      Map<String, System.OrgLimit> reportedLimits = System.OrgLimits.getMap();
      run.Skipped_Count__c = Math.max(
        0,
        (reportedLimits == null ? 0 : reportedLimits.size()) - readings.size()
      );
      run.Warning_Count__c = warnings;
      run.Critical_Count__c = criticals;
      run.Email_Disposition__c = warnings + criticals == 0
        ? 'No alerts'
        : 'Pending';

      if (warnings + criticals > 0) {
        try {
          OrgMonitoringEmailService.sendAlerts(
            readings,
            OrgMonitoringConfigService.normalizeEmails(
              config.Email_Addresses__c
            ),
            config.Warning_Percent_Value__c,
            config.Critical_Percent_Value__c,
            startedAt
          );
          run.Email_Disposition__c = String.isBlank(config.Email_Addresses__c)
            ? 'No recipients'
            : 'Sent';
        } catch (Exception emailError) {
          errors.add('Alert email failed: ' + emailError.getMessage());
          run.Email_Disposition__c = 'Failed';
        }
      }
      run.Completed_At__c = System.now();
      run.Status__c = errors.isEmpty() ? 'Completed' : 'Completed with errors';
      run.Error_Details__c = errors.isEmpty()
        ? null
        : String.join(errors, '\n').left(32000);
      update run;
    } catch (Exception e) {
      run.Completed_At__c = System.now();
      run.Status__c = 'Failed';
      run.Error_Details__c = e.getMessage().left(32000);
      update run;
      throw e;
    }
  }
}
