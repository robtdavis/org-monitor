public without sharing class OrgLimitRepository {
  public Database.SaveResult[] insertReadings(List<Org_Limit__c> readings) {
    if (!readings.isEmpty()) {
      return Database.insert(readings, false);
    }
    return new List<Database.SaveResult>();
  }
}
