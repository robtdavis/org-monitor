import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import isAdmin from "@salesforce/customPermission/Manage_Org_Monitoring";
import getConfiguration from "@salesforce/apex/OrgMonitoringController.getConfiguration";
import initializeConfiguration from "@salesforce/apex/OrgMonitoringController.initializeConfiguration";
import saveConfiguration from "@salesforce/apex/OrgMonitoringController.saveConfiguration";
import abortScheduledJobs from "@salesforce/apex/OrgMonitoringController.abortScheduledJobs";

const DAYS = [
  { label: "Sunday", value: "SUN" },
  { label: "Monday", value: "MON" },
  { label: "Tuesday", value: "TUE" },
  { label: "Wednesday", value: "WED" },
  { label: "Thursday", value: "THU" },
  { label: "Friday", value: "FRI" },
  { label: "Saturday", value: "SAT" }
];

const DEFAULTS = {
  warningPercent: 70,
  criticalPercent: 90,
  active: true,
  daysToRun: ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"],
  frequencyHours: "24",
  timeOffsetMinutes: 0,
  retentionPeriod: "90",
  comments: "",
  emailAddresses: ""
};

const FREQUENCY_OPTIONS = [
  { label: "Every hour", value: "1" },
  { label: "Every 2 hours", value: "2" },
  { label: "Every 4 hours", value: "4" },
  { label: "Every 6 hours", value: "6" },
  { label: "Every 8 hours", value: "8" },
  { label: "Every 12 hours", value: "12" },
  { label: "Every 24 hours", value: "24" }
];

const RETENTION_OPTIONS = [
  { label: "30 days", value: "30" },
  { label: "60 days", value: "60" },
  { label: "90 days", value: "90" },
  { label: "120 days", value: "120" },
  { label: "Keep Forever", value: "FOREVER" }
];

function errorMessage(error) {
  const body = error?.body;
  if (Array.isArray(body)) {
    return (
      body
        .map((item) => item.message)
        .filter(Boolean)
        .join(", ") || "An unexpected error occurred."
    );
  }
  return body?.message || error?.message || "An unexpected error occurred.";
}

function parseDays(value) {
  const aliases = {
    SUNDAY: "SUN",
    MONDAY: "MON",
    TUESDAY: "TUE",
    WEDNESDAY: "WED",
    THURSDAY: "THU",
    FRIDAY: "FRI",
    SATURDAY: "SAT"
  };
  if (Array.isArray(value)) {
    value = value.join(";");
  }
  if (typeof value === "string") {
    if (!value.trim()) {
      return [];
    }
    const normalized = new Set(
      value
        .split(";")
        .map((day) => day.trim().toUpperCase())
        .map((day) => aliases[day] || day)
    );
    return DAYS.map(({ value: day }) => day).filter((day) =>
      normalized.has(day)
    );
  }
  return [...DEFAULTS.daysToRun];
}

function parseEmails(value) {
  if (Array.isArray(value)) {
    return value.join("; ");
  }
  return typeof value === "string" ? value : "";
}

export default class OrgMonitoringConfiguration extends LightningElement {
  isLoading = true;
  isSaving = false;
  isAborting = false;
  isInitializing = false;
  accessDenied = false;
  requiresInitialization = false;
  loadError;
  hasConfiguration = false;
  initialValues;
  warningPercent = DEFAULTS.warningPercent;
  criticalPercent = DEFAULTS.criticalPercent;
  active = DEFAULTS.active;
  daysToRun = [...DEFAULTS.daysToRun];
  frequencyHours = DEFAULTS.frequencyHours;
  timeOffsetMinutes = DEFAULTS.timeOffsetMinutes;
  retentionPeriod = DEFAULTS.retentionPeriod;
  comments = DEFAULTS.comments;
  emailAddresses = DEFAULTS.emailAddresses;
  schedulingTimeZone;
  nextRunAt;
  scheduleStatus;

  get isAdmin() {
    return Boolean(isAdmin);
  }

  get isActionDisabled() {
    return this.isSaving || this.isAborting;
  }

  get dayOptions() {
    return DAYS.map((day) => ({
      ...day,
      checked: this.daysToRun.includes(day.value)
    }));
  }

  get frequencyOptions() {
    return FREQUENCY_OPTIONS;
  }

  get retentionOptions() {
    return RETENTION_OPTIONS;
  }

