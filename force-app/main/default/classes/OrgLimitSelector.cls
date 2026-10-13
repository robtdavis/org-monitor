public with sharing class OrgLimitSelector {
  public List<Org_Limit__c> latestReadings() {
    List<Org_Limit__c> latest = [
      SELECT
        Id,
        Limit_Name__c,
        Maximum_Allowed__c,
        Currently_Used__c,
        Remaining__c,
        Percent_Used__c,
        Status__c,
        Sampled_At__c
      FROM Org_Limit__c
      WITH USER_MODE
      ORDER BY Sampled_At__c DESC
      LIMIT 1
    ];
    if (latest.isEmpty()) {
      return new List<Org_Limit__c>();
    }
    Datetime latestAt = latest[0].Sampled_At__c;
    return [
      SELECT
        Id,
        Limit_Name__c,
        Maximum_Allowed__c,
        Currently_Used__c,
        Remaining__c,
        Percent_Used__c,
        Status__c,
        Sampled_At__c
      FROM Org_Limit__c
      WHERE Sampled_At__c = :latestAt
      WITH USER_MODE
      ORDER BY Status__c DESC, Percent_Used__c DESC
    ];
  }

  public Integer countHistory() {
    return Database.countQueryWithBinds(
      'SELECT COUNT() FROM Org_Limit__c',
      new Map<String, Object>(),
      AccessLevel.USER_MODE
    );
  }

  public List<Org_Limit__c> history(
    String limitName,
    String status,
    Datetime startAt,
    Datetime endAt,
    String sortBy,
    String sortDirection,
    Integer pageSize,
    Integer offsetRows
  ) {
    List<String> predicates = new List<String>();
    Map<String, Object> binds = new Map<String, Object>();
    if (String.isNotBlank(limitName)) {
      predicates.add('Limit_Name__c LIKE :limitName');
      binds.put('limitName', '%' + limitName.trim() + '%');
    }
    if (
      String.isNotBlank(status) &&
      new Set<String>{ 'Normal', 'Warning', 'Critical' }.contains(status)
    ) {
      predicates.add('Status__c = :status');
      binds.put('status', status);
    }
    if (startAt != null) {
      predicates.add('Sampled_At__c >= :startAt');
      binds.put('startAt', startAt);
    }
    if (endAt != null) {
      predicates.add('Sampled_At__c <= :endAt');
      binds.put('endAt', endAt);
    }
    String queryText =
      'SELECT Id, Limit_Name__c, Maximum_Allowed__c, Currently_Used__c, ' +
      'Remaining__c, Percent_Used__c, Status__c, Sampled_At__c FROM Org_Limit__c';
    if (!predicates.isEmpty()) {
      queryText += ' WHERE ' + String.join(predicates, ' AND ');
    }
    Map<String, String> sortFields = new Map<String, String>{
      'limitName' => 'Limit_Name__c',
      'maximumAllowed' => 'Maximum_Allowed__c',
      'currentlyUsed' => 'Currently_Used__c',
      'remaining' => 'Remaining__c',
      'percentUsed' => 'Percent_Used__c',
      'status' => 'Status__c',
      'sampledAt' => 'Sampled_At__c'
    };
    String sortField = sortFields.containsKey(sortBy)
      ? sortFields.get(sortBy)
      : 'Sampled_At__c';
    String direction = sortDirection == 'ASC' ? 'ASC' : 'DESC';
    queryText +=
      ' ORDER BY ' +
      sortField +
      ' ' +
      direction +
      ', Id DESC LIMIT :pageSize OFFSET :offsetRows';
    binds.put('pageSize', pageSize);
    binds.put('offsetRows', offsetRows);
    return Database.queryWithBinds(queryText, binds, AccessLevel.USER_MODE);
  }

  public Integer countHistory(
    String limitName,
    String status,
    Datetime startAt,
    Datetime endAt
  ) {
    List<String> predicates = new List<String>();
    Map<String, Object> binds = new Map<String, Object>();
    if (String.isNotBlank(limitName)) {
      predicates.add('Limit_Name__c LIKE :limitName');
      binds.put('limitName', '%' + limitName.trim() + '%');
    }
    if (
      String.isNotBlank(status) &&
      new Set<String>{ 'Normal', 'Warning', 'Critical' }.contains(status)
    ) {
      predicates.add('Status__c = :status');
      binds.put('status', status);
    }
    if (startAt != null) {
      predicates.add('Sampled_At__c >= :startAt');
      binds.put('startAt', startAt);
    }
    if (endAt != null) {
      predicates.add('Sampled_At__c <= :endAt');
      binds.put('endAt', endAt);
    }
    String queryText = 'SELECT COUNT() FROM Org_Limit__c';
    if (!predicates.isEmpty()) {
      queryText += ' WHERE ' + String.join(predicates, ' AND ');
    }
    return (Integer) Database.countQueryWithBinds(
      queryText,
      binds,
      AccessLevel.USER_MODE
    );
  }
}
