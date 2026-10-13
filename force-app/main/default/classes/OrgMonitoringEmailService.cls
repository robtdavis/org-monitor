public without sharing class OrgMonitoringEmailService {
  public static void sendAlerts(
    List<OrgLimitReading> readings,
    List<String> recipients,
    Decimal warning,
    Decimal critical,
    Datetime sampledAt
  ) {
    sendAlerts(readings, recipients, warning, critical, sampledAt, false);
  }

  public static void sendAlerts(
    List<OrgLimitReading> readings,
    List<String> recipients,
    Decimal warning,
    Decimal critical,
    Datetime sampledAt,
    Boolean isDemo
  ) {
    List<OrgLimitReading> alerts = new List<OrgLimitReading>();
    String highestSeverity = 'WARNING';
    for (OrgLimitReading reading : readings) {
      if (reading.status == 'Warning' || reading.status == 'Critical') {
        alerts.add(reading);
        if (reading.status == 'Critical') {
          highestSeverity = 'CRITICAL';
        }
      }
    }
    if (alerts.isEmpty() || recipients.isEmpty()) {
      return;
    }
    for (Integer left = 0; left < alerts.size(); left++) {
      for (Integer right = left + 1; right < alerts.size(); right++) {
        Boolean swap =
          alerts[left].status != 'Critical' &&
          alerts[right].status == 'Critical';
        if (
          !swap &&
          alerts[left].status == alerts[right].status &&
          alerts[right].percentUsed > alerts[left].percentUsed
        ) {
          swap = true;
        }
        if (swap) {
          OrgLimitReading displaced = alerts[left];
          alerts[left] = alerts[right];
          alerts[right] = displaced;
        }
      }
    }
    String orgName = UserInfo.getOrganizationName();
    String timezone = UserInfo.getTimeZone().getDisplayName();
    String stamp = sampledAt.format(
      'yyyy-MM-dd HH:mm z',
      UserInfo.getTimeZone().getID()
    );
    String demoBannerHtml = isDemo
      ? '<div style="background-color:#c23934;color:#ffffff;text-align:center;padding:12px 16px;font-size:18px;font-weight:bold;letter-spacing:1px;margin-bottom:16px;border-radius:4px;font-family:Arial,sans-serif;">DEMO - FOR TESTING ONLY</div>'
      : '';
    String body =
      '<html><body>' +
      demoBannerHtml +
      '<h2>Org Monitoring — ' +
      escape(orgName) +
      '</h2>' +
      '<p>Sampled ' +
      escape(stamp) +
      '</p><table style="border-collapse:collapse">' +
      '<thead><tr><th>Limit Name</th><th>Max Allowed</th><th>Currently Used</th>' +
      '<th>Remaining Calls</th><th>Percent Currently Used</th><th>Status</th></tr></thead><tbody>';
    for (OrgLimitReading row : alerts) {
      String color = row.status == 'Critical' ? '#fce8e6' : '#fff4ce';
      body +=
        '<tr style="background-color:' +
        color +
        '"><td>' +
        escape(row.limitName) +
        '</td><td>' +
        row.maximumAllowed.format() +
        '</td><td>' +
        row.currentlyUsed.format() +
        '</td><td>' +
        row.remaining.format() +
        '</td><td>' +
        row.percentUsed.format() +
        '%</td><td>' +
        escape(row.status) +
        '</td></tr>';
    }
    body +=
      '</tbody></table><p>Warning threshold: ' +
      warning.format() +
      '%; Critical threshold: ' +
      critical.format() +
      '%; Time zone: ' +
      escape(timezone) +
      '</p></body></html>';
    String demoBannerText = isDemo
      ? '**************************************************\n' +
        '***         DEMO - FOR TESTING ONLY            ***\n' +
        '**************************************************\n\n'
      : '';
    String plainText =
      demoBannerText +
      'Org Monitoring alerts for ' +
      orgName +
      ' at ' +
      stamp +
      '. Warning threshold: ' +
      warning.format() +
      '%, Critical threshold: ' +
      critical.format() +
      '%.\n';
    for (OrgLimitReading row : alerts) {
      plainText +=
        row.limitName +
        ' | Max ' +
        row.maximumAllowed.format() +
        ' | Used ' +
        row.currentlyUsed.format() +
        ' | Remaining ' +
        row.remaining.format() +
        ' | ' +
        row.percentUsed.format() +
        '% | ' +
        row.status +
        '\n';
    }
    Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
    message.setToAddresses(recipients);
    String subjectPrefix = isDemo
      ? '[Org Monitoring][DEMO - FOR TESTING ONLY][' + highestSeverity + '] '
      : '[Org Monitoring][' + highestSeverity + '] ';
    message.setSubject(subjectPrefix + orgName + ' — ' + stamp);
    message.setHtmlBody(body);
    message.setPlainTextBody(plainText);
    Messaging.SendEmailResult[] results = Messaging.sendEmail(
      new List<Messaging.SingleEmailMessage>{ message },
      false
    );
    for (Messaging.SendEmailResult result : results) {
      if (!result.isSuccess()) {
        List<String> messages = new List<String>();
        for (Messaging.SendEmailError error : result.getErrors()) {
          messages.add(error.getMessage());
        }
        throw new EmailException(String.join(messages, '; '));
      }
    }
  }

  public class EmailException extends Exception {
  }

  private static String escape(String value) {
    if (value == null) {
      return '';
    }
    return value.replace('&', '&amp;')
      .replace('<', '&lt;')
      .replace('>', '&gt;')
      .replace('"', '&quot;')
      .replace('\'', '&#39;');
  }
}