  get scheduleStatusLabel() {
    return this.scheduleStatus || "Not scheduled";
  }

  get schedulingTimeZoneLabel() {
    return this.schedulingTimeZone || "Not specified";
  }

  get nextRunLabel() {
    return this.nextRunAt || "Not scheduled";
  }

  get hasNextRunAt() {
    return Boolean(this.nextRunAt);
  }

  connectedCallback() {
    this.loadConfiguration();
  }

  async loadConfiguration() {
    if (!this.isAdmin) {
      this.accessDenied = true;
      this.isLoading = false;
      this.hasConfiguration = false;
      return;
    }
    this.isLoading = true;
    this.loadError = undefined;
    this.requiresInitialization = false;
    try {
      const result = await getConfiguration();
      if (
        !result ||
        result.warningPercent === null ||
        result.warningPercent === undefined
      ) {
        this.requiresInitialization = true;
        this.hasConfiguration = false;
        return;
      }
      this.applyConfiguration(result || {});
      this.hasConfiguration = true;
    } catch (error) {
      this.loadError = `Unable to load monitoring configuration: ${errorMessage(error)}`;
      this.hasConfiguration = false;
    } finally {
      this.isLoading = false;
    }
  }

  async handleInitialize() {
    if (!this.isAdmin || this.isInitializing) {
      return;
    }
    this.isInitializing = true;
    try {
      await initializeConfiguration();
      await this.loadConfiguration();
      if (this.hasConfiguration) {
        this.showToast(
          "Configuration initialized",
          "The default org monitoring configuration is ready.",
          "success"
        );
      } else if (this.loadError) {
        this.showToast("Initialization incomplete", this.loadError, "error");
      }
    } catch (error) {
      this.loadError = `Unable to initialize monitoring configuration: ${errorMessage(error)}`;
      this.showToast("Initialization failed", this.loadError, "error");
    } finally {
      this.isInitializing = false;
    }
  }

  applyConfiguration(config) {
    this.warningPercent = config.warningPercent ?? DEFAULTS.warningPercent;
    this.criticalPercent = config.criticalPercent ?? DEFAULTS.criticalPercent;
    this.active = config.active ?? DEFAULTS.active;
    this.daysToRun = parseDays(config.daysToRun);
    this.frequencyHours = String(
      config.frequencyHours ?? DEFAULTS.frequencyHours
    );
    this.timeOffsetMinutes =
      config.timeOffsetMinutes ?? DEFAULTS.timeOffsetMinutes;
    this.retentionPeriod = String(
      config.retentionPeriod ?? DEFAULTS.retentionPeriod
    );
    this.comments = config.comments ?? DEFAULTS.comments;
    this.emailAddresses = parseEmails(config.emailAddresses);
    this.schedulingTimeZone = config.schedulingTimeZone;
    this.nextRunAt = config.nextRunAt;
    this.scheduleStatus = config.scheduleStatus;
    this.initialValues = this.snapshotValues();
  }

  snapshotValues() {
    return {
      warningPercent: this.warningPercent,
      criticalPercent: this.criticalPercent,
      active: this.active,
      daysToRun: [...this.daysToRun],
      frequencyHours: this.frequencyHours,
      timeOffsetMinutes: this.timeOffsetMinutes,
      retentionPeriod: this.retentionPeriod,
      comments: this.comments,
      emailAddresses: this.emailAddresses
    };
  }

  handleFieldChange(event) {
    const { name, type, checked, value } = event.target;
    this[name] = name === "active" || type === "checkbox" ? checked : value;
  }

  handleDayChange(event) {
    const day = event.target.value;
    const selected = new Set(this.daysToRun);
    if (event.target.checked) {
      selected.add(day);
    } else {
      selected.delete(day);
    }
    this.daysToRun = DAYS.map(({ value }) => value).filter((value) =>
      selected.has(value)
    );
  }

  handleReset() {
    if (this.initialValues) {
      this.warningPercent = this.initialValues.warningPercent;
      this.criticalPercent = this.initialValues.criticalPercent;
      this.active = this.initialValues.active;
      this.daysToRun = [...this.initialValues.daysToRun];
      this.frequencyHours = this.initialValues.frequencyHours;
      this.timeOffsetMinutes = this.initialValues.timeOffsetMinutes;
      this.retentionPeriod = this.initialValues.retentionPeriod;
      this.comments = this.initialValues.comments;
      this.emailAddresses = this.initialValues.emailAddresses;
    }
  }

