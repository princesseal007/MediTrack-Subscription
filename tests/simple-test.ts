import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";
import { initSimnet } from "@hirosystems/clarinet-sdk";

describe("MediTrack Subscription Tests", () => {
    let simnet: any;
    let provider1: string;
    let provider2: string;
    let provider3: string;

    beforeAll(async () => {
        simnet = await initSimnet();
        const accounts = simnet.getAccounts();
        provider1 = accounts.get("wallet_1")!;
        provider2 = accounts.get("wallet_2")!;
        provider3 = accounts.get("wallet_3")!;
    });

    it("allows healthcare provider to subscribe with basic tier", () => {
        const subscribeCall = simnet.callPublicFn(
            "MediTrack-Subscription",
            "subscribe",
            [Cl.stringAscii("basic")],
            provider1
        );
        expect(subscribeCall.result.type).toBe(7); // ok type
    });

    it("renew-subscription works for existing subscriber", () => {
        simnet.callPublicFn(
            "MediTrack-Subscription",
            "subscribe",
            [Cl.stringAscii("basic")],
            provider1
        );

        const renewCall = simnet.callPublicFn(
            "MediTrack-Subscription",
            "renew-subscription",
            [],
            provider1
        );
        expect(renewCall.result.type).toBe(7); // ok type
    });

    it("renew-subscription fails for non-subscriber", () => {
        const renewCall = simnet.callPublicFn(
            "MediTrack-Subscription",
            "renew-subscription",
            [],
            provider3
        );
        expect(renewCall.result.type).toBe(8); // error type
    });

    it("change-subscription-tier works for valid tiers", () => {
        simnet.callPublicFn(
            "MediTrack-Subscription",
            "subscribe",
            [Cl.stringAscii("basic")],
            provider1
        );

        const changeCall = simnet.callPublicFn(
            "MediTrack-Subscription",
            "change-subscription-tier",
            [Cl.stringAscii("specialist")],
            provider1
        );
        expect(changeCall.result.type).toBe(7); // ok type
    });

    it("change-subscription-tier fails for invalid tier", () => {
        simnet.callPublicFn(
            "MediTrack-Subscription",
            "subscribe",
            [Cl.stringAscii("basic")],
            provider1
        );

        const changeCall = simnet.callPublicFn(
            "MediTrack-Subscription",
            "change-subscription-tier",
            [Cl.stringAscii("invalid")],
            provider1
        );
        expect(changeCall.result.type).toBe(8); // error type
    });

    it("toggle-auto-renewal enables auto-renewal", () => {
        const toggleCall = simnet.callPublicFn(
            "MediTrack-Subscription",
            "toggle-auto-renewal",
            [],
            provider1
        );
        expect(toggleCall.result.type).toBe(7); // ok type
    });

    it("transfer-subscription works for existing subscriber", () => {
        simnet.callPublicFn(
            "MediTrack-Subscription",
            "subscribe",
            [Cl.stringAscii("basic")],
            provider1
        );

        const transferCall = simnet.callPublicFn(
            "MediTrack-Subscription",
            "transfer-subscription",
            [Cl.principal(provider2)],
            provider1
        );
        expect(transferCall.result.type).toBe(7); // ok type
    });

    it("transfer-subscription fails for non-subscriber", () => {
        const transferCall = simnet.callPublicFn(
            "MediTrack-Subscription",
            "transfer-subscription",
            [Cl.principal(provider1)],
            provider3
        );
        expect(transferCall.result.type).toBe(8); // error type
    });

    it("accumulate-points works for any user", () => {
        const pointsCall = simnet.callPublicFn(
            "MediTrack-Subscription",
            "accumulate-points",
            [],
            provider1
        );
        expect(pointsCall.result.type).toBe(7); // ok type
    });

    it("accumulate-points works for new user", () => {
        const pointsCall = simnet.callPublicFn(
            "MediTrack-Subscription",
            "accumulate-points",
            [],
            provider3
        );
        expect(pointsCall.result.type).toBe(7); // ok type
    });
});
