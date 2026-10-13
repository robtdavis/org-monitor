public without sharing class OrgMonitoringScheduleService {
  public static final String MONITOR_PREFIX = 'OrgMonitoring-MONITOR-';
  public static final String PURGE_PREFIX = 'OrgMonitoring-PURGE-';
  private final OrgMonitoringScheduleSelector selector = new OrgMonitoringScheduleSelector();

  public void reconcileMonitoring(Org_Monitoring_Configuration__c config) {
    List<CronTrigger> existing = selector.monitoringJobs();
    if (config == null || !config.Active__c) {
      abortAll(existing);
      return;
    }
    if (config.Scheduling_Time_Zone__c != UserInfo.getTimeZone().getID()) {
      throw new AuraHandledException(
        'Schedule changes must be submitted by the designated scheduler user in the configured time zone.'
      );
    }
    String cron = buildCron(config);
    Integer matching = 0;
    for (CronTrigger job : existing) {
      if (job.CronExpression == cron) {
        matching++;
      }
    }
    if (matching == 1) {
      for (CronTrigger job : existing) {
        if (job.CronExpression != cron) {
          System.abortJob(job.Id);
        }
      }
      return;
    }

    String jobName = MONITOR_PREFIX + String.valueOf(DateTime.now().getTime());
    String newJobId = System.schedule(
      jobName,
      cron,
      new OrgMonitoringScheduler()
    );
    try {
      for (CronTrigger job : existing) {
        System.abortJob(job.Id);
      }
    } catch (Exception abortError) {
      System.abortJob(newJobId);
      throw new AuraHandledException(
        'The new schedule was rolled back because an existing monitoring schedule could not be cancelled: ' +
        abortError.getMessage()
      );
    }
  }

  public void ensurePurgeSchedule() {
    List<CronTrigger> existing = selector.purgeJobs();
    String cron = '0 17 1 * * ?';
    if (existing.size() == 1 && existing[0].CronExpression == cron) {
      return;
    }
    String newJobId = System.schedule(
      PURGE_PREFIX + String.valueOf(DateTime.now().getTime()),
      cron,
      new OrgMonitoringPurgeJob()
    );
    try {
      abortAll(existing);
    } catch (Exception abortError) {
      System.abortJob(newJobId);
      throw new AuraHandledException(
        'The replacement purge schedule was rolled back because an older purge schedule could not be cancelled: ' +
        abortError.getMessage()
      );
    }
  }

  public static String buildCron(Org_Monitoring_Configuration__c config) {
    Integer interval = Integer.valueOf(config.Frequency_Hours__c);
    Integer offset = Integer.valueOf(
      String.valueOf(config.Time_Offset_Minutes__c.setScale(0))
    );
    Integer minute = Math.mod(offset, 60);
    Integer firstHour = offset / 60;
    List<String> hours = new List<String>();
    for (Integer hour = firstHour; hour < 24; hour += interval) {
      hours.add(String.valueOf(hour));
    }
    List<String> days = OrgMonitoringConfigService.normalizeDays(
      String.isBlank(config.Days_to_Run__c)
        ? new List<String>()
        : config.Days_to_Run__c.split(';')
    );
    if (days.isEmpty()) {
      throw new AuraHandledException(
        'At least one weekday is required to schedule monitoring.'
      );
    }
    return '0 ' +
      minute +
      ' ' +
      String.join(hours, ',') +
      ' ? * ' +
      String.join(days, ',');
  }

  public void abortAllJobs() {
    abortAllMonitoringJobs();
    abortAllPurgeJobs();
  }

  public void abortAllMonitoringJobs() {
    abortAll(selector.monitoringJobs());
  }

  public void abortAllPurgeJobs() {
    abortAll(selector.purgeJobs());
  }

  private static void abortAll(List<CronTrigger> jobs) {
    for (CronTrigger job : jobs) {
      System.abortJob(job.Id);
    }
  }
}
