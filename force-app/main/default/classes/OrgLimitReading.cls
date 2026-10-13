public class OrgLimitReading {
  @AuraEnabled
  public String id { get; set; }
  @AuraEnabled
  public String limitName { get; set; }
  @AuraEnabled
  public Decimal maximumAllowed { get; set; }
  @AuraEnabled
  public Decimal currentlyUsed { get; set; }
  @AuraEnabled
  public Decimal remaining { get; set; }
  @AuraEnabled
  public Decimal percentUsed { get; set; }
  @AuraEnabled
  public String status { get; set; }
  @AuraEnabled
  public Datetime sampledAt { get; set; }
}
