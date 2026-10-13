import { createElement } from "lwc";
import OrgMonitoringDashboard from "c/orgMonitoringDashboard";
import getDashboard from "@salesforce/apex/OrgMonitoringController.getDashboard";
import getHistory from "@salesforce/apex/OrgMonitoringController.getHistory";
import getLiveSnapshot from "@salesforce/apex/OrgMonitoringController.getLiveSnapshot";
import getDemoSnapshot from "@salesforce/apex/OrgMonitoringController.getDemoSnapshot";

jest.mock(
  "@salesforce/apex/OrgMonitoringController.getDashboard",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrgMonitoringController.getLiveSnapshot",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrgMonitoringController.getDemoSnapshot",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrgMonitoringController.getHistory",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = () =>
  Array.from({ length: 5 }).reduce(
    (promise) => promise.then(() => undefined),
    Promise.resolve()
  );
const sampleRows = [
  {
    id: "api",
    limitName: "API Requests",
    maximumAllowed: 100,
    currentlyUsed: 60,
    remaining: 40,
    percentUsed: 60,
    status: "Normal",
    sampledAt: "2026-10-12T12:00:00.000Z"
  }
];

describe("c-org-monitoring-dashboard", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("loads dashboard data and refreshes from the read-only live endpoint", async () => {
    getDashboard.mockResolvedValue({
      rows: sampleRows,
      normalCount: 1,
      warningCount: 0,
      criticalCount: 0,
      historyCount: 3,
      retentionPeriod: "30 days",
      scheduleStatus: "Scheduled"
    });
    getLiveSnapshot.mockResolvedValue(sampleRows);

    const element = createElement("c-org-monitoring-dashboard", {
      is: OrgMonitoringDashboard
    });
    document.body.appendChild(element);
    await flushPromises();

    expect(getDashboard).toHaveBeenCalledTimes(1);
    expect(element.shadowRoot.textContent).toContain("API Requests");
    element.shadowRoot.querySelector("lightning-button").click();
    await flushPromises();

    expect(getLiveSnapshot).toHaveBeenCalledTimes(1);
  });

  it("regenerates demo data without calling production dashboard endpoints", async () => {
    getDemoSnapshot.mockResolvedValue({
      rows: sampleRows,
      notice: "Generated sample"
    });

    const element = createElement("c-org-monitoring-dashboard", {
      is: OrgMonitoringDashboard
    });
    element.demoMode = true;
    document.body.appendChild(element);
    await flushPromises();

    expect(getDemoSnapshot).toHaveBeenCalledTimes(1);
    expect(getDashboard).not.toHaveBeenCalled();
    element.shadowRoot.querySelector("lightning-button").click();
    await flushPromises();

    expect(getDemoSnapshot).toHaveBeenCalledTimes(2);
    expect(getLiveSnapshot).not.toHaveBeenCalled();
  });

  it("sends history filters and pagination to the history endpoint", async () => {
    getDashboard.mockResolvedValue({ rows: [], historyCount: 60 });
    getHistory.mockResolvedValue({ rows: sampleRows, totalCount: 60 });

    const element = createElement("c-org-monitoring-dashboard", {
      is: OrgMonitoringDashboard
    });
    document.body.appendChild(element);
    await flushPromises();

    element.shadowRoot.querySelectorAll("lightning-button")[1].click();
    await flushPromises();

    const firstRequest = JSON.parse(getHistory.mock.calls[0][0].requestJson);
    expect(firstRequest.pageNumber).toBe(1);
    expect(firstRequest.pageSize).toBe(50);
    expect(firstRequest.sortBy).toBe("sampledAt");

    element.shadowRoot.querySelectorAll("lightning-button")[4].click();
    await flushPromises();
    const nextRequest = JSON.parse(getHistory.mock.calls[1][0].requestJson);
    expect(nextRequest.pageNumber).toBe(2);
  });
});
