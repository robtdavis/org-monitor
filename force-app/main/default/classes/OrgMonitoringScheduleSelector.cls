public without sharing class OrgMonitoringScheduleSelector {
  public List<CronTrigger> monitoringJobs() {
    return [
      SELECT Id, CronExpression, State
      FROM CronTrigger
      WHERE
        CronJobDetail.Name LIKE 'OrgMonitoring-MONITOR-%'
        AND State IN ('WAITING', 'ACQUIRED', 'PAUSED', 'BLOCKED')
    ];
  }

  public List<CronTrigger> purgeJobs() {
    return [
      SELECT Id, CronExpression, State
      FROM CronTrigger
      WHERE
        CronJobDetail.Name LIKE 'OrgMonitoring-PURGE-%'
        AND State IN ('WAITING', 'ACQUIRED', 'PAUSED', 'BLOCKED')
    ];
  }

  public Datetime nextMonitoringRun() {
    List<CronTrigger> jobs = [
      SELECT NextFireTime
      FROM CronTrigger
      WHERE
        CronJobDetail.Name LIKE 'OrgMonitoring-MONITOR-%'
        AND State IN ('WAITING', 'ACQUIRED')
      ORDER BY NextFireTime ASC
      LIMIT 1
    ];
    return jobs.isEmpty() ? null : jobs[0].NextFireTime;
  }
}
