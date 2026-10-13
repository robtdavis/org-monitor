import { createElement } from "lwc";
import OrgMonitoringConfiguration from "c/orgMonitoringConfiguration";
import getConfiguration from "@salesforce/apex/OrgMonitoringController.getConfiguration";

jest.mock(
  "@salesforce/apex/OrgMonitoringController.getConfiguration",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Manage_Org_Monitoring",
  () => ({ default: false }),
  {
    virtual: true
  }
);

const flushPromises = () =>
  Array.from({ length: 5 }).reduce(
    (promise) => promise.then(() => undefined),
    Promise.resolve()
  );

describe("c-org-monitoring-configuration", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("does not call the admin-only configuration endpoint for non-admins", async () => {
    const element = createElement("c-org-monitoring-configuration", {
      is: OrgMonitoringConfiguration
    });
    document.body.appendChild(element);
    await flushPromises();

    expect(getConfiguration).not.toHaveBeenCalled();
    expect(element.shadowRoot.textContent).toContain(
      "Only authorized administrators"
    );
    expect(
      element.shadowRoot.querySelector(
        'lightning-textarea[name="emailAddresses"]'
      )
    ).toBeNull();
  });
});
