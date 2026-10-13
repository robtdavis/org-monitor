public virtual with sharing class OrgLimitsProvider {
  public virtual List<OrgLimitReading> collect(
    Decimal warning,
    Decimal critical
  ) {
    List<OrgLimitReading> readings = new List<OrgLimitReading>();
    Map<String, System.OrgLimit> limitsByName = System.OrgLimits.getMap();
    if (limitsByName == null) {
      return readings;
    }
    Datetime sampledAt = System.now();

    for (String key : limitsByName.keySet()) {
      System.OrgLimit source = limitsByName.get(key);
      if (
        source == null ||
        source.getLimit() == null ||
        source.getValue() == null
      ) {
        continue;
      }
      Integer maximum = source.getLimit();
      Integer used = source.getValue();
      if (maximum <= 0) {
        continue;
      }
      OrgLimitReading reading = new OrgLimitReading();
      reading.limitName = key;
      reading.maximumAllowed = Decimal.valueOf(String.valueOf(maximum));
      reading.currentlyUsed = Decimal.valueOf(String.valueOf(used));
      reading.remaining = reading.maximumAllowed - reading.currentlyUsed;
      reading.percentUsed = (reading.currentlyUsed /
        reading.maximumAllowed *
        100)
        .setScale(2, RoundingMode.HALF_UP);
      reading.status = OrgMonitoringService.classify(
        reading.percentUsed,
        warning,
        critical
      );
      reading.sampledAt = sampledAt;
      readings.add(reading);
    }
    return readings;
  }
}
