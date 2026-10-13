for (CronTrigger job : [
  SELECT Id, CronJobDetail.Name
  FROM CronTrigger
  WHERE CronJobDetail.Name LIKE 'OrgMonitoring-%'
]) {
  System.debug('Aborting job: ' + job.CronJobDetail.Name + ' (' + job.Id + ')');
  System.abortJob(job.Id);
}
