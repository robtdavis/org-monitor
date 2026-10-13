@IsTest
private class OrgMonitoringCoreTest {
  @TestSetup
  static void setupTestData() {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    String uniqueSuffix =
      String.valueOf(Datetime.now().getTime()) +
      String.valueOf(Math.abs(Crypto.getRandomInteger()));
    User u = new User(
      Alias = 'orgmon',
      Email = 'orgmonadmin@test.org',
      EmailEncodingKey = 'UTF-8',
      LastName = 'AdminUser',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = p.Id,
      TimeZoneSidKey = 'America/New_York',
      UserName = 'orgmonadmin' + uniqueSuffix + '@test.org'
    );
    insert u;
    PermissionSet ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'Org_Monitoring_Administrator'
      LIMIT 1
    ];
    insert new PermissionSetAssignment(
      AssigneeId = u.Id,
      PermissionSetId = ps.Id
    );
  }

  @IsTest
  static void classifiesThresholdBoundariesAndOverages() {
    System.assertEquals('Normal', OrgMonitoringService.classify(69.99, 70, 90));
    System.assertEquals('Warning', OrgMonitoringService.classify(70, 70, 90));
    System.assertEquals(
      'Warning',
      OrgMonitoringService.classify(89.99, 70, 90)
    );
    System.assertEquals('Critical', OrgMonitoringService.classify(90, 70, 90));
    System.assertEquals('Critical', OrgMonitoringService.classify(125, 70, 90));
  }

  @IsTest
  static void createsSingletonAndNormalizesConfiguration() {
    System.runAs(getAdminUser()) {
      OrgMonitoringConfigService service = new OrgMonitoringConfigService();
      Org_Monitoring_Configuration__c initialized = service.initializeDefault();
      System.assertEquals('DEFAULT', initialized.Configuration_Key__c);
      System.assertEquals('Default', initialized.Name);
      System.assertEquals(initialized.Id, service.initializeDefault().Id);

      OrgMonitoringController.ConfigurationInput input = new OrgMonitoringController.ConfigurationInput();
      input.warningPercent = 65;
      input.criticalPercent = 88;
      input.active = true;
      input.daysToRun = new List<String>{ 'fri', 'MON', 'fri' };
      input.frequencyHours = '12';
      input.timeOffsetMinutes = 90;
      input.retentionPeriod = 'FOREVER';
      input.comments = 'Test configuration';
      input.emailAddresses = 'ops@example.com, OPS@example.com';
      Org_Monitoring_Configuration__c saved = service.save(input);

      System.assertEquals('MON;FRI', saved.Days_to_Run__c);
      System.assertEquals('ops@example.com', saved.Email_Addresses__c);
      System.assertEquals('FOREVER', saved.Retention_Period__c);
      System.assertEquals(
        UserInfo.getTimeZone().getID(),
        saved.Scheduling_Time_Zone__c
      );
    }
  }

  @IsTest
  static void rejectsInvalidConfiguration() {
    System.runAs(getAdminUser()) {
      OrgMonitoringController.ConfigurationInput input = validInput();
      input.criticalPercent = 65;
      try {
        new OrgMonitoringConfigService().save(input);
        System.assert(
          false,
          'Critical threshold must be greater than Warning.'
        );
      } catch (AuraHandledException expected) {
        System.assertNotEquals(null, expected);
      }

      input = validInput();
      input.frequencyHours = '1';
      input.timeOffsetMinutes = 60;
      try {
        new OrgMonitoringConfigService().save(input);
        System.assert(false, 'Offset must be less than the interval.');
      } catch (AuraHandledException expected) {
        System.assertNotEquals(null, expected);
      }

      input = validInput();
      input.emailAddresses = 'not-an-address';
      try {
        new OrgMonitoringConfigService().save(input);
        System.assert(false, 'Invalid email addresses must be rejected.');
      } catch (AuraHandledException expected) {
        System.assertNotEquals(null, expected);
      }
    }
  }

  @IsTest
  static void buildsSchedulesAtConfiguredOffsetAcrossSupportedIntervals() {
    Map<String, String> expectedHours = new Map<String, String>{
      '1' => '0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23',
      '2' => '1,3,5,7,9,11,13,15,17,19,21,23',
      '4' => '1,5,9,13,17,21',
      '6' => '1,7,13,19',
      '8' => '1,9,17',
      '12' => '1,13',
      '24' => '1'
    };
    for (String frequency : expectedHours.keySet()) {
      Integer offset = frequency == '1' ? 15 : 90;
      Integer minute = Math.mod(offset, 60);
      Org_Monitoring_Configuration__c config = new Org_Monitoring_Configuration__c(
        Frequency_Hours__c = frequency,
        Time_Offset_Minutes__c = offset,
        Days_to_Run__c = 'MON;WED;FRI'
      );
      String cron = OrgMonitoringScheduleService.buildCron(config);
      System.assertEquals(
        '0 ' + minute + ' ' + expectedHours.get(frequency) + ' ? * MON,WED,FRI',
        cron
      );
    }
  }

  @IsTest
  static void persistsScheduledSnapshotAndRunSummary() {
    System.runAs(getAdminUser()) {
      Org_Monitoring_Configuration__c config = new Org_Monitoring_Configuration__c(
        Name = 'Default',
        Configuration_Key__c = 'DEFAULT',
        Warning_Percent_Value__c = 70,
        Critical_Percent_Value__c = 90,
        Active__c = true,
        Days_to_Run__c = 'SUN;MON;TUE;WED;THU;FRI;SAT',
        Frequency_Hours__c = '24',
        Retention_Period__c = '90',
        Time_Offset_Minutes__c = 0,
        Scheduling_Time_Zone__c = UserInfo.getTimeZone().getID()
      );
      insert config;
      OrgMonitoringService.limitsProvider = new FixtureProvider(
        new List<OrgLimitReading>{
          reading('NormalLimit', 10000, 69.99),
          reading('WarningLimit', 10000, 70),
          reading('CriticalLimit', 10000, 125)
        }
      );

      Test.startTest();
      new OrgMonitoringService().runScheduled();
      Test.stopTest();

      Org_Monitoring_Run__c run = [
        SELECT
          Status__c,
          Read_Count__c,
          Stored_Count__c,
          Execution_Key__c,
          Warning_Count__c,
          Critical_Count__c
        FROM Org_Monitoring_Run__c
        LIMIT 1
      ];
      System.assertEquals('Completed', run.Status__c);
      System.assertEquals(Decimal.valueOf('3'), run.Read_Count__c);
      System.assertEquals(run.Read_Count__c, run.Stored_Count__c);
      System.assertEquals(12, run.Execution_Key__c.length());
      System.assertEquals(3, [SELECT COUNT() FROM Org_Limit__c]);
      System.assertEquals(Decimal.valueOf('1'), run.Warning_Count__c);
      System.assertEquals(Decimal.valueOf('1'), run.Critical_Count__c);
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM Org_Limit__c
          WHERE Status__c = 'Normal' AND Percent_Used__c = 69.99
        ]
      );
    }
  }

  @IsTest
  static void sendsOneConsolidatedMessageForAlerts() {
    List<OrgLimitReading> readings = new List<OrgLimitReading>{
      reading('WarningLimit', 10000, 80),
      reading('CriticalLimit', 10000, 110)
    };
    Test.startTest();
    OrgMonitoringEmailService.sendAlerts(
      readings,
      new List<String>{ 'monitor@example.com' },
      70,
      90,
      System.now()
    );
    Integer emailsSent = Limits.getEmailInvocations();
    Test.stopTest();
    System.assertEquals(1, emailsSent);
  }

  @IsTest
  static void sendsAlertsInDemoModeWithBanner() {
    List<OrgLimitReading> readings = new List<OrgLimitReading>{
      reading('WarningLimit', 10000, 80),
      reading('CriticalLimit', 10000, 110)
    };
    Test.startTest();
    OrgMonitoringEmailService.sendAlerts(
      readings,
      new List<String>{ 'monitor@example.com' },
      70,
      90,
      System.now(),
      true
    );
    Integer emailsSent = Limits.getEmailInvocations();
    Test.stopTest();
    System.assertEquals(1, emailsSent);
  }

  @IsTest
  static void demoSnapshotSendsEmailWhenRecipientsConfigured() {
    System.runAs(getAdminUser()) {
      Org_Monitoring_Configuration__c config = new Org_Monitoring_Configuration__c(
        Name = 'Default',
        Configuration_Key__c = 'DEFAULT',
        Warning_Percent_Value__c = 70,
        Critical_Percent_Value__c = 90,
        Active__c = false,
        Days_to_Run__c = 'MON',
        Frequency_Hours__c = '24',
        Retention_Period__c = '90',
        Time_Offset_Minutes__c = 0,
        Email_Addresses__c = 'demo.recipient@example.com',
        Scheduling_Time_Zone__c = UserInfo.getTimeZone().getID()
      );
      insert config;

      Test.startTest();
      OrgMonitoringController.DemoSnapshotView demo = OrgMonitoringController.getDemoSnapshot();
      Integer emailsSent = Limits.getEmailInvocations();
      Test.stopTest();

      if (!demo.rows.isEmpty()) {
        System.assertEquals(1, emailsSent);
        System.assert(
          demo.notice.contains('Demo alert email sent') ||
          demo.notice.contains('Demo email notice')
        );
      }
    }
  }

  @IsTest
  static void controllerReadEndpointsAndDemoHaveNoSideEffects() {
    System.runAs(getAdminUser()) {
      Org_Monitoring_Configuration__c config = new Org_Monitoring_Configuration__c(
        Name = 'Default',
        Configuration_Key__c = 'DEFAULT',
        Warning_Percent_Value__c = 70,
        Critical_Percent_Value__c = 90,
        Active__c = false,
        Days_to_Run__c = 'MON',
        Frequency_Hours__c = '24',
        Retention_Period__c = '90',
        Time_Offset_Minutes__c = 0,
        Scheduling_Time_Zone__c = UserInfo.getTimeZone().getID()
      );
      insert config;
      Org_Limit__c history = historyRow(System.now());
      history.Limit_Name__c = 'DailyApiRequests';
      insert history;
      Integer historyBefore = [SELECT COUNT() FROM Org_Limit__c];
      Integer monitorJobsBefore = [
        SELECT COUNT()
        FROM CronTrigger
        WHERE CronJobDetail.Name LIKE 'OrgMonitoring-MONITOR-%'
      ];

      OrgMonitoringController.ConfigurationView configuration = OrgMonitoringController.getConfiguration();
      OrgMonitoringController.DashboardView dashboard = OrgMonitoringController.getDashboard();
      OrgMonitoringController.HistoryResponse page = OrgMonitoringController.getHistory(
        JSON.serialize(
          new Map<String, Object>{
            'limitName' => 'Daily',
            'status' => 'Normal',
            'pageSize' => 25,
            'pageNumber' => 1,
            'sortBy' => 'sampledAt',
            'sortDirection' => 'DESC'
          }
        )
      );
      List<OrgLimitReading> live = OrgMonitoringController.getLiveSnapshot();
      OrgMonitoringController.DemoSnapshotView demo = OrgMonitoringController.getDemoSnapshot();

      System.assertEquals(Decimal.valueOf('70'), configuration.warningPercent);
      System.assertEquals(1, dashboard.historyCount);
      System.assertEquals(1, page.totalCount);
      System.assertEquals('DailyApiRequests', page.rows[0].limitName);
      System.assertNotEquals(null, live);
      System.assert(demo.rows.size() <= 5);
      if (demo.rows.size() >= 2) {
        Set<String> demoNames = new Set<String>();
        Boolean hasWarning = false;
        Boolean hasCritical = false;
        for (OrgLimitReading reading : demo.rows) {
          demoNames.add(reading.limitName);
          hasWarning = hasWarning || reading.status == 'Warning';
          hasCritical = hasCritical || reading.status == 'Critical';
        }
        System.assertEquals(demo.rows.size(), demoNames.size());
        System.assert(hasWarning);
        System.assert(hasCritical);
      }
      System.assertEquals(historyBefore, [SELECT COUNT() FROM Org_Limit__c]);
      System.assertEquals(
        monitorJobsBefore,
        [
          SELECT COUNT()
          FROM CronTrigger
          WHERE CronJobDetail.Name LIKE 'OrgMonitoring-MONITOR-%'
        ]
      );
      System.assertEquals(0, Limits.getEmailInvocations());
    }
  }

  @IsTest
  static void monitoringScheduleReconcileIsIdempotentAndDeactivates() {
    System.runAs(getAdminUser()) {
      Org_Monitoring_Configuration__c config = new Org_Monitoring_Configuration__c(
        Active__c = true,
        Frequency_Hours__c = '6',
        Time_Offset_Minutes__c = 90,
        Days_to_Run__c = 'SUN;TUE;THU',
        Scheduling_Time_Zone__c = UserInfo.getTimeZone().getID()
      );
      OrgMonitoringScheduleService service = new OrgMonitoringScheduleService();
      Test.startTest();
      service.reconcileMonitoring(config);
      service.reconcileMonitoring(config);
      List<CronTrigger> jobs = [
        SELECT Id
        FROM CronTrigger
        WHERE
          CronJobDetail.Name LIKE 'OrgMonitoring-MONITOR-%'
          AND State IN ('WAITING', 'ACQUIRED', 'PAUSED', 'BLOCKED')
      ];
      System.assertEquals(1, jobs.size());
      config.Active__c = false;
      service.reconcileMonitoring(config);
      System.assertEquals(
        0,
        new OrgMonitoringScheduleSelector().monitoringJobs().size()
      );
      service.ensurePurgeSchedule();
      service.ensurePurgeSchedule();
      System.assertEquals(
        1,
        new OrgMonitoringScheduleSelector().purgeJobs().size()
      );
      service.abortAllJobs();
      System.assertEquals(
        0,
        new OrgMonitoringScheduleSelector().purgeJobs().size()
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void purgesOnlyRowsOlderThanActualCutoff() {
    System.runAs(getAdminUser()) {
      Datetime nowAt = System.now();
      insert new List<Org_Limit__c>{
        historyRow(nowAt.addDays(-31)),
        historyRow(nowAt.addDays(-29))
      };
      Test.startTest();
      Database.executeBatch(new OrgMonitoringPurgeJob(nowAt.addDays(-30)), 1);
      Test.stopTest();

      System.assertEquals(1, [SELECT COUNT() FROM Org_Limit__c]);
      System.assertEquals(
        nowAt.addDays(-29).date(),
        [SELECT Sampled_At__c FROM Org_Limit__c LIMIT 1].Sampled_At__c.date()
      );
    }
  }

  @IsTest
  static void keepForeverDoesNotDeleteHistory() {
    System.runAs(getAdminUser()) {
      Org_Monitoring_Configuration__c config = new Org_Monitoring_Configuration__c(
        Name = 'Default',
        Configuration_Key__c = 'DEFAULT',
        Warning_Percent_Value__c = 70,
        Critical_Percent_Value__c = 90,
        Active__c = false,
        Days_to_Run__c = 'MON',
        Frequency_Hours__c = '24',
        Retention_Period__c = 'FOREVER',
        Time_Offset_Minutes__c = 0,
        Scheduling_Time_Zone__c = UserInfo.getTimeZone().getID()
      );
      insert config;
      insert historyRow(System.now().addYears(-5));

      Test.startTest();
      new OrgMonitoringPurgeJob().execute((SchedulableContext) null);
      Test.stopTest();

      System.assertEquals(1, [SELECT COUNT() FROM Org_Limit__c]);
    }
  }

  @IsTest
  static void purgesRunSummariesUsingTheHistoryCutoff() {
    System.runAs(getAdminUser()) {
      Datetime nowAt = System.now();
      insert new List<Org_Monitoring_Run__c>{
        new Org_Monitoring_Run__c(
          Execution_Key__c = 'OLD-RUN',
          Started_At__c = nowAt.addDays(-31),
          Status__c = 'Completed'
        ),
        new Org_Monitoring_Run__c(
          Execution_Key__c = 'NEW-RUN',
          Started_At__c = nowAt.addDays(-29),
          Status__c = 'Completed'
        )
      };

      Test.startTest();
      Database.executeBatch(
        new OrgMonitoringRunPurgeBatch(nowAt.addDays(-30)),
        1
      );
      Test.stopTest();

      System.assertEquals(1, [SELECT COUNT() FROM Org_Monitoring_Run__c]);
      System.assertEquals(
        'NEW-RUN',
        [SELECT Execution_Key__c FROM Org_Monitoring_Run__c LIMIT 1]
        .Execution_Key__c
      );
    }
  }

  @IsTest
  static void schedulerSafelyReturnsWithoutConfiguration() {
    System.runAs(getAdminUser()) {
      Test.startTest();
      new OrgMonitoringScheduler().execute((SchedulableContext) null);
      Test.stopTest();
      System.assertEquals(0, [SELECT COUNT() FROM Org_Monitoring_Run__c]);
    }
  }

  @IsTest
  static void controllerInitializesSavesAndAbortsConfiguration() {
    System.runAs(getAdminUser()) {
      Test.startTest();
      OrgMonitoringController.ConfigurationView initialView = OrgMonitoringController.initializeConfiguration();
      System.assertEquals(70, initialView.warningPercent);
      System.assertEquals(90, initialView.criticalPercent);

      OrgMonitoringController.ConfigurationInput input = validInput();
      input.warningPercent = 68;
      input.criticalPercent = 89;
      input.emailAddresses = 'admin@example.com';
      OrgMonitoringController.ConfigurationView savedView = OrgMonitoringController.saveConfiguration(
        JSON.serialize(input)
      );
      System.assertEquals(68, savedView.warningPercent);
      System.assertEquals(89, savedView.criticalPercent);

      OrgMonitoringController.ConfigurationView abortedView = OrgMonitoringController.abortScheduledJobs();
      System.assertEquals(null, abortedView.nextRunAt);
      Test.stopTest();
    }
  }

  @IsTest
  static void purgeJobExecutesWithConfiguredRetention() {
    System.runAs(getAdminUser()) {
      Org_Monitoring_Configuration__c config = new Org_Monitoring_Configuration__c(
        Name = 'Default',
        Configuration_Key__c = 'DEFAULT',
        Warning_Percent_Value__c = 70,
        Critical_Percent_Value__c = 90,
        Active__c = false,
        Days_to_Run__c = 'MON',
        Frequency_Hours__c = '24',
        Retention_Period__c = '30',
        Time_Offset_Minutes__c = 0,
        Scheduling_Time_Zone__c = UserInfo.getTimeZone().getID()
      );
      insert config;
      insert historyRow(System.now().addDays(-40));

      Test.startTest();
      new OrgMonitoringPurgeJob().execute((SchedulableContext) null);
      Test.stopTest();

      System.assertEquals(0, [SELECT COUNT() FROM Org_Limit__c]);
    }
  }

  private static OrgMonitoringController.ConfigurationInput validInput() {
    OrgMonitoringController.ConfigurationInput input = new OrgMonitoringController.ConfigurationInput();
    input.warningPercent = 70;
    input.criticalPercent = 90;
    input.active = true;
    input.daysToRun = new List<String>{ 'MON' };
    input.frequencyHours = '24';
    input.timeOffsetMinutes = 0;
    input.retentionPeriod = '90';
    input.emailAddresses = '';
    return input;
  }

  private static Org_Limit__c historyRow(Datetime sampledAt) {
    return new Org_Limit__c(
      Limit_Name__c = 'TestLimit',
      Maximum_Allowed__c = 100,
      Currently_Used__c = 50,
      Remaining__c = 50,
      Percent_Used__c = 50,
      Status__c = 'Normal',
      Sampled_At__c = sampledAt,
      Warning_Threshold__c = 70,
      Critical_Threshold__c = 90,
      Run_Identifier__c = 'TEST'
    );
  }

  private static User getAdminUser() {
    return [
      SELECT Id, TimeZoneSidKey
      FROM User
      WHERE UserName LIKE 'orgmonadmin%@test.org'
      LIMIT 1
    ];
  }

  private static OrgLimitReading reading(
    String name,
    Decimal maximum,
    Decimal percent
  ) {
    OrgLimitReading result = new OrgLimitReading();
    result.limitName = name;
    result.maximumAllowed = maximum;
    result.currentlyUsed = (maximum *
      percent /
      100)
      .setScale(0, RoundingMode.HALF_UP);
    result.remaining = maximum - result.currentlyUsed;
    result.percentUsed = (result.currentlyUsed /
      maximum *
      100)
      .setScale(2, RoundingMode.HALF_UP);
    result.status = OrgMonitoringService.classify(result.percentUsed, 70, 90);
    return result;
  }

  private class FixtureProvider extends OrgLimitsProvider {
    private List<OrgLimitReading> readings;

    FixtureProvider(List<OrgLimitReading> fixture) {
      readings = fixture;
    }

    public override List<OrgLimitReading> collect(
      Decimal warning,
      Decimal critical
    ) {
      return readings;
    }
  }
}
