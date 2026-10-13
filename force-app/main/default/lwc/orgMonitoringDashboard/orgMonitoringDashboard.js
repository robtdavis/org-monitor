import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getDashboard from "@salesforce/apex/OrgMonitoringController.getDashboard";
import getHistory from "@salesforce/apex/OrgMonitoringController.getHistory";
import getLiveSnapshot from "@salesforce/apex/OrgMonitoringController.getLiveSnapshot";
import getDemoSnapshot from "@salesforce/apex/OrgMonitoringController.getDemoSnapshot";

const HISTORY_PAGE_SIZE = 50;
const HISTORY_STATUS_OPTIONS = [
  { label: "All statuses", value: "" },
  { label: "Normal", value: "Normal" },
  { label: "Warning", value: "Warning" },
  { label: "Critical", value: "Critical" }
];
const HISTORY_SORT_OPTIONS = [
  { label: "Sampled at", value: "sampledAt" },
  { label: "Limit name", value: "limitName" },
  { label: "Status", value: "status" },
  { label: "Percent used", value: "percentUsed" }
];
const HISTORY_SORT_DIRECTION_OPTIONS = [
  { label: "Newest / descending", value: "DESC" },
  { label: "Oldest / ascending", value: "ASC" }
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

function extractRows(result) {
  if (Array.isArray(result)) {
    return result;
  }
  if (Array.isArray(result?.rows)) {
    return result.rows;
  }
  if (Array.isArray(result?.data)) {
    return result.data;
  }
  return [];
}

function decorateRows(rows) {
  return rows.map((row, index) => ({
    ...row,
    id: row.id ?? `${row.limitName || "limit"}-${index}`,
    statusClass: statusClass(row.status),
    percentDisplay:
      row.percentUsed === null || row.percentUsed === undefined
        ? "—"
        : `${Number(row.percentUsed).toFixed(1)}%`
  }));
}

function statusClass(status) {
  const normalized = String(status || "").toLowerCase();
  if (normalized === "critical") {
    return "slds-badge slds-theme_error";
  }
  if (normalized === "warning") {
    return "slds-badge slds-theme_warning";
  }
  if (normalized === "normal") {
    return "slds-badge slds-theme_success";
  }
  return "slds-badge";
}

function countStatus(rows, statusName) {
  const target = statusName.toLowerCase();
  return rows.filter((row) => String(row.status || "").toLowerCase() === target)
    .length;
}

function latestSampleTime(rows) {
  const dates = rows.map((row) => row.sampledAt).filter(Boolean);
  return dates.sort((left, right) => new Date(right) - new Date(left))[0];
}

export default class OrgMonitoringDashboard extends LightningElement {
  @api demoMode = false;

  rows = [];
  historyRows = [];
  historyCount = 0;
  normalCount = 0;
  warningCount = 0;
  criticalCount = 0;
  retentionPeriod;
  scheduleStatus;
  nextRunAt;
  latestSampledAt;
  demoNotice;
  loadError;
  historyError;
  isLoading = true;
  isHistoryLoading = false;
  historyVisible = false;
  historyTotalCount = 0;
  liveSnapshot = false;
  historyLimitName = "";
  historyStatus = "";
  historyStartDate = "";
  historyEndDate = "";
  historySortBy = "sampledAt";
  historySortDirection = "DESC";
  historyPage = 1;

  get isDemoMode() {
    return this.demoMode === true || this.demoMode === "true";
  }

  get refreshLabel() {
    return this.isDemoMode ? "Generate New Demo Sample" : "Refresh Now";
  }

  get showHistoryButton() {
    return !this.isDemoMode;
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get hasHistoryRows() {
    return this.historyRows.length > 0;
  }

  get historyEmpty() {
    return (
      this.historyVisible &&
      !this.isHistoryLoading &&
      !this.hasHistoryRows &&
      !this.historyError
    );
  }

  get historyStatusOptions() {
    return HISTORY_STATUS_OPTIONS;
  }

  get historySortOptions() {
    return HISTORY_SORT_OPTIONS;
  }

  get historySortDirectionOptions() {
    return HISTORY_SORT_DIRECTION_OPTIONS;
  }

  get historyPageCount() {
    return Math.max(1, Math.ceil(this.historyTotalCount / HISTORY_PAGE_SIZE));
  }

  get historyPageSummary() {
    return `Page ${this.historyPage} of ${this.historyPageCount}`;
  }

  get previousPageDisabled() {
    return this.isHistoryLoading || this.historyPage <= 1;
  }

  get nextPageDisabled() {
    return this.isHistoryLoading || this.historyPage >= this.historyPageCount;
  }

  get scheduleStatusLabel() {
    return this.scheduleStatus || "Not scheduled";
  }

  get nextRunLabel() {
    return this.nextRunAt || "Not scheduled";
  }

  get retentionPeriodLabel() {
    if (!this.retentionPeriod) {
      return "Not specified";
    }
    return String(this.retentionPeriod).toUpperCase() === "FOREVER"
      ? "Keep Forever"
      : `${this.retentionPeriod}${String(this.retentionPeriod).toLowerCase().includes("day") ? "" : " days"}`;
  }

  get retentionNotice() {
    return String(this.retentionPeriod || "").toUpperCase() === "FOREVER"
      ? "Keep Forever retention can consume increasing org storage."
      : undefined;
  }

  get readingsHeading() {
    if (this.isDemoMode) {
      return "Simulated limit readings";
    }
    return this.liveSnapshot
      ? "Live limit usage"
      : "Latest captured limit readings";
  }

  get historySummary() {
    const count = this.historyTotalCount ?? this.historyCount;
    return `${count} total sample${count === 1 ? "" : "s"}`;
  }

  connectedCallback() {
    this.loadDashboard();
  }

  async loadDashboard() {
    this.isLoading = true;
    this.loadError = undefined;
    try {
      if (this.isDemoMode) {
        await this.loadDemoSample();
      } else {
        const result = await getDashboard();
        this.applyDashboard(result || {});
      }
    } catch (error) {
      this.loadError = `Unable to load monitoring dashboard: ${errorMessage(error)}`;
    } finally {
      this.isLoading = false;
    }
  }

  applyDashboard(result) {
    const rows = extractRows(result);
    this.rows = decorateRows(rows);
    this.latestSampledAt = result.latestSampledAt || latestSampleTime(rows);
    this.nextRunAt = result.nextRunAt;
    this.scheduleStatus = result.scheduleStatus;
    this.normalCount = Number(
      result.normalCount ?? countStatus(rows, "normal")
    );
    this.warningCount = Number(
      result.warningCount ?? countStatus(rows, "warning")
    );
    this.criticalCount = Number(
      result.criticalCount ?? countStatus(rows, "critical")
    );
    this.historyCount = Number(result.historyCount || 0);
    this.historyTotalCount = this.historyCount;
    this.retentionPeriod = result.retentionPeriod;
    this.demoNotice = undefined;
    this.liveSnapshot = false;
  }

  async loadDemoSample() {
    const result = await getDemoSnapshot();
    const rows = extractRows(result);
    this.rows = decorateRows(rows);
    this.latestSampledAt = result?.latestSampledAt || latestSampleTime(rows);
    this.normalCount = countStatus(rows, "normal");
    this.warningCount = countStatus(rows, "warning");
    this.criticalCount = countStatus(rows, "critical");
    this.demoNotice =
      result?.notice ||
      "Demo data is generated for preview and does not change org monitoring configuration.";
    this.liveSnapshot = false;
  }

  async handleRefresh() {
    this.isLoading = true;
    this.loadError = undefined;
    try {
      if (this.isDemoMode) {
        await this.loadDemoSample();
      } else {
        const result = await getLiveSnapshot();
        const rows = extractRows(result);
        this.rows = decorateRows(rows);
        this.latestSampledAt =
          latestSampleTime(rows) || new Date().toISOString();
        this.normalCount = countStatus(rows, "normal");
        this.warningCount = countStatus(rows, "warning");
        this.criticalCount = countStatus(rows, "critical");
        this.liveSnapshot = true;
      }
      this.showToast(
        this.isDemoMode ? "Demo sample generated" : "Dashboard refreshed",
        this.isDemoMode
          ? "A new demo sample is ready."
          : "Current live limit usage has been refreshed.",
        "success"
      );
    } catch (error) {
      this.loadError = `Unable to refresh monitoring data: ${errorMessage(error)}`;
      this.showToast("Refresh failed", this.loadError, "error");
    } finally {
      this.isLoading = false;
    }
  }

  async handleLoadHistory() {
    this.historyVisible = true;
    this.historyPage = 1;
    await this.loadHistoryPage();
  }

  handleHistoryFilterChange(event) {
    this[event.target.name] = event.target.value;
  }

  async handleApplyHistoryFilters() {
    if (
      this.historyStartDate &&
      this.historyEndDate &&
      this.historyStartDate > this.historyEndDate
    ) {
      this.showToast(
        "Check date range",
        "The start date must be on or before the end date.",
        "error"
      );
      return;
    }
    this.historyPage = 1;
    await this.loadHistoryPage();
  }

  async handlePreviousHistoryPage() {
    if (this.historyPage > 1) {
      this.historyPage -= 1;
      await this.loadHistoryPage();
    }
  }

  async handleNextHistoryPage() {
    if (this.historyPage < this.historyPageCount) {
      this.historyPage += 1;
      await this.loadHistoryPage();
    }
  }

  async loadHistoryPage() {
    this.historyVisible = true;
    this.isHistoryLoading = true;
    this.historyError = undefined;
    try {
      const request = {
        pageNumber: this.historyPage,
        pageSize: HISTORY_PAGE_SIZE,
        limitName: this.historyLimitName.trim(),
        status: this.historyStatus,
        startDate: this.historyStartDate,
        endDate: this.historyEndDate,
        sortBy: this.historySortBy,
        sortDirection: this.historySortDirection
      };
      const result = await getHistory({
        requestJson: JSON.stringify(request)
      });
      const history = result || {};
      this.historyRows = decorateRows(extractRows(history));
      this.historyTotalCount = Number(
        history.totalCount ?? this.historyRows.length
      );
    } catch (error) {
      this.historyRows = [];
      this.historyError = `Unable to load monitoring history: ${errorMessage(error)}`;
      this.showToast("History unavailable", this.historyError, "error");
    } finally {
      this.isHistoryLoading = false;
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
