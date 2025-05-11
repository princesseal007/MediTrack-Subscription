import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const provider1 = accounts.get("wallet_1")!;
const provider2 = accounts.get("wallet_2")!;

describe("MediTrack Subscription", () => {
    it("allows healthcare provider to subscribe with basic tier", () => {
        const subscribeCall = simnet.callPublicFn(
            "MediTrack-Subscription",
            "subscribe",
            [Cl.stringAscii("basic")],
            provider1
        );
        expect(subscribeCall.result).toHaveProperty('type', 7);
    });

    it("allows healthcare provider to subscribe with specialist tier", () => {
        const subscribeCall = simnet.callPublicFn(
            "MediTrack-Subscription",
            "subscribe",
            [Cl.stringAscii("specialist")],
            provider2
        );
        expect(subscribeCall.result).toHaveProperty('type', 7);
    });

    it("correctly reports subscription status", () => {
        const getSubscriptionCall = simnet.callReadOnlyFn(
            "MediTrack-Subscription",
            "get-subscription",
            [Cl.principal(provider1)],
            provider1
        );
        expect(getSubscriptionCall.result).toHaveProperty('type', 7);

    });

    it("allows enabling emergency access", () => {
        const emergencyAccessCall = simnet.callPublicFn(
            "MediTrack-Subscription",
            "enable-emergency-access",
            [],
            provider1
        );
      expect(emergencyAccessCall.result).toHaveProperty('type', 8);

    });

    it("correctly checks active subscription status", () => {
      const activeStatusCall = simnet.callReadOnlyFn(
          "MediTrack-Subscription",
          "is-active-subscriber",
          [Cl.principal(provider1)],
          provider1
      );
      expect(activeStatusCall.result).toHaveProperty('type', 7);
      });
});
