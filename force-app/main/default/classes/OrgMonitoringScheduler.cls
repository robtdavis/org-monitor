public without sharing class OrgMonitoringScheduler implements Schedulable {
  public void execute(SchedulableContext context) {
    new OrgMonitoringService().runScheduled();
  }
}