  validateForm() {
    const inputs = [
      ...this.template.querySelectorAll(
        "lightning-input, lightning-combobox, lightning-textarea"
      )
    ];
    const nativeValid = inputs.reduce((valid, input) => {
      input.reportValidity();
      return input.checkValidity() && valid;
    }, true);
    const warning = Number(this.warningPercent);
    const critical = Number(this.criticalPercent);
    if (!nativeValid) {
      return false;
    }
    if (
      !Number.isFinite(warning) ||
      !Number.isFinite(critical) ||
      warning < 0 ||
      warning > 100 ||
      critical < 0 ||
      critical > 100 ||
      critical <= warning
    ) {
      this.showToast(
        "Check thresholds",
        "Critical threshold must be greater than warning and both must be from 0 to 100.",
        "error"
      );
      return false;
    }
    if (this.active && this.daysToRun.length === 0) {
      this.showToast(
        "Select a run day",
        "Choose at least one day for monitoring to run.",
        "error"
      );
      return false;
    }
    const offset = Number(this.timeOffsetMinutes);
    const frequency = Number(this.frequencyHours);
    if (!Number.isInteger(offset) || offset < 0 || offset >= frequency * 60) {
      this.showToast(
        "Check time offset",
        "Time offset must be a whole number of minutes, at least 0, and less than the selected frequency in minutes.",
        "error"
      );
      return false;
    }
    if (this.isAdmin && !this.areEmailsValid(this.emailAddresses)) {
      this.showToast(
        "Check email addresses",
        "Enter valid email addresses separated by commas or semicolons.",
        "error"
      );
      return false;
    }
    return true;
  }

  areEmailsValid(value) {
    const emails = value
      .split(/[;,]/)
      .map((email) => email.trim())
      .filter(Boolean);
    return emails.every((email) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email));
  }

  async handleSave() {
    if (!this.isAdmin) {
      this.showToast(
        "Access restricted",
        "Only authorized administrators can edit org monitoring configuration.",
        "error"
      );
      return;
    }
    if (!this.validateForm()) {
      return;
    }
    const request = {
      warningPercent: Number(this.warningPercent),
      criticalPercent: Number(this.criticalPercent),
      active: Boolean(this.active),
      daysToRun: [...this.daysToRun],
      frequencyHours: String(this.frequencyHours),
      timeOffsetMinutes: Number(this.timeOffsetMinutes),
      retentionPeriod: String(this.retentionPeriod),
      comments: this.comments || "",
      emailAddresses: [
        ...new Map(
          this.emailAddresses
            .split(/[;,]/)
            .map((email) => email.trim())
            .filter(Boolean)
            .map((email) => [email.toLowerCase(), email])
        ).values()
      ].join(",")
    };

    this.isSaving = true;
    try {
      const result = await saveConfiguration({
        requestJson: JSON.stringify(request)
      });
      if (result && typeof result === "object") {
        this.applyConfiguration({
          schedulingTimeZone: this.schedulingTimeZone,
          nextRunAt: this.nextRunAt,
          scheduleStatus: this.scheduleStatus,
          ...request,
          ...result
        });
      } else {
        this.initialValues = this.snapshotValues();
      }
      this.showToast(
        "Configuration saved",
        "Org monitoring settings were saved successfully.",
        "success"
      );
    } catch (error) {
      this.showToast(
        "Save failed",
        `Unable to save monitoring configuration: ${errorMessage(error)}`,
        "error"
      );
    } finally {
      this.isSaving = false;
    }
  }

  async handleAbortJobs() {
    if (!this.isAdmin || this.isActionDisabled) {
      return;
    }
    this.isAborting = true;
    try {
      const result = await abortScheduledJobs();
      if (result && typeof result === "object") {
        this.applyConfiguration(result);
      }
      this.showToast(
        "Scheduled Jobs Deleted",
        "All Org Monitoring scheduled jobs have been deleted.",
        "success"
      );
    } catch (error) {
      this.showToast(
        "Delete Failed",
        `Unable to delete scheduled jobs: ${errorMessage(error)}`,
        "error"
      );
    } finally {
      this.isAborting = false;
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
